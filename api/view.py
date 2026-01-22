# view.py
from rest_framework import viewsets, status, mixins
from rest_framework.decorators import action
from rest_framework.response import Response
from django.shortcuts import get_object_or_404
from django.http import Http404

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


class RepositoryViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления репозиториями.
    Поддерживает поиск по public_id через lookup_field.
    """
    queryset = Repository.objects.all()
    lookup_field = 'public_id'  # Используем public_id вместо id для API
    lookup_url_kwarg = 'public_id'  # Параметр в URL

    # Косте нужно изменить так, чтобы репозиторий создавался в соответствии с моделями в models.py, имел uuid и ветки как в репозиторий в бд postgresql 
    # @action(detail=False, methods=['post'])
    # def create(self, request):
        """
        Создать новый репозиторий
        POST /api/repositories/create/
        
        В теле запроса можно передать:
        {
            "name": "Название репозитория"  # опционально
        }
        """
        
        # 1. Генерируем UUID для папки репозитория
        repo_uuid = str(uuid.uuid4())
        
        # 2. Создаем путь: media/version_management/<UUID>/
        # repo_path = os.path.join(settings.MEDIA_ROOT, 'version_management', repo_uuid) # путь ч/з МЕДИА_РУТ

        repo_path = os.path.join('media', 'version_management', repo_uuid) # явный путь

        try:
            # 3. Создаем основную папку репозитория
            os.makedirs(repo_path, exist_ok=False)
            
            # 4. Создаем подпапки api/ и client/
            os.makedirs(os.path.join(repo_path, 'api'))
            os.makedirs(os.path.join(repo_path, 'client'))
            
            # 5. Создаем стандартные файлы
            
            # manifest.json с метаданными
            manifest = {
                "id": repo_uuid,
                "name": request.data.get('name', f"Repository {repo_uuid[:8]}"),
                "created_at": datetime.now().isoformat(),
                "version": "1.0.0"
            }
            
            with open(os.path.join(repo_path, 'manifest.json'), 'w') as f:
                json.dump(manifest, f, indent=2)
            
            # README.md
            readme_content = f"""# {manifest['name']}
            
        Время создания: {manifest['created_at']}
        ID репозитория: {repo_uuid}

        ## Структура
        - `/api/` - серверная часть
        - `/client/` - клиентская часть
        """
            with open(os.path.join(repo_path, 'README.md'), 'w') as f:
                f.write(readme_content)
            
            # .gitignore (базовый)
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
        """
            with open(os.path.join(repo_path, '.gitignore'), 'w') as f:
                f.write(gitignore_content)
            
            # 6. Возвращаем ответ
            return Response({
                "id": repo_uuid,
                "name": manifest["name"],
                "path": repo_path,
                "created_at": manifest["created_at"],
                "message": "Репозиторий успешно создан"
            }, status=status.HTTP_201_CREATED)
            
        except FileExistsError:
            # Если папка уже существует (крайне маловероятно с UUID)
            return Response(
                {"detail": "Репозиторий с таким ID уже существует"},
                status=status.HTTP_400_BAD_REQUEST
            )
        except Exception as e:
            # Любая другая ошибка
            return Response(
                {"detail": f"Ошибка при создании репозитория: {str(e)}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

    def get_serializer_class(self):
        """Выбираем сериализатор в зависимости от действия"""
        if self.action == 'create':
            return RepositoryCreateSerializer
        elif self.action in ['update', 'partial_update']:
            return RepositoryUpdateSerializer
        return RepositorySerializer
    
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
    def set_default_branch(self, request, public_id=None):
        """
        Установить ветку по умолчанию для репозитория.
        Поддерживает два варианта:
        
        1. По branch_id:
        POST /repositories/{public_id}/set_default_branch/
        {
            "branch_id": 1
        }
        
        2. По имени ветки:
        POST /repositories/{public_id}/set_default_branch/
        {
            "branch_name": "develop"
        }
        """
        repository = self.get_object()
        
        # Проверяем оба варианта
        branch_id = request.data.get('branch_id')
        branch_name = request.data.get('branch_name')
        
        if branch_id:
            # Находим ветку по ID в этом репозитории
            branch = get_object_or_404(
                Branch, 
                id=branch_id, 
                repository=repository
            )
        elif branch_name:
            # Находим ветку по имени в этом репозитории
            branch = get_object_or_404(
                Branch,
                name=branch_name,
                repository=repository
            )
        else:
            return Response({
                'error': 'Необходимо указать branch_id или branch_name'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Устанавливаем как дефолтную
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
        
        # Можно использовать BranchListSerializer для упрощенного вывода
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
    
    def get_queryset(self):
        """Фильтрация веток по репозиторию"""
        queryset = super().get_queryset()
        
        # Фильтрация по public_id репозитория
        repository_public_id = self.request.query_params.get('repository_public_id')
        if repository_public_id:
            queryset = queryset.filter(repository__public_id=repository_public_id)
        
        # Фильтрация по id репозитория (для обратной совместимости)
        repository_id = self.request.query_params.get('repository_id')
        if repository_id:
            queryset = queryset.filter(repository_id=repository_id)
        
        # Фильтрация по имени репозитория
        repository_name = self.request.query_params.get('repository_name')
        if repository_name:
            queryset = queryset.filter(repository__name__icontains=repository_name)
        
        return queryset
    
    @action(detail=False, methods=['post'])
    def set_default(self, request):
        """
        Установить ветку по умолчанию.
        POST /branches/set_default/
        
        Вариант 1 (по ID ветки):
        {
            "branch_id": 1
        }
        
        Вариант 2 (по public_id репозитория и имени ветки):
        {
            "repository_public_id": "550e8400-e29b-41d4-a716-446655440000",
            "branch_name": "develop"
        }
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
        POST /branches/{id}/make_default/
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