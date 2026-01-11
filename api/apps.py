from django.apps import AppConfig
from src.config.settings import database


class VersionManagementConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'modules.version_management.api'
    label = 'version_management'

    def ready(self):
        """
        Регистрация database router для модуля version_management.
        Добавляет роутер в DATABASE_ROUTERS через механизм переопределения настроек Django.
        
        Используется механизм доступа к настройкам Django, позволяющий модулям
        динамически добавлять свои роутеры без изменения ядра системы.
        """
        router_path = "modules.version_management.api.routers.AppLabelRouter"
        
        # Получаем текущий список роутеров
        current_routers = getattr(database, 'DATABASE_ROUTERS', [])
        
        # Создаём новый список с добавленным роутером, если его ещё нет
        if router_path not in current_routers:
            new_routers = list(current_routers) if current_routers else []
            new_routers.append(router_path)
            # Устанавливаем обновлённый список роутеров
            setattr(database, 'DATABASE_ROUTERS', new_routers)