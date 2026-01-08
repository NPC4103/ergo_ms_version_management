"""
Тут будут все эндпоинты (методы для работы с репозиториями; все эндпоинты - в классе RepositoryViewSet!)
"""

# view.py
import uuid
import json
from datetime import datetime
from pathlib import Path
from rest_framework import viewsets, status
from rest_framework.response import Response

# Локальный MEDIA_ROOT:
MODULE_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_MEDIA_ROOT = MODULE_ROOT.parent.parent / "media"
REPOSITORIES_ROOT = DEFAULT_MEDIA_ROOT / "version_management"


class RepositoryViewSet(viewsets.ViewSet):
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
        repo_path = REPOSITORIES_ROOT / repo_uuid

        try:
            # 3. Создаем основную папку репозитория
            repo_path.mkdir(parents=True, exist_ok=False)

            # 4. Создаем подпапки api/ и client/
            (repo_path / "api").mkdir()
            (repo_path / "client").mkdir()

            # 5. Создаем стандартные файлы

            # manifest.json с метаданными
            manifest = {
                "id": repo_uuid,
                "name": request.data.get("name", f"Repository {repo_uuid[:8]}"),
                "created_at": datetime.now().isoformat(),
                "version": "1.0.0",
            }

            with open(repo_path / "manifest.json", "w") as f:
                json.dump(manifest, f, indent=2)

            # README.md
            readme_content = f"""# {manifest['name']}

                Время создания: {manifest['created_at']}
                ID репозитория: {repo_uuid}

                ## Структура
                - `/api/` - серверная часть
                - `/client/` - клиентская часть
                """
            with open(repo_path / "README.md", "w") as f:
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
                .swo
                """
            with open(repo_path / ".gitignore", "w") as f:
                f.write(gitignore_content)

            # 6. Возвращаем ответ
            return Response(
                {
                    "id": repo_uuid,
                    "name": manifest["name"],
                    "path": str(repo_path),
                    "created_at": manifest["created_at"],
                    "message": "Репозиторий успешно создан",
                },
                status=status.HTTP_201_CREATED,
            )

        except FileExistsError:
            # Если папка уже существует (крайне маловероятно с UUID)
            return Response(
                {"detail": "Репозиторий с таким ID уже существует"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        except Exception as e:
            # Любая другая ошибка
            return Response(
                {"detail": f"Ошибка при создании репозитория: {str(e)}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
 
    def list(self, request):
        """
        Получить список всех репозиториев
        GET /api/repositories/list/
        """
        return Response(
            {"detail": "Список репозиториев"},
            status=status.HTTP_200_OK,
        )
    def retrieve(self, request, pk=None):
        """
        Получить информацию о конкретном репозитории
        GET /api/repositories/<id>/
        """
        return Response(
            {"detail": "Информация о репозитории"},
            status=status.HTTP_200_OK,
        )
    def update(self, request, pk=None):
        """
        Обновить информацию о конкретном репозитории
        PUT /api/repositories/<id>/
        """
        return Response(
            {"detail": "Информация о репозитории обновлена"},
            status=status.HTTP_200_OK,
        )
    def delete(self, request, pk=None):
        """
        Удалить конкретный репозиторий
        DELETE /api/repositories/<id>/
        """
        return Response(
            {"detail": "Репозиторий удален"},
            status=status.HTTP_200_OK,
        )
    def commit_create(self, request, pk=None):
        """
        Создать новый коммит
        POST /api/repositories/<id>/commit/create/
        """
        return Response(
            {"detail": "Коммит создан"},
            status=status.HTTP_200_OK,
        )
    def commit_list(self, request, pk=None):
        """
        Получить список всех коммитов
        GET /api/repositories/<id>/commit/list/
        """
        return Response(
            {"detail": "Список коммитов"},
            status=status.HTTP_200_OK,
        )
    def commit_retrieve(self, request, pk=None):
        """
        Получить информацию о конкретном коммите
        GET /api/repositories/<id>/commit/<commit_hash>/
        """
        return Response(
            {"detail": "Информация о коммите"},
            status=status.HTTP_200_OK,
        )
    def commit_update(self, request, pk=None):
        """
        Обновить информацию о конкретном коммите
        PUT /api/repositories/<id>/commit/<commit_hash>/
        """
        return Response(
            {"detail": "Информация о коммите обновлена"},
            status=status.HTTP_200_OK,
        )
    def commit_delete(self, request, pk=None):
        """
        Удалить конкретный коммит
        DELETE /api/repositories/<id>/commit/<commit_hash>/
        """
        return Response(
            {"detail": "Коммит удален"},
            status=status.HTTP_200_OK,
        )
    def commit_diff(self, request, pk=None):
        
        """
        Получить diff конкретного коммита
        GET /api/repositories/<id>/commit/<commit_hash>/diff/
        """
        return Response(
            {"detail": "Diff коммита"},
            status=status.HTTP_200_OK,
        )
    def clone(self, request, pk=None):
        """
        Клонировать конкретный репозиторий
        POST /api/repositories/<id>/clone/
        """
        return Response(
            {"detail": "Репозиторий клонирован"},
            status=status.HTTP_200_OK,
        )
    def push(self, request, pk=None):
        """
        Отправить изменения на сервер
        POST /api/repositories/<id>/push/
        """
        return Response(
            {"detail": "Изменения отправлены на сервер"},
            status=status.HTTP_200_OK,
        )

    def create_branch(self, request, pk=None):
        """
        Создать новую ветку
        POST /api/repositories/<id>/create-branch/
        """
        return Response(
            {"detail": "Ветка создана"},
            status=status.HTTP_200_OK,
        )
    def delete_branch(self, request, pk=None):
        """
        Удалить ветку
        POST /api/repositories/<id>/delete-branch/
        """
        return Response(
            {"detail": "Ветка удалена"},
            status=status.HTTP_200_OK,
        )
    def list_branches(self, request, pk=None):
        """
        Получить список всех веток
        GET /api/repositories/<id>/list-branches/
        """
        return Response(
            {"detail": "Список веток"},
            status=status.HTTP_200_OK,
        )
    def change_branch(self, request, pk=None):
        """
        Сменить ветку
        POST /api/repositories/<id>/change-branch/
        """
        return Response(
            {"detail": "Ветка сменена"},
            status=status.HTTP_200_OK,
        )
