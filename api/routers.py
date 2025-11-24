from typing import Optional


class AppLabelRouter:
    """
    Роутер БД по app_label.

    Назначает приложениям отдельные подключения БД согласно aliases в settings.DATABASES.
    Для модуля version_management используется алиас БД 'version_management' из databases.yaml.
    """

    app_label_to_db = {
        'version_management': 'version_management',
    }

    def _get_db_for_app(self, app_label: str) -> Optional[str]:
        return self.app_label_to_db.get(app_label)

    def db_for_read(self, model, **hints):
        return self._get_db_for_app(model._meta.app_label)

    def db_for_write(self, model, **hints):
        return self._get_db_for_app(model._meta.app_label)

    def allow_relation(self, obj1, obj2, **hints):
        db1 = self._get_db_for_app(obj1._meta.app_label)
        db2 = self._get_db_for_app(obj2._meta.app_label)
        if db1 and db2:
            return db1 == db2
        return None

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        target_db = self._get_db_for_app(app_label)
        if target_db:
            return db == target_db
        return None