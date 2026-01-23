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
    
    def create(self, request, *args, **kwargs):
        """
        Создать репозиторий и автоматически создать физическую структуру
        """
        # 1. Создаем репозиторий в БД
        response = super().create(request, *args, **kwargs)
        
        # 2. Если успешно, создаем физическую структуру
        if response.status_code == status.HTTP_201_CREATED:
            # Получаем созданный репозиторий из ответа
            repo_public_id = response.data.get('public_id')
            try:
                repository = Repository.objects.get(public_id=repo_public_id)
                
                # Запускаем асинхронное создание физической структуры
                self._create_physical_repository_async(repository)
                
                # Добавляем информацию в ответ
                response.data['physical_structure'] = {
                    'status': 'scheduled',
                    'message': 'Физическая структура будет создана в фоновом режиме'
                }
                
            except Exception as e:
                print(f"Warning: Could not schedule physical repository creation: {e}")
        
        return response
    
    def _create_physical_repository_async(self, repository):
        """
        Асинхронное создание физического репозитория
        """
        def create_physical():
            try:
                repo_uuid = str(repository.public_id)
                base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
                
                if not os.path.exists(base_path):
                    os.makedirs(base_path, exist_ok=True)
                    
                    # Создаем подпапки
                    api_path = os.path.join(base_path, 'api')
                    client_path = os.path.join(base_path, 'client')
                    os.makedirs(api_path, exist_ok=True)
                    os.makedirs(client_path, exist_ok=True)
                    
                    # Создаем папки для существующих веток
                    branches = repository.branches.all()
                    for branch in branches:
                        branch_path = os.path.join(base_path, branch.name)
                        os.makedirs(branch_path, exist_ok=True)
                    
                    # Создаем файлы
                    self._create_repository_files(repository, base_path)
                    
                    print(f"✓ Физический репозиторий создан: {base_path}")
            except Exception as e:
                print(f"✗ Ошибка при создании физического репозитория: {e}")
        
        # Запускаем в отдельном потоке
        thread = threading.Thread(target=create_physical)
        thread.daemon = True
        thread.start()
    
    def _create_repository_files(self, repository, base_path):
        """Создание файлов репозитория"""
        # manifest.json
        manifest = {
            "id": str(repository.public_id),
            "name": repository.name,
            "description": repository.description,
            "created_at": repository.created_at.isoformat() if repository.created_at else datetime.now().isoformat(),
            "updated_at": repository.updated_at.isoformat() if repository.updated_at else datetime.now().isoformat(),
            "version": "1.0.0"
        }
        
        with open(os.path.join(base_path, 'manifest.json'), 'w', encoding='utf-8') as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
        
        # README.md
        readme_content = f"""# {repository.name}

{repository.description if repository.description else 'Репозиторий для управления версиями'}

## Основная информация
- **ID**: {repository.public_id}
- **Создан**: {repository.created_at.strftime('%Y-%m-%d %H:%M:%S') if repository.created_at else 'Неизвестно'}
- **Обновлен**: {repository.updated_at.strftime('%Y-%m-%d %H:%M:%S') if repository.updated_at else 'Неизвестно'}

## Структура
- `/api/` - серверная часть
- `/client/` - клиентская часть
- `/<branch_name>/` - рабочие директории веток
"""
        
        with open(os.path.join(base_path, 'README.md'), 'w', encoding='utf-8') as f:
            f.write(readme_content)
        
        # .gitignore
        gitignore_content = """# Python
__pycache__/
*.pyc
*.pyo
*.pyd

# Environments
.env
.venv
env/
venv/

# IDE
.vscode/
.idea/
*.swp
*.swo

# System
.DS_Store
Thumbs.db
"""
        
        with open(os.path.join(base_path, '.gitignore'), 'w', encoding='utf-8') as f:
            f.write(gitignore_content)
    
    def get_object(self):
        """
        Получить объект по public_id.
        Если не найден по public_id, пробуем по id для обратной совместимости.
        """
        queryset = self.filter_queryset(self.get_queryset())
        
        # Получаем значение из URL
        lookup_url_kwarg = self.lookup_url_kwarg or self.lookup_field
        lookup_value = self.kwargs.get(lookup_url_kwarg)
        
        if lookup_value:
            try:
                # Сначала ищем по public_id (UUID)
                obj = queryset.get(public_id=lookup_value)
                self.check_object_permissions(self.request, obj)
                return obj
            except (Repository.DoesNotExist, ValueError):
                # Если не UUID, может быть числовой id для обратной совместимости
                try:
                    obj = queryset.get(id=lookup_value)
                    self.check_object_permissions(self.request, obj)
                    return obj
                except Repository.DoesNotExist:
                    pass
        
        raise Http404('Репозиторий не найден')
    
    @action(detail=True, methods=['post'])
    def create_physical_repository(self, request, public_id=None):
        """
        Создать физический репозиторий в файловой системе.
        POST /repositories/{public_id}/create_physical_repository/
        """
        repository = self.get_object()
        
        # Проверяем, существует ли уже физический репозиторий
        repo_uuid = str(repository.public_id)
        base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
        
        if os.path.exists(base_path):
            return Response({
                "success": False,
                "message": "Физический репозиторий уже существует",
                "path": base_path
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            # Создаем структуру
            os.makedirs(base_path, exist_ok=True)
            api_path = os.path.join(base_path, 'api')
            client_path = os.path.join(base_path, 'client')
            os.makedirs(api_path, exist_ok=True)
            os.makedirs(client_path, exist_ok=True)
            
            # Создаем папки для веток
            branches = repository.branches.all()
            for branch in branches:
                branch_path = os.path.join(base_path, branch.name)
                os.makedirs(branch_path, exist_ok=True)
            
            # Создаем файлы
            self._create_repository_files(repository, base_path)
            
            return Response({
                "success": True,
                "message": "Физический репозиторий успешно создан",
                "repository": {
                    "id": repository.id,
                    "public_id": repository.public_id,
                    "name": repository.name
                },
                "physical_path": base_path,
                "structure": {
                    "root": base_path,
                    "api": api_path,
                    "client": client_path,
                    "manifest": os.path.join(base_path, 'manifest.json'),
                    "readme": os.path.join(base_path, 'README.md'),
                    "gitignore": os.path.join(base_path, '.gitignore'),
                    "branches": [{"name": b.name, "path": os.path.join(base_path, b.name)} for b in branches]
                }
            }, status=status.HTTP_201_CREATED)
            
        except Exception as e:
            # Если ошибка, удаляем созданные папки
            import shutil
            if os.path.exists(base_path):
                shutil.rmtree(base_path)
            
            return Response({
                "success": False,
                "message": f"Ошибка при создании физического репозитория: {str(e)}"
            }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    @action(detail=True, methods=['get'])
    def physical_structure(self, request, public_id=None):
        """
        Получить информацию о физической структуре репозитория.
        GET /repositories/{public_id}/physical_structure/
        """
        repository = self.get_object()
        repo_uuid = str(repository.public_id)
        base_path = os.path.join(MEDIA_ROOT, 'version_management', repo_uuid)
        
        exists = os.path.exists(base_path)
        
        data = {
            "repository": {
                "id": repository.id,
                "public_id": repository.public_id,
                "name": repository.name
            },
            "physical_repository": {
                "exists": exists,
                "path": base_path if exists else None
            }
        }
        
        if exists:
            # Собираем информацию о файлах и папках
            import glob
            data["physical_repository"]["structure"] = {
                "root": base_path,
                "directories": [d for d in os.listdir(base_path) if os.path.isdir(os.path.join(base_path, d))],
                "files": [f for f in os.listdir(base_path) if os.path.isfile(os.path.join(base_path, f))]
            }
        
        return Response(data)
    
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

    def list_repo():
        pass

    def retrieve():
        pass

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

        
        
        def commit_create():
            pass

        def commit_list():
            pass
        
        def commit_retrieve():
            pass
        
        def commit_dif():
            pass
        