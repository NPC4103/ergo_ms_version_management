# view.py
from rest_framework import viewsets, status, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from django.shortcuts import get_object_or_404
from django.http import Http404
import os
import json
from datetime import datetime
from django.conf import settings
import threading
from pathlib import Path
import shutil
import hashlib
import uuid as uuid_lib

from .models import Repository, Branch
from .serializers import (
    RepositorySerializer,
    RepositoryCreateSerializer,
    RepositoryUpdateSerializer,
    BranchSerializer,
    BranchCreateSerializer,
    SetDefaultBranchSerializer,
    BranchListSerializer
)

BASE_DIR = Path(__file__).resolve().parent.parent.parent.parent
MEDIA_ROOT = BASE_DIR / 'media'

class RepositoryViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления репозиториями.
    Поддерживает поиск по public_id через lookup_field.
    """
    queryset = Repository.objects.all()
    lookup_field = 'public_id'  # Используем public_id вместо id для API
    lookup_url_kwarg = 'public_id'  # Параметр в URL

    def get_serializer_class(self):
        """Выбираем сериализатор в зависимости от действия"""
        if self.action == 'create':
            return RepositoryCreateSerializer
        elif self.action in ['update', 'partial_update']:
            return RepositoryUpdateSerializer
        return RepositorySerializer

    # Добавьте этот метод в класс RepositoryViewSet в view.py

    def create(self, request, *args, **kwargs):
        """
        Создание репозитория с физической папкой в файловой системе.
        POST /api/version_management/repositories/
        """
        serializer = RepositoryCreateSerializer(data=request.data)
        
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
                        
                        # Создаем начальный коммит (опционально)
                        initial_commit_dir = os.path.join(commits_path, 'initial')
                        os.makedirs(initial_commit_dir, exist_ok=True)
                        
                        # Создаем файл с информацией о начальном коммите
                        initial_commit_info = {
                            'hash': 'initial',
                            'message': 'Initial commit',
                            'branch': default_branch.name,
                            'created_at': repository.created_at.isoformat(),
                            'author': 'System',
                            'files': []
                        }
                        
                        initial_commit_path = os.path.join(initial_commit_dir, 'commit.json')
                        with open(initial_commit_path, 'w', encoding='utf-8') as f:
                            json.dump(initial_commit_info, f, indent=2, ensure_ascii=False)
                    
                    # Создаем файл README.md в корне репозитория
                    readme_path = os.path.join(repo_path, 'README.md')
                    with open(readme_path, 'w', encoding='utf-8') as f:
                        f.write(f"# {repository.name}\n\n")
                        f.write(f"{repository.description or 'No description provided.'}\n\n")
                        f.write(f"Created: {repository.created_at}\n")
                        f.write(f"UUID: {repo_uuid}\n")
                    
                    # Создаем файл с метаинформацией о репозитории
                    repo_info_path = os.path.join(repo_path, '.repo_info.json')
                    repo_info = {
                        'uuid': repo_uuid,
                        'name': repository.name,
                        'description': repository.description,
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
                    response_data = RepositorySerializer(repository).data
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
            'repository': self.get_serializer(repository).data,
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
        branches = repository.branches.all()

        serializer = BranchListSerializer(branches, many=True)

        return Response({
            'repository': {
                'id': repository.id,
                'public_id': repository.public_id,
                'name': repository.name
            },
            'branches': serializer.data,
            'count': branches.count()
        })

    @action(detail=True, methods=['get', 'post', 'delete'], url_path='delete')
    def delete(self, request, public_id=None):
        """
        Удаляет репозиторий из БД и стирает файлы из media/version_management/
        """
        print(f"--- [INFO] Попытка удаления репозитория с UUID: {public_id} ---")

        # 1. Пытаемся найти объект
        # Так как lookup_field = 'public_id', get_object() сам использует этот UUID
        instance = self.get_object()

        repo_name = instance.name
        repo_uuid = str(instance.public_id)

        # 2. Формируем путь к папке (media/version_management/UUID)
        # В твоем файле MEDIA_ROOT уже определен через Path
        repo_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)

        print(f"--- [INFO] Путь к файлам: {repo_path} ---")

        try:
            # 3. Удаляем из базы данных
            # Ветки (Branch) удалятся каскадом сами
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
            # Коммиты хранятся в media/version_management/{uuid}/branches/{branch_name}/
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
                    'pushed': False
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
                                'author': pending_commit.get('author', 'Unknown')
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
        return hash_obj.hexdigest()[:16]  # Первые 16 символов хеша

class BranchViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления ветками.
    """
    queryset = Branch.objects.all()

    def get_serializer_class(self):
        """Выбираем сериализатор в зависимости от действия"""
        if self.action == 'create':
            return BranchCreateSerializer
        elif self.action == 'list':
            return BranchListSerializer
        return BranchSerializer

    def create(self, request, *args, **kwargs):
        """
        Создать ветку и соответствующую папку в файловой системе
        """
        response = super().create(request, *args, **kwargs)

        if response.status_code == status.HTTP_201_CREATED:
            try:
                # Получаем созданную ветку
                branch_id = response.data.get('id')
                branch = Branch.objects.get(id=branch_id)
                repository = branch.repository

                # Проверяем, существует ли физический репозиторий
                repo_uuid = str(repository.public_id)
                base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)

                if os.path.exists(base_path):
                    # Создаем папку для ветки
                    branch_path = os.path.join(base_path, branch.name)
                    os.makedirs(branch_path, exist_ok=True)

                    # Добавляем информацию в ответ
                    response.data['physical_path'] = branch_path
                    response.data['physical_created'] = True
                else:
                    response.data['physical_created'] = False
                    response.data['message'] = 'Физический репозиторий не существует, папка ветки не создана'

            except Exception as e:
                print(f"Warning: Could not create physical folder for branch: {e}")

        return response

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
        serializer = SetDefaultBranchSerializer(data=request.data)

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
        