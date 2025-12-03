"""
Тут будут все эндпоинты (методы для работы с репозиториями; все эндпоинты - в классе RepositoryViewSet!) 
-- Вок, принял [Мухачёв]
"""


# view.py
import os
import uuid
import json
from datetime import datetime
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.conf import settings

class RepositoryViewSet(viewsets.ViewSet):
    
    @action(detail=False, methods=['post'])
    def create(self, request):
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