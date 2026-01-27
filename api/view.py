from rest_framework import viewsets, status, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied
from django.shortcuts import get_object_or_404
from django.http import Http404
import os
import json
import difflib
from datetime import datetime
from django.conf import settings
import threading
from pathlib import Path
import shutil
import hashlib
import uuid as uuid_lib

from .smart_merge import smart_merge

from .models import Repository, Branch, Collaborator
from .serializers import (
    RepositorySerializer,
    RepositoryCreateSerializer,
    RepositoryUpdateSerializer,
    BranchSerializer,
    BranchCreateSerializer,
    SetDefaultBranchSerializer,
    BranchListSerializer,
    CollaboratorSerializer,
    CollaboratorCreateSerializer
)

BASE_DIR = Path(__file__).resolve().parent.parent.parent.parent
MEDIA_ROOT = BASE_DIR / 'media'


def _build_diff_maps(base_lines, other_lines):
    """
    Строит карты отличий base -> other для трёхстороннего слияния.
    Возвращает:
      - status: список длиной len(base_lines) с элементами (tag, j_index_or_None)
      - inserts: словарь {base_index: [строки]}, вставки перед base_index.
    """
    matcher = difflib.SequenceMatcher(a=base_lines, b=other_lines)
    status = [None] * len(base_lines)
    inserts = {}

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == 'equal':
            for offset in range(i2 - i1):
                i = i1 + offset
                status[i] = ('equal', j1 + offset)
        elif tag == 'replace':
            # Часть, которая сопоставляется 1:1
            overlap = min(i2 - i1, j2 - j1)
            for offset in range(overlap):
                i = i1 + offset
                status[i] = ('replace', j1 + offset)
            # Лишние строки в base считаются удалёнными
            for i in range(i1 + overlap, i2):
                status[i] = ('delete', None)
            # Лишние строки в other считаются вставками после i2 - 1
            if j1 + overlap < j2:
                inserts.setdefault(i2, []).extend(other_lines[j1 + overlap : j2])
        elif tag == 'delete':
            for i in range(i1, i2):
                status[i] = ('delete', None)
        elif tag == 'insert':
            inserts.setdefault(i1, []).extend(other_lines[j1:j2])

    # Любые неустановленные статусы трактуем как equal
    for i in range(len(base_lines)):
        if status[i] is None:
            status[i] = ('equal', None)

    return status, inserts


def three_way_merge(base_text, local_text, remote_text):
    """
    Простой строковый 3‑сторонний merge по строкам, аналогичный git diff3.

    Правила:
      - Изменено только в LOCAL (относительно BASE) -> берём LOCAL.
      - Изменено только в REMOTE -> берём REMOTE.
      - Одинаковые изменения в LOCAL и REMOTE -> берём одно значение.
      - Разные изменения в LOCAL и REMOTE -> помечаем конфликтом:
        <<<<<<< LOCAL
        ...local...
        =======
        ...remote...
        >>>>>>> REMOTE
    Обрабатывает добавления и удаления строк.
    Возвращает объединённый текст (str).
    """
    base_lines = base_text.splitlines(keepends=True)
    local_lines = local_text.splitlines(keepends=True)
    remote_lines = remote_text.splitlines(keepends=True)

    local_status, local_inserts = _build_diff_maps(base_lines, local_lines)
    remote_status, remote_inserts = _build_diff_maps(base_lines, remote_lines)

    merged_lines = []

    def emit_conflict(local_block, remote_block):
        # local_block / remote_block - списки строк с разделителями строк
        merged_lines.append("<<<<<<< LOCAL\n")
        if local_block:
            merged_lines.extend(local_block)
            if not local_block[-1].endswith("\n"):
                merged_lines[-1] = merged_lines[-1] + "\n"
        merged_lines.append("=======\n")
        if remote_block:
            merged_lines.extend(remote_block)
            if not remote_block[-1].endswith("\n"):
                merged_lines[-1] = merged_lines[-1] + "\n"
        merged_lines.append(">>>>>>> REMOTE\n")

    def handle_inserts(pos):
        l_ins = local_inserts.get(pos, [])
        r_ins = remote_inserts.get(pos, [])
        if not l_ins and not r_ins:
            return
        if l_ins and not r_ins:
            merged_lines.extend(l_ins)
        elif r_ins and not l_ins:
            merged_lines.extend(r_ins)
        else:
            if l_ins == r_ins:
                merged_lines.extend(l_ins)
            else:
                emit_conflict(l_ins, r_ins)

    # Основной проход по строкам BASE
    for i in range(len(base_lines) + 1):
        # Сначала вставки перед позицией i
        handle_inserts(i)

        if i == len(base_lines):
            break

        base_line = base_lines[i]
        l_tag, l_j = local_status[i]
        r_tag, r_j = remote_status[i]

        # Утилиты для получения строк
        local_line = None
        if l_tag != 'delete' and l_j is not None and 0 <= l_j < len(local_lines):
            local_line = local_lines[l_j]

        remote_line = None
        if r_tag != 'delete' and r_j is not None and 0 <= r_j < len(remote_lines):
            remote_line = remote_lines[r_j]

        # Оба варианта совпадают с BASE
        if l_tag == 'equal' and r_tag == 'equal':
            merged_lines.append(base_line)
            continue

        # Изменено только в LOCAL
        if l_tag != 'equal' and r_tag == 'equal':
            if l_tag == 'delete':
                # Удалено только в LOCAL -> удаляем
                continue
            if local_line is not None:
                merged_lines.append(local_line)
            else:
                # На всякий случай, если не удалось получить строку
                merged_lines.append(base_line)
            continue

        # Изменено только в REMOTE
        if l_tag == 'equal' and r_tag != 'equal':
            if r_tag == 'delete':
                # Удалено только в REMOTE -> удаляем
                continue
            if remote_line is not None:
                merged_lines.append(remote_line)
            else:
                merged_lines.append(base_line)
            continue

        # Изменено и в LOCAL, и в REMOTE
        local_block = [] if l_tag == 'delete' else ([local_line] if local_line is not None else [])
        remote_block = [] if r_tag == 'delete' else ([remote_line] if remote_line is not None else [])

        if local_block == remote_block:
            merged_lines.extend(local_block)
        else:
            emit_conflict(local_block, remote_block)

    return "".join(merged_lines)


class RepositoryViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления репозиториями.
    Поддерживает поиск по public_id через lookup_field.
    """
    #permission_classes = [IsAuthenticated]
    permission_classes = []
    queryset = Repository.objects.all()
    lookup_field = 'public_id'
    lookup_url_kwarg = 'public_id'

    @action(detail=True, methods=['get'], url_path='tree/(?P<branch_name>[^/.]+)')
    def get_tree(self, request, public_id=None, branch_name='main'):
        """
        Возвращает список файлов и папок в конкретной ветке.
        URL: /api/repositories/{public_id}/tree/{branch_name}/
        """
        repository = self.get_object()
        # Определяем путь к папке ветки
        # (Убедитесь, что при создании веток вы создаете соответствующие папки)
        repo_path = MEDIA_ROOT / 'repositories' / str(repository.id) / branch_name

        if not repo_path.exists():
            return Response({'error': f'Ветка {branch_name} не инициализирована на сервере'}, status=404)

        # Рекурсивно или только верхний уровень собираем файлы
        items = []
        try:
            for entry in os.scandir(repo_path):
                items.append({
                    'name': entry.name,
                    'is_dir': entry.is_dir(),
                    'path': entry.name, # Для вложенности тут будет относительный путь
                    'size': entry.stat().st_size if entry.is_file() else None
                })
        except Exception as e:
            return Response({'error': str(e)}, status=500)

        return Response({
            'repository': repository.name,
            'branch': branch_name,
            'items': sorted(items, key=lambda x: (not x['is_dir'], x['name']))
        })

    @action(detail=True, methods=['get'], url_path='blob/(?P<branch_name>[^/.]+)')
    def get_blob(self, request, public_id=None, branch_name='main'):
        """
        Возвращает содержимое конкретного файла.
        URL: /api/repositories/{public_id}/blob/{branch_name}/?path=folder/file.py
        """
        repository = self.get_object()
        file_relative_path = request.query_params.get('path')

        if not file_relative_path:
            return Response({'error': 'Не указан путь к файлу (path)'}, status=400)

        # Безопасное формирование пути
        full_path = (MEDIA_ROOT / 'repositories' / str(repository.id) / branch_name / file_relative_path).resolve()
        
        # Защита от выхода за пределы папки репозитория (Path Traversal)
        base_repo_path = (MEDIA_ROOT / 'repositories' / str(repository.id) / branch_name).resolve()
        if not str(full_path).startswith(str(base_repo_path)):
            return Response({'error': 'Доступ запрещен'}, status=403)

        if not full_path.exists() or not full_path.is_file():
            return Response({'error': 'Файл не найден'}, status=404)

        try:
            # Читаем содержимое. Если файлы бинарные, нужна другая логика.
            with open(full_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            return Response({
                'name': full_path.name,
                'path': file_relative_path,
                'content': content,
                'size': full_path.stat().st_size
            })
        except UnicodeDecodeError:
            return Response({'error': 'Файл является бинарным и не может быть отображен как текст'}, status=400)

    def get_queryset(self):
        """Возвращаем только репозитории, доступные текущему пользователю"""
        queryset = super().get_queryset()
        user_id = self.request.user.id
        
        # Фильтруем репозитории по правам доступа
        accessible_repos = []
        for repo in queryset:
            if repo.can_user_view(user_id):
                accessible_repos.append(repo.id)
        
        return queryset.filter(id__in=accessible_repos)

    def get_serializer_class(self):
        """Выбираем сериализатор в зависимости от действия"""
        if self.action == 'create':
            return RepositoryCreateSerializer
        elif self.action in ['update', 'partial_update']:
            return RepositoryUpdateSerializer
        return RepositorySerializer

    def create(self, request, *args, **kwargs):
        """
        Создание репозитория с физической папкой в файловой системе.
        POST /api/version_management/repositories/
        """
        serializer = RepositoryCreateSerializer(data=request.data, context={'request': request})
        
        if serializer.is_valid():
            try:
                # Создаем репозиторий в базе данных
                repository = serializer.save()
                
                # Получаем UUID из созданного репозитория
                repo_uuid = str(repository.public_id)
                
                # Формируем путь для физического репозитория
                repo_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
                
                # Создаем структуру папок
                try:
                    # Основная папка репозитория
                    os.makedirs(repo_path, exist_ok=True)
                    print(f"--- [INFO] Создана папка репозитория: {repo_path} ---")
                    
                    # Папка для веток
                    branches_path = os.path.join(repo_path, 'branches')
                    os.makedirs(branches_path, exist_ok=True)
                    
                    # Создаем папку для дефолтной ветки
                    default_branch = repository.branches.filter(is_default=True).first()
                    if default_branch:
                        default_branch_path = os.path.join(branches_path, default_branch.name)
                        os.makedirs(default_branch_path, exist_ok=True)
                        
                        # Создаем папку для коммитов в дефолтной ветке
                        commits_path = os.path.join(default_branch_path, 'commits')
                        os.makedirs(commits_path, exist_ok=True)

                        readme_path = os.path.join(default_branch_path, 'README.md')
                        with open(readme_path, 'w', encoding='utf-8') as f:
                            f.write(f"# {default_branch.name}\n\n")
                            f.write(f"{repository.description or 'No description provided.'}\n\n")

                        
                        # Создаем начальный коммит (опционально)
                        initial_commit_dir = os.path.join(commits_path, 'initial')
                        os.makedirs(initial_commit_dir, exist_ok=True)
                        
                        # Создаем файл с информацией о начальном коммите
                        initial_commit_info = {
                            'hash': 'initial',
                            'parents': [],
                            'message': 'Initial commit',
                            'branch': default_branch.name,
                            'created_at': repository.created_at.isoformat(),
                            'author': 'System',
                            'files': []
                        }
                        
                        initial_commit_path = os.path.join(default_branch_path, 'commit.json')
                        with open(initial_commit_path, 'w', encoding='utf-8') as f:
                            json.dump(initial_commit_info, f, indent=2, ensure_ascii=False)
                       
                    # Создаем файл README.md в корне репозитория
                    # readme_path = os.path.join(repo_path, 'README.md')
                    # with open(readme_path, 'w', encoding='utf-8') as f:
                    #     f.write(f"# {repository.name}\n\n")
                    #     f.write(f"{repository.description or 'No description provided.'}\n\n")
                    #     f.write(f"Created: {repository.created_at}\n")
                    #     f.write(f"UUID: {repo_uuid}\n")
                    #     f.write(f"Owner: User #{repository.owner_id}\n")
                    #     f.write(f"Private: {repository.is_private}\n")
                    #     f.write(f"Read-only: {repository.is_read_only}\n")
                    # Создаем файл README.md ветке
                    
                    # Создаем файл с метаинформацией о репозитории
                    repo_info_path = os.path.join(repo_path, '.repo_info.json')
                    repo_info = {
                        'uuid': repo_uuid,
                        'name': repository.name,
                        'description': repository.description,
                        'is_private': repository.is_private,
                        'is_read_only': repository.is_read_only,
                        'owner_id': repository.owner_id,
                        'created_at': repository.created_at.isoformat(),
                        'branches': [
                            {
                                'name': branch.name,
                                'is_default': branch.is_default,
                                'created_at': branch.created_at.isoformat()
                            }
                            for branch in repository.branches.all()
                        ]
                    }
                    
                    with open(repo_info_path, 'w', encoding='utf-8') as f:
                        json.dump(repo_info, f, indent=2, ensure_ascii=False)
                    
                    print(f"--- [INFO] Физическая структура репозитория создана успешно ---")
                    
                    # Добавляем информацию о физическом пути в ответ
                    response_data = RepositorySerializer(repository, context={'request': request}).data
                    response_data['physical_path'] = repo_path
                    response_data['physical_structure_created'] = True
                    
                    return Response(response_data, status=status.HTTP_201_CREATED)
                    
                except OSError as e:
                    print(f"--- [ERROR] Ошибка создания файловой структуры: {e} ---")
                    # Удаляем репозиторий из базы данных, если не удалось создать файлы
                    repository.delete()
                    return Response({
                        'success': False,
                        'error': f'Не удалось создать физическую структуру репозитория: {str(e)}'
                    }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
                    
            except Exception as e:
                print(f"--- [ERROR] Ошибка при создании репозитория: {e} ---")
                return Response({
                    'success': False,
                    'error': f'Ошибка при создании репозитория: {str(e)}'
                }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['post'])
    def set_default_branch(self, request, public_id=None):
        """
        Установить ветку по умолчанию для репозитория.
        """
        repository = self.get_object()
        
        # Проверяем права доступа
        #if not repository.can_user_modify(request.user.id):
        #    raise PermissionDenied("У вас недостаточно прав для изменения этого репозитория")

        branch_id = request.data.get('branch_id')
        branch_name = request.data.get('branch_name')

        if branch_id:
            branch = get_object_or_404(
                Branch,
                id=branch_id,
                repository=repository
            )
        elif branch_name:
            branch = get_object_or_404(
                Branch,
                name=branch_name,
                repository=repository
            )
        else:
            return Response({
                'error': 'Необходимо указать branch_id или branch_name'
            }, status=status.HTTP_400_BAD_REQUEST)

        Branch.set_default_branch(branch)

        return Response({
            'success': True,
            'message': f'Ветка "{branch.name}" установлена как ветка по умолчанию',
            'repository': self.get_serializer(repository, context={'request': request}).data,
            'branch': {
                'id': branch.id,
                'name': branch.name,
                'is_default': branch.is_default
            }
        })

    @action(detail=True, methods=['get'])
    def branches(self, request, public_id=None):
        """
        Получить все ветки репозитория.
        GET /repositories/{public_id}/branches/
        """
        repository = self.get_object()
        
        # Проверяем права доступа на просмотр
        #if not repository.can_user_view(request.user.id):
        #    raise PermissionDenied("У вас нет доступа к этому репозиторию")
        
        branches = repository.branches.all()

        serializer = BranchListSerializer(branches, many=True, context={'request': request})

        return Response({
            'repository': {
                'id': repository.id,
                'public_id': repository.public_id,
                'name': repository.name
            },
            'branches': serializer.data,
            'count': branches.count()
        })


    def destroy(self, request, *args, **kwargs):
        """
        Удаляет репозиторий из БД и стирает файлы из media/version_management/
        DELETE /api/version_management/repositories/{public_id}/
        """
        print(f"--- [INFO] Попытка удаления репозитория с UUID: {kwargs.get('public_id')} ---")
        
        # 1. Пытаемся найти объект
        instance = self.get_object()
        
        # Проверяем, что пользователь является владельцем
        # if instance.owner_id != request.user.id:
        #     # Проверяем, является ли пользователь администратором
        #     admin_collaborator = instance.collaborators.filter(
        #         user_id=request.user.id,
        #         role='admin'
        #     ).first()
        #     if not admin_collaborator:
        #         raise PermissionDenied("Только владелец или администратор может удалить репозиторий")
        
        repo_name = instance.name
        repo_uuid = str(instance.public_id)
        
        # 2. Формируем путь к папке (media/version_management/UUID)
        repo_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
        
        print(f"--- [INFO] Путь к файлам: {repo_path} ---")
        
        try:
            # 3. Удаляем из базы данных
            instance.delete()
            print(f"--- [INFO] Запись в БД удалена успешно ---")
            
            # 4. Удаляем физическую папку
            if os.path.exists(repo_path):
                shutil.rmtree(repo_path)
                status_msg = "Репозиторий и файлы удалены."
                print(f"--- [INFO] Папка удалена ---")
            else:
                status_msg = "Запись удалена, но папка с файлами не была найдена на диске."
                print(f"--- [INFO] Папка не найдена, удалять нечего ---")
            
            return Response({
                "success": True,
                "message": status_msg,
                "repo_name": repo_name
            }, status=status.HTTP_200_OK)
            
        except Exception as e:
            print(f"--- [INFO] ОШИБКА: {str(e)} ---")
            return Response({
                "success": False,
                "message": f"Произошла ошибка: {str(e)}"
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(detail=True, methods=['post'], url_path='commits/create')
    def commit_create(self, request, public_id=None):
        """
        Создать коммит для репозитория.
        POST /api/repositories/{id}/commits/create/

        При повторном вызове не создаётся новый коммит, а добавляются изменения
        в существующий, до тех пор пока коммит не отправлен на сервер (push).
        """
        repository = self.get_object()
        
        # Проверяем права на запись
        #if not repository.can_user_modify(request.user.id):
        #    raise PermissionDenied("У вас недостаточно прав для создания коммитов в этом репозитории")

        # Получаем данные из запроса
        message = request.data.get('message')
        files = request.data.get('files', [])  # Список файлов с содержимым
        branch_name = request.data.get('branch_name')

        # Валидация
        if not message:
            return Response({
                'success': False,
                'error': 'Необходимо указать сообщение коммита (message)'
            }, status=status.HTTP_400_BAD_REQUEST)

        if not files:
            return Response({
                'success': False,
                'error': 'Необходимо указать файлы для коммита (files)'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Определяем ветку
        if branch_name:
            try:
                branch = Branch.objects.get(repository=repository, name=branch_name)
            except Branch.DoesNotExist:
                return Response({
                    'success': False,
                    'error': f'Ветка "{branch_name}" не найдена в репозитории'
                }, status=status.HTTP_404_NOT_FOUND)
        else:
            # Используем ветку по умолчанию
            branch = repository.branches.filter(is_default=True).first()
            if not branch:
                return Response({
                    'success': False,
                    'error': 'Ветка по умолчанию не найдена. Укажите branch_name'
                }, status=status.HTTP_400_BAD_REQUEST)

        try:
            # Путь к папке ветки
            repo_uuid = str(repository.public_id)
            base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
            branches_path = os.path.join(base_path, 'branches')
            branch_path = os.path.join(branches_path, branch.name)
            pending_commit_path = os.path.join(branch_path, 'pending_commit.json')

            # Проверяем, существует ли незавершенный коммит
            pending_commit = None
            if os.path.exists(pending_commit_path):
                try:
                    with open(pending_commit_path, 'r', encoding='utf-8') as f:
                        pending_commit = json.load(f)
                except (json.JSONDecodeError, IOError) as e:
                    # Если файл поврежден, создаем новый коммит
                    print(f"Warning: Не удалось прочитать pending_commit.json: {e}")
                    pending_commit = None

            # Если есть незавершенный коммит, добавляем изменения в него
            if pending_commit and not pending_commit.get('pushed', False):
                # Обновляем существующий коммит
                existing_files = {f['path']: f for f in pending_commit.get('files', [])}

                # Добавляем или обновляем файлы
                for file_data in files:
                    file_path = file_data.get('path')
                    if not file_path:
                        continue

                    # Обновляем или добавляем файл
                    existing_files[file_path] = {
                        'path': file_path,
                        'content': file_data.get('content', ''),
                        'action': file_data.get('action', 'modified')
                    }

                # Обновляем коммит
                pending_commit['files'] = list(existing_files.values())
                pending_commit['updated_at'] = datetime.now().isoformat()
                pending_commit['message'] = message  # Обновляем сообщение
                pending_commit['author'] = f"User #{request.user.id}"  # Добавляем автора

                commit_hash = pending_commit.get('hash')
                is_new_commit = False
            else:
                # Создаем новый коммит
                commit_hash = self._generate_commit_hash(repository, branch, message, files)
                pending_commit = {
                    'hash': commit_hash,
                    'message': message,
                    'branch': branch.name,
                    'repository_uuid': repo_uuid,
                    'author': f"User #{request.user.id}",
                    'files': [
                        {
                            'path': f.get('path'),
                            'content': f.get('content', ''),
                            'action': f.get('action', 'modified')
                        }
                        for f in files if f.get('path')
                    ],
                    'created_at': datetime.now().isoformat(),
                    'updated_at': datetime.now().isoformat(),
                    'pushed': False
                }
                is_new_commit = True

            # Создаем структуру папок, если нужно
            os.makedirs(branch_path, exist_ok=True)

            # Сохраняем коммит
            with open(pending_commit_path, 'w', encoding='utf-8') as f:
                json.dump(pending_commit, f, indent=2, ensure_ascii=False)

            return Response({
                'success': True,
                'message': 'Коммит создан' if is_new_commit else 'Коммит обновлен',
                'commit': {
                    'hash': commit_hash,
                    'message': message,
                    'branch': branch.name,
                    'files_count': len(pending_commit['files']),
                    'is_new': is_new_commit,
                    'pushed': False,
                    'author': pending_commit.get('author')
                }
            }, status=status.HTTP_201_CREATED if is_new_commit else status.HTTP_200_OK)

        except Exception as e:
            return Response({
                'success': False,
                'error': f'Ошибка при создании коммита: {str(e)}'
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(detail=True, methods=['get'], url_path='commits')
    def commits_list(self, request, public_id=None):
        """
        Получить всю историю коммитов из репозитория.
        GET /api/repositories/{id}/commits/

        Возвращает список всех коммитов из всех веток, отсортированных по дате (новые первыми).
        """
        repository = self.get_object()
        
        # Проверяем права на просмотр
        #if not repository.can_user_view(request.user.id):
        #    raise PermissionDenied("У вас нет доступа к этому репозиторию")

        try:
            repo_uuid = str(repository.public_id)
            base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
            branches_path = os.path.join(base_path, 'branches')

            all_commits = []

            # Проверяем, существует ли папка branches
            if not os.path.exists(branches_path):
                return Response({
                    'success': True,
                    'commits': [],
                    'count': 0,
                    'repository': {
                        'id': repository.id,
                        'public_id': repository.public_id,
                        'name': repository.name
                    }
                })

            # Проходим по всем веткам репозитория
            branches = repository.branches.all()

            for branch in branches:
                branch_path = os.path.join(branches_path, branch.name)

                if not os.path.exists(branch_path):
                    continue

                # 1. Проверяем pending_commit.json (неотправленные коммиты)
                pending_commit_path = os.path.join(branch_path, 'pending_commit.json')
                if os.path.exists(pending_commit_path):
                    try:
                        with open(pending_commit_path, 'r', encoding='utf-8') as f:
                            pending_commit = json.load(f)

                        # Добавляем только если коммит не отправлен
                        if not pending_commit.get('pushed', False):
                            commit_data = {
                                'hash': pending_commit.get('hash', 'pending'),
                                'message': pending_commit.get('message', ''),
                                'branch': branch.name,
                                'files_count': len(pending_commit.get('files', [])),
                                'created_at': pending_commit.get('created_at', ''),
                                'updated_at': pending_commit.get('updated_at', ''),
                                'pushed': False,
                                'author': pending_commit.get('author', f'User #{request.user.id}')
                            }
                            all_commits.append(commit_data)
                    except (json.JSONDecodeError, IOError) as e:
                        print(f"Warning: Не удалось прочитать pending_commit.json для ветки {branch.name}: {e}")

                # 2. Проверяем папку commits/ (отправленные коммиты)
                commits_path = os.path.join(branch_path, 'commits')
                if os.path.exists(commits_path) and os.path.isdir(commits_path):
                    # Проходим по всем подпапкам (каждая подпапка - коммит по hash)
                    for commit_dir in os.listdir(commits_path):
                        commit_dir_path = os.path.join(commits_path, commit_dir)

                        if not os.path.isdir(commit_dir_path):
                            continue

                        # Ищем commit.json в папке коммита
                        commit_json_path = os.path.join(commit_dir_path, 'commit.json')
                        if os.path.exists(commit_json_path):
                            try:
                                with open(commit_json_path, 'r', encoding='utf-8') as f:
                                    commit_data = json.load(f)

                                # Добавляем информацию о коммите
                                commit_info = {
                                    'hash': commit_data.get('hash', commit_dir),
                                    'message': commit_data.get('message', ''),
                                    'branch': branch.name,
                                    'files_count': len(commit_data.get('files', [])),
                                    'created_at': commit_data.get('created_at', ''),
                                    'updated_at': commit_data.get('updated_at', ''),
                                    'pushed': True,
                                    'pushed_at': commit_data.get('pushed_at', ''),
                                    'author': commit_data.get('author', 'Unknown')
                                }
                                all_commits.append(commit_info)
                            except (json.JSONDecodeError, IOError) as e:
                                print(f"Warning: Не удалось прочитать commit.json для {commit_dir}: {e}")
                        else:
                            # Если нет commit.json, но есть папка, создаем базовую информацию
                            commit_info = {
                                'hash': commit_dir,
                                'message': 'Коммит без метаданных',
                                'branch': branch.name,
                                'files_count': 0,
                                'created_at': datetime.fromtimestamp(
                                    os.path.getctime(commit_dir_path)
                                ).isoformat(),
                                'updated_at': datetime.fromtimestamp(
                                    os.path.getmtime(commit_dir_path)
                                ).isoformat(),
                                'pushed': True,
                                'author': 'Unknown'
                            }
                            all_commits.append(commit_info)

            # Сортируем коммиты по дате создания (новые первыми)
            all_commits.sort(
                key=lambda x: x.get('created_at', '') or x.get('updated_at', ''),
                reverse=True
            )

            return Response({
                'success': True,
                'commits': all_commits,
                'count': len(all_commits),
                'repository': {
                    'id': repository.id,
                    'public_id': repository.public_id,
                    'name': repository.name
                }
            })

        except Exception as e:
            return Response({
                'success': False,
                'error': f'Ошибка при получении списка коммитов: {str(e)}',
                'commits': [],
                'count': 0
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(detail=True, methods=['get'], url_path=r'branches/(?P<branch_name>[^/]+)/files')
    def get_branch_files(self, request, public_id=None, branch_name=None):
        """
        Получить список файлов в ветке (из последнего коммита).
        GET /api/repositories/{id}/branches/{branch_name}/files/
        """
        repository = self.get_object()
        repo_uuid = str(repository.public_id)
        
        try:
            base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
            branch_path = os.path.join(base_path, 'branches', branch_name)
            
            if not os.path.exists(branch_path):
                 return Response({
                    'error': f'Ветка {branch_name} не найдена',
                    'files': []
                 }, status=status.HTTP_404_NOT_FOUND)

            # Стратегия:
            # 1. Ищем файлы в корне ветки (branch_path) - тут лежит README.md и commit.json
            # 2. Ищем папку commits/ и последний коммит там
            
            target_dirs = [branch_path]
            
            commits_path = os.path.join(branch_path, 'commits')
            if os.path.exists(commits_path) and os.path.isdir(commits_path):
                # Находим последний измененный коммит
                commits = []
                for commit_dir in os.listdir(commits_path):
                    full_path = os.path.join(commits_path, commit_dir)
                    if os.path.isdir(full_path):
                        commits.append((os.path.getmtime(full_path), full_path))
                
                if commits:
                    # Сортируем по времени (последний первым)
                    commits.sort(key=lambda x: x[0], reverse=True)
                    target_dirs.append(commits[0][1])

            files_map = {}
            for d in target_dirs:
                if not os.path.exists(d): continue
                
                for item in os.listdir(d):
                    if item in ['commit.json', 'pending_commit.json', 'commits', '.repo_info.json', '.git']:
                        continue
                        
                    item_path = os.path.join(d, item)
                    is_dir = os.path.isdir(item_path)
                    
                    # Добавляем или перезаписываем (приоритет у последнего, т.е. коммита)
                    files_map[item] = {
                        'name': item,
                        'path': item,
                        'type': 'dir' if is_dir else 'file',
                        'size': os.path.getsize(item_path) if not is_dir else 0,
                        'last_date': datetime.fromtimestamp(os.path.getmtime(item_path)).strftime('%Y-%m-%d %H:%M')
                    }

            files_list = list(files_map.values())
            files_list.sort(key=lambda x: x['name'])

            return Response(files_list, status=status.HTTP_200_OK)

        except Exception as e:
            print(f"Error getting branch files: {e}")
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(detail=True, methods=['get'], url_path=r'commits/(?P<commit_hash>[^/.]+)')
    def commit_retrieve(self, request, public_id=None, commit_hash=None):
        """
        Получить метаданные коммита по хешу.
        GET /api/repositories/{id}/commits/{commit_hash}/

        Возвращает JSON с метаданными коммита (hash, message, branch, author,
        created_at, files и т.п.) из commit.json или pending_commit.json.
        """
        repository = self.get_object()
        
        # Проверяем права на просмотр
        #if not repository.can_user_view(request.user.id):
        #    raise PermissionDenied("У вас нет доступа к этому репозиторию")

        repo_uuid = str(repository.public_id)
        base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
        branches_path = os.path.join(base_path, 'branches')

        if not os.path.exists(branches_path) or not os.path.isdir(branches_path):
            return Response({
                'error': 'Коммит не найден',
                'commit_hash': commit_hash
            }, status=status.HTTP_404_NOT_FOUND)

        for branch_name in os.listdir(branches_path):
            branch_path = os.path.join(branches_path, branch_name)
            if not os.path.isdir(branch_path):
                continue
            pending_path = os.path.join(branch_path, 'pending_commit.json')
            if os.path.exists(pending_path):
                try:
                    with open(pending_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    if not data.get('pushed', False) and data.get('hash') == commit_hash:
                        if 'branch' not in data:
                            data = {**data, 'branch': branch_name}
                        return Response(data)
                except (json.JSONDecodeError, IOError):
                    pass

        for branch_name in os.listdir(branches_path):
            branch_path = os.path.join(branches_path, branch_name)
            if not os.path.isdir(branch_path):
                continue
            commits_path = os.path.join(branch_path, 'commits')
            if not os.path.exists(commits_path) or not os.path.isdir(commits_path):
                continue
            for commit_dir in os.listdir(commits_path):
                commit_dir_path = os.path.join(commits_path, commit_dir)
                if not os.path.isdir(commit_dir_path):
                    continue
                commit_json_path = os.path.join(commit_dir_path, 'commit.json')
                if os.path.exists(commit_json_path):
                    try:
                        with open(commit_json_path, 'r', encoding='utf-8') as f:
                            data = json.load(f)
                    except (json.JSONDecodeError, IOError):
                        continue
                    if data.get('hash') == commit_hash or commit_dir == commit_hash:
                        return Response(data)

        return Response({
            'error': 'Коммит не найден',
            'commit_hash': commit_hash
        }, status=status.HTTP_404_NOT_FOUND)

    @action(detail=True, methods=['get'], url_path=r'commits/(?P<commit_hash>[^/.]+)/diff')
    def commit_diff(self, request, public_id=None, commit_hash=None):
        """
        Получить унифицированный diff коммита (конкретные изменения).
        GET /api/repositories/{id}/commits/{commit_hash}/diff/

        Возвращает текст в формате unified diff: ---/+++ заголовки, @@ hunks, -/+ строки.
        Для новых файлов: --- /dev/null, для удалённых: +++ /dev/null.
        """
        repository = self.get_object()
        
        # Проверяем права на просмотр
        #if not repository.can_user_view(request.user.id):
        #    raise PermissionDenied("У вас нет доступа к этому репозиторию")

        repo_uuid = str(repository.public_id)
        base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
        branches_path = os.path.join(base_path, 'branches')

        if not os.path.exists(branches_path) or not os.path.isdir(branches_path):
            return Response({
                'error': 'Коммит не найден',
                'commit_hash': commit_hash
            }, status=status.HTTP_404_NOT_FOUND)

        commit_data = None
        found_branch_path = None

        for branch_name in os.listdir(branches_path):
            branch_path = os.path.join(branches_path, branch_name)
            if not os.path.isdir(branch_path):
                continue
            pending_path = os.path.join(branch_path, 'pending_commit.json')
            if os.path.exists(pending_path):
                try:
                    with open(pending_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                    if not data.get('pushed', False) and data.get('hash') == commit_hash:
                        commit_data = data
                        found_branch_path = branch_path
                        break
                except (json.JSONDecodeError, IOError):
                    pass

        if commit_data is None:
            for branch_name in os.listdir(branches_path):
                branch_path = os.path.join(branches_path, branch_name)
                if not os.path.isdir(branch_path):
                    continue
                commits_path = os.path.join(branch_path, 'commits')
                if not os.path.exists(commits_path) or not os.path.isdir(commits_path):
                    continue
                for commit_dir in os.listdir(commits_path):
                    commit_dir_path = os.path.join(commits_path, commit_dir)
                    if not os.path.isdir(commit_dir_path):
                        continue
                    commit_json_path = os.path.join(commit_dir_path, 'commit.json')
                    if os.path.exists(commit_json_path):
                        try:
                            with open(commit_json_path, 'r', encoding='utf-8') as f:
                                data = json.load(f)
                        except (json.JSONDecodeError, IOError):
                            continue
                        if data.get('hash') == commit_hash or commit_dir == commit_hash:
                            commit_data = data
                            found_branch_path = branch_path
                            break
                if commit_data is not None:
                    break

        if commit_data is None:
            return Response({
                'error': 'Коммит не найден',
                'commit_hash': commit_hash
            }, status=status.HTTP_404_NOT_FOUND)

        our_created = commit_data.get('created_at') or commit_data.get('updated_at') or ''
        commits_path = os.path.join(found_branch_path, 'commits')
        parent_data = None

        if os.path.exists(commits_path) and os.path.isdir(commits_path):
            candidates = []
            for commit_dir in os.listdir(commits_path):
                commit_dir_path = os.path.join(commits_path, commit_dir)
                if not os.path.isdir(commit_dir_path):
                    continue
                commit_json_path = os.path.join(commit_dir_path, 'commit.json')
                if not os.path.exists(commit_json_path):
                    continue
                try:
                    with open(commit_json_path, 'r', encoding='utf-8') as f:
                        cdata = json.load(f)
                except (json.JSONDecodeError, IOError):
                    continue
                if cdata.get('hash') == commit_hash or commit_dir == commit_hash:
                    continue
                created = cdata.get('created_at') or cdata.get('updated_at') or ''
                candidates.append((created, cdata))
            candidates.sort(key=lambda x: x[0])
            for created, cdata in reversed(candidates):
                if created < our_created:
                    parent_data = cdata
                    break

        parent_files = {}
        if parent_data:
            parent_files = {
                f['path']: f.get('content', '')
                for f in parent_data.get('files', [])
                if f.get('path')
            }

        def _content_to_lines(content):
            if content is None:
                content = ''
            return [line + '\n' for line in (content or '').splitlines()] if (content or '') else []

        diff_parts = []
        for f in commit_data.get('files', []):
            path = f.get('path')
            if not path:
                continue
            content = f.get('content', '')
            action = f.get('action', 'modified')

            if action == 'added' or (path not in parent_files and content):
                fromfile, tofile = '/dev/null', 'b/' + path
                fromlines, tolines = [], _content_to_lines(content)
            elif action == 'deleted' or (path in parent_files and not content):
                fromfile, tofile = 'a/' + path, '/dev/null'
                fromlines = _content_to_lines(parent_files.get(path, ''))
                tolines = []
            else:
                fromfile, tofile = 'a/' + path, 'b/' + path
                fromlines = _content_to_lines(parent_files.get(path, ''))
                tolines = _content_to_lines(content)

            ud = list(difflib.unified_diff(fromlines, tolines, fromfile=fromfile, tofile=tofile, lineterm='\n'))
            if ud:
                diff_parts.append(''.join(ud))

        diff_text = '\n'.join(diff_parts) if diff_parts else ''

        return Response(diff_text, content_type='text/plain; charset=utf-8')

    def _generate_commit_hash(self, repository, branch, message, files):
        """
        Генерирует хеш для коммита на основе репозитория, ветки, сообщения и файлов.
        """
        # Создаем строку для хеширования
        content = f"{repository.public_id}{branch.name}{message}"
        for file_data in files:
            content += f"{file_data.get('path', '')}{file_data.get('content', '')}"

        # Генерируем хеш
        hash_obj = hashlib.sha256(content.encode('utf-8'))
        return hash_obj.hexdigest()[:16]

    @action(detail=True, methods=['get', 'post', 'delete'], url_path='collaborators')
    def collaborators(self, request, public_id=None):
        """
        Управление коллабораторами репозитория.
        GET: Получить список коллабораторов
        POST: Добавить нового коллаборатора
        DELETE: Удалить коллаборатора
        """
        repository = self.get_object()
        
        # Проверяем права на управление коллабораторами
        if request.user.id != repository.owner_id:
            # Проверяем, является ли пользователь администратором
            admin_collaborator = repository.collaborators.filter(
                user_id=request.user.id,
                role='admin'
            ).first()
            if not admin_collaborator:
                raise PermissionDenied("Только владелец или администратор может управлять коллабораторами")
        
        if request.method == 'GET':
            # Получаем список коллабораторов
            collaborators = repository.collaborators.all()
            serializer = CollaboratorSerializer(collaborators, many=True)
            return Response({
                'repository': {
                    'id': repository.id,
                    'public_id': repository.public_id,
                    'name': repository.name
                },
                'collaborators': serializer.data,
                'count': collaborators.count()
            })
        
        elif request.method == 'POST':
            # Добавляем нового коллаборатора
            serializer = CollaboratorCreateSerializer(
                data=request.data,
                context={'request': request, 'repository': repository}
            )
            
            if serializer.is_valid():
                # Создаем коллаборатора
                collaborator = Collaborator.objects.create(
                    repository=repository,
                    user_id=serializer.validated_data['user_id'],
                    role=serializer.validated_data['role']
                )
                
                # Сериализуем ответ
                response_serializer = CollaboratorSerializer(collaborator)
                
                return Response({
                    'success': True,
                    'message': 'Коллаборатор успешно добавлен',
                    'collaborator': response_serializer.data
                }, status=status.HTTP_201_CREATED)
            
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
        
        elif request.method == 'DELETE':
            # Удаляем коллаборатора
            user_id = request.data.get('user_id')
            
            if not user_id:
                return Response({
                    'error': 'Необходимо указать user_id'
                }, status=status.HTTP_400_BAD_REQUEST)
            
            # Нельзя удалить владельца
            if user_id == repository.owner_id:
                return Response({
                    'error': 'Нельзя удалить владельца репозитория'
                }, status=status.HTTP_400_BAD_REQUEST)
            
            # Находим и удаляем коллаборатора
            collaborator = repository.collaborators.filter(user_id=user_id).first()
            
            if not collaborator:
                return Response({
                    'error': 'Коллаборатор не найден'
                }, status=status.HTTP_404_NOT_FOUND)
            
            collaborator.delete()
            
            return Response({
                'success': True,
                'message': 'Коллаборатор успешно удален'
            })
    
    @action(detail=True, methods=['post'], url_path='collaborators/(?P<collaborator_id>[^/.]+)')
    def update_collaborator(self, request, public_id=None, collaborator_id=None):
        """
        Обновление роли коллаборатора.
        """
        repository = self.get_object()
        
        # Проверяем права на управление коллабораторами
        if request.user.id != repository.owner_id:
            # Проверяем, является ли пользователь администратором
            admin_collaborator = repository.collaborators.filter(
                user_id=request.user.id,
                role='admin'
            ).first()
            if not admin_collaborator:
                raise PermissionDenied("Только владелец или администратор может обновлять коллабораторов")
        
        # Находим коллаборатора
        try:
            collaborator = Collaborator.objects.get(id=collaborator_id, repository=repository)
        except Collaborator.DoesNotExist:
            return Response({
                'error': 'Коллаборатор не найден'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Обновляем роль
        new_role = request.data.get('role')
        
        if not new_role:
            return Response({
                'error': 'Необходимо указать новую роль'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if new_role not in ['read', 'write', 'admin']:
            return Response({
                'error': 'Некорректная роль. Допустимые значения: read, write, admin'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        collaborator.role = new_role
        collaborator.save()
        
        serializer = CollaboratorSerializer(collaborator)
        
        return Response({
            'success': True,
            'message': 'Роль коллаборатора обновлена',
            'collaborator': serializer.data
        })

    @action(detail=True, methods=['get'], url_path='files')
    def get_files(self, request, public_id=None):

        instance = self.get_object()

        # Путь: media/version_management/{repo_uuid}/
        repo_path = os.path.join(settings.MEDIA_ROOT, 'version_management', str(instance.public_id))

        if not os.path.exists(repo_path):

            return Response({"error": "Папка репозитория не найдена"}, status=404)

        structure = get_directory_structure(repo_path)

        return Response({
            "repository": instance.name,
            "structure": structure
        })

    @action(detail=False, methods=['post'], url_path='smart_merge')
    def smart_merge_action(self, request):
        """
        Smart 3-way merge with heuristics and conflict analysis.

        Body:
        {
          "base_text": "...",
          "local_text": "...",
          "remote_text": "..."
        }

        Response:
        {
          "merged_text": "...",
          "conflicts": {...},
          "quality": {...}
        }
        """
        base_text = request.data.get('base_text', '') or ''
        local_text = request.data.get('local_text', '') or ''
        remote_text = request.data.get('remote_text', '') or ''

        result = smart_merge(base_text, local_text, remote_text)

        return Response(result, status=status.HTTP_200_OK)

    @action(detail=False, methods=['post'], url_path='three_way_merge')
    def three_way_merge_action(self, request):
        """
        API‑endpoint для выполнения трёхстороннего слияния текста.

        Ожидает в теле запроса JSON:
        {
          "base_text": "...",
          "local_text": "...",
          "remote_text": "..."
        }

        Возвращает:
        {
          "merged_text": "..."
        }
        """
        base_text = request.data.get('base_text', '') or ''
        local_text = request.data.get('local_text', '') or ''
        remote_text = request.data.get('remote_text', '') or ''

        merged_text = three_way_merge(base_text, local_text, remote_text)

        return Response({
            'merged_text': merged_text
        }, status=status.HTTP_200_OK)


class BranchViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления ветками.
    """
    #permission_classes = [IsAuthenticated]
    permission_classes = []
    queryset = Branch.objects.all()

    def get_serializer_class(self):
        """Выбираем сериализатор в зависимости от действия"""
        if self.action == 'create':
            return BranchCreateSerializer
        elif self.action == 'list':
            return BranchListSerializer
        return BranchSerializer

    def get_queryset(self):
        """Фильтрация веток по доступным репозиториям"""
        queryset = super().get_queryset()
        user_id = self.request.user.id
        
        # Фильтруем только ветки из репозиториев, доступных пользователю
        accessible_repos = []
        for repo in Repository.objects.all():
            if repo.can_user_view(user_id):
                accessible_repos.append(repo.id)
        
        return queryset.filter(repository_id__in=accessible_repos)

    def create(self, request, *args, **kwargs):
        """
        Создать ветку и соответствующую папку в файловой системе
        """
        serializer = self.get_serializer(data=request.data, context={'request': request})
        
        if serializer.is_valid():
            branch = serializer.save()
            
            # Добавляем информацию о физическом пути
            try:
                repository = branch.repository
                repo_uuid = str(repository.public_id)
                base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
                
                if os.path.exists(base_path):
                    # Создаем папку для ветки
                    branches_path = os.path.join(base_path, 'branches')
                    branch_path = os.path.join(branches_path, branch.name)
                    os.makedirs(branch_path, exist_ok=True)
                    
                    # Создаем подпапку для коммитов
                    commits_path = os.path.join(branch_path, 'commits')
                    os.makedirs(commits_path, exist_ok=True)

                    # Создаем начальный коммит (опционально)
                    commit_dir = os.path.join(commits_path, 'initial')
                    os.makedirs(commit_dir, exist_ok=True)


                    # Создаем файл README.md ветке
                    readme_path = os.path.join(branch_path, 'README.md')
                    if not os.path.exists(readme_path):
                        with open(readme_path, 'w', encoding='utf-8') as f:
                            f.write(f"# {branch.name}\n\n")
                            f.write(f"{repository.description or 'No description provided.'}\n\n")
                            f.write(f"Создана: {branch.created_at}\n")
                        print(f"DEBUG: README.md создан")
                    else:
                        print(f"DEBUG: README.md уже существует, пропускаем создание")

                    # Создаем файл с информацией о начальном коммите
                    initial_commit_info = {
                        'hash': 'initial',
                        'parents': [],
                        'message': 'Initial commit',
                        'branch': branch.name,
                        'created_at': repository.created_at.isoformat(),
                        'author': 'System',
                        'files': []
                    }
                        
                    initial_commit_path = os.path.join(branch_path, 'commit.json')
                    
                    if not os.path.exists(initial_commit_path):
                        with open(initial_commit_path, 'w', encoding='utf-8') as f:
                            json.dump(initial_commit_info, f, indent=2, ensure_ascii=False)
                        
                        print(f"DEBUG: commit.json создан")
                    else:
                        # Можно обновить существующий файл (опционально)
                        with open(initial_commit_path, 'r+', encoding='utf-8') as f:
                            existing_data = json.load(f)
                            # Обновляем нужные поля
                            existing_data.update({
                                'branch': branch.name,
                                'updated_at': branch.created_at.isoformat()
                            })
                            f.seek(0)
                            json.dump(existing_data, f, indent=2, ensure_ascii=False)
                            f.truncate()
                        print(f"DEBUG: commit.json обновлен")

                    response_data = BranchSerializer(branch, context={'request': request}).data
                    response_data['physical_path'] = branch_path
                    response_data['physical_created'] = True
                else:
                    response_data = BranchSerializer(branch, context={'request': request}).data
                    response_data['physical_created'] = False
                    response_data['message'] = 'Физический репозиторий не существует, папка ветки не создана'
            
            except Exception as e:
                print(f"Warning: Could not create physical folder for branch: {e}")
                response_data = BranchSerializer(branch, context={'request': request}).data
                response_data['physical_created'] = False
                response_data['warning'] = str(e)
            
            return Response(response_data, status=status.HTTP_201_CREATED)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    def update(self, request, *args, **kwargs):
        """Обновление ветки с проверкой прав"""
        branch = self.get_object()
        
        # Проверяем права на изменение репозитория
        #if not branch.repository.can_user_modify(request.user.id):
        #    raise PermissionDenied("У вас недостаточно прав для изменения этой ветки")
        
        return super().update(request, *args, **kwargs)
    
    def destroy(self, request, *args, **kwargs):
        """Удаление ветки с проверкой прав"""
        branch = self.get_object()
        
        # Проверяем права на изменение репозитория
        #if not branch.repository.can_user_modify(request.user.id):
        #    raise PermissionDenied("У вас недостаточно прав для удаления этой ветки")
        
        # Нельзя удалить ветку по умолчанию
        if branch.is_default:
            return Response({
                'error': 'Нельзя удалить ветку по умолчанию'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            # Удаляем физическую папку ветки
            repository = branch.repository
            repo_uuid = str(repository.public_id)
            base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
            branches_path = os.path.join(base_path, 'branches')
            branch_path = os.path.join(branches_path, branch.name)
        
            # Сохраняем данные для ответа
            branch_id = branch.id
            branch_name = branch.name

            # Удаляем физическую папку
            if os.path.exists(branch_path):
                shutil.rmtree(branch_path)
                print(f"--- [INFO] Физическая папка ветки удалена: {branch_path} ---")
        
            # Удаляем из базы данных
            branch.delete()

            return Response({
                'success': True,
                'message': f'Ветка "{branch_name}" успешно удалена',
                'branch_id': branch_id,
                'branch_name': branch_name
            }, status=status.HTTP_200_OK)

        except Exception as e:
            return Response({
                'success': False,
                'error': f'Ошибка при удалении ветки: {str(e)}'
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


    def get_queryset(self):
        """Фильтрация веток по репозиторию"""
        queryset = super().get_queryset()

        repository_public_id = self.request.query_params.get('repository_public_id')
        if repository_public_id:
            queryset = queryset.filter(repository__public_id=repository_public_id)

        repository_id = self.request.query_params.get('repository_id')
        if repository_id:
            queryset = queryset.filter(repository_id=repository_id)

        repository_name = self.request.query_params.get('repository_name')
        if repository_name:
            queryset = queryset.filter(repository__name__icontains=repository_name)

        return queryset

    @action(detail=False, methods=['post'])
    def set_default(self, request):
        """
        Установить ветку по умолчанию.
        """
        serializer = SetDefaultBranchSerializer(data=request.data, context={'request': request})

        if serializer.is_valid():
            branch = serializer.validated_data['branch']
            Branch.set_default_branch(branch)

            return Response({
                'success': True,
                'message': f'Ветка "{branch.name}" установлена как ветка по умолчанию',
                'branch': {
                    'id': branch.id,
                    'name': branch.name,
                    'repository': {
                        'id': branch.repository.id,
                        'public_id': branch.repository.public_id,
                        'name': branch.repository.name
                    }
                }
            })

        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=True, methods=['post'])
    def make_default(self, request, pk=None):
        """
        Сделать текущую ветку веткой по умолчанию.
        """
        branch = self.get_object()
        
        # Проверяем права на изменение репозитория
        #if not branch.repository.can_user_modify(request.user.id):
        #    raise PermissionDenied("У вас недостаточно прав для изменения этой ветки")
        
        Branch.set_default_branch(branch)

        return Response({
            'success': True,
            'message': f'Ветка "{branch.name}" установлена как ветка по умолчанию',
            'branch': {
                'id': branch.id,
                'name': branch.name,
                'is_default': branch.is_default
            }
        })

    @action(detail=True, methods=['get'], url_path='files')
    def get_files(self, request, pk=None):

        branch = self.get_object()

        repo_uuid = str(branch.repository.public_id)

        # Путь: media/version_management/{repo_uuid}/{branch_name}/
        # Если у тебя файлы веток лежат в папках с названиями веток

        branch_path = os.path.join(settings.MEDIA_ROOT, 'version_management', repo_uuid, branch.name)
        
        if not os.path.exists(branch_path):

            # Если папки ветки нет, возможно файлы общие в корне репо? 

            # Тут подправь путь под свою реальную структуру папок

            return Response({"error": "Папка ветки не найдена"}, status=404)

        structure = get_directory_structure(branch_path)

        return Response({

            "repository": branch.repository.name,

            "branch": branch.name,

            "structure": structure

        })



def get_directory_structure(root_path):
    """
    Рекурсивно собирает дерево файлов и папок.
    """
    items = []

    try:

        for entry in os.scandir(root_path):

            item = {

                "name": entry.name,

                "is_directory": entry.is_dir(),

                "size": entry.stat().st_size if entry.is_file() else None,

                "items": get_directory_structure(entry.path) if entry.is_dir() else []

            }

            items.append(item)

    except FileNotFoundError:

        return []

    return items


class CollaboratorViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления коллабораторами репозиториев.
    """
    #permission_classes = [IsAuthenticated]
    permission_classes = []
    queryset = Collaborator.objects.all()
    serializer_class = CollaboratorSerializer
    
    def get_serializer_class(self):
        if self.action == 'create':
            return CollaboratorCreateSerializer
        return CollaboratorSerializer

    def get_queryset(self):
        """Фильтрация коллабораторов по доступным репозиториям"""
        queryset = super().get_queryset()
        user_id = self.request.user.id
        
        # Фильтруем только коллабораторов из репозиториев, где пользователь является владельцем или администратором
        accessible_collaborators = []
        
        for collaborator in queryset:
            repository = collaborator.repository
            
            # Проверяем, является ли текущий пользователь владельцем или администратором
            if user_id == repository.owner_id:
                accessible_collaborators.append(collaborator.id)
            else:
                admin_collaborator = repository.collaborators.filter(
                    user_id=user_id,
                    role='admin'
                ).first()
                if admin_collaborator:
                    accessible_collaborators.append(collaborator.id)
        
        return queryset.filter(id__in=accessible_collaborators)
    
    def create(self, request, *args, **kwargs):
        """
        Создание коллаборатора.
        Требуется указать repository_public_id в запросе.
        """
        repository_public_id = request.data.get('repository_public_id')
        
        if not repository_public_id:
            return Response({
                'error': 'Необходимо указать repository_public_id'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            repository = Repository.objects.get(public_id=repository_public_id)
        except Repository.DoesNotExist:
            return Response({
                'error': 'Репозиторий не найден'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Проверяем права на управление коллабораторами
        if request.user.id != repository.owner_id:
            # Проверяем, является ли пользователь администратором
            admin_collaborator = repository.collaborators.filter(
                user_id=request.user.id,
                role='admin'
            ).first()
            if not admin_collaborator:
                raise PermissionDenied("Только владелец или администратор может добавлять коллабораторов")
        
        # Используем сериализатор для создания коллаборатора
        serializer = CollaboratorCreateSerializer(
            data=request.data,
            context={'request': request, 'repository': repository}
        )
        
        if serializer.is_valid():
            # Создаем коллаборатора
            collaborator = Collaborator.objects.create(
                repository=repository,
                user_id=serializer.validated_data['user_id'],
                role=serializer.validated_data['role']
            )
            
            # Сериализуем ответ
            response_serializer = CollaboratorSerializer(collaborator)
            
            return Response({
                'success': True,
                'message': 'Коллаборатор успешно добавлен',
                'collaborator': response_serializer.data
            }, status=status.HTTP_201_CREATED)
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)
    
    def update(self, request, *args, **kwargs):
        """Обновление роли коллаборатора"""
        collaborator = self.get_object()
        repository = collaborator.repository
        
        # Проверяем права на управление коллабораторами
        if request.user.id != repository.owner_id:
            # Проверяем, является ли пользователь администратором
            admin_collaborator = repository.collaborators.filter(
                user_id=request.user.id,
                role='admin'
            ).first()
            if not admin_collaborator:
                raise PermissionDenied("Только владелец или администратор может обновлять коллабораторов")
        
        # Обновляем только роль
        new_role = request.data.get('role')
        
        if not new_role:
            return Response({
                'error': 'Необходимо указать новую роль'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        if new_role not in ['read', 'write', 'admin']:
            return Response({
                'error': 'Некорректная роль. Допустимые значения: read, write, admin'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        collaborator.role = new_role
        collaborator.save()
        
        serializer = CollaboratorSerializer(collaborator)
        
        return Response({
            'success': True,
            'message': 'Роль коллаборатора обновлена',
            'collaborator': serializer.data
        })
    
    def destroy(self, request, *args, **kwargs):
        """Удаление коллаборатора"""
        collaborator = self.get_object()
        repository = collaborator.repository
        
        # Проверяем права на управление коллабораторами
        # if request.user.id != repository.owner_id:
        #     # Проверяем, является ли пользователь администратором
        #     admin_collaborator = repository.collaborators.filter(
        #         user_id=request.user.id,
        #         role='admin'
        #     ).first()
        #     if not admin_collaborator:
        #         raise PermissionDenied("Только владелец или администратор может удалять коллабораторов")
        
        # Нельзя удалить владельца
        if collaborator.user_id == repository.owner_id:
            return Response({
                'error': 'Нельзя удалить владельца репозитория'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        collaborator.delete()
        
        return Response({
            'success': True,
            'message': 'Коллаборатор успешно удален'
        })
    
    @action(detail=False, methods=['get'])
    def by_repository(self, request):
        """Получить коллабораторов по репозиторию"""
        repository_public_id = request.query_params.get('repository_public_id')
        
        if not repository_public_id:
            return Response({
                'error': 'Необходимо указать repository_public_id'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            repository = Repository.objects.get(public_id=repository_public_id)
        except Repository.DoesNotExist:
            return Response({
                'error': 'Репозиторий не найден'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Проверяем права на просмотр коллабораторов
        user_id = request.user.id
        if not repository.can_user_view(user_id):
            raise PermissionDenied("У вас нет доступа к этому репозиторию")
        
        collaborators = repository.collaborators.all()
        serializer = CollaboratorSerializer(collaborators, many=True)
        
        return Response({
            'repository': {
                'id': repository.id,
                'public_id': repository.public_id,
                'name': repository.name
            },
            'collaborators': serializer.data,
            'count': collaborators.count()
        })