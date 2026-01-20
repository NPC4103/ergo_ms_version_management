from typing import Optional


class AppLabelRouter:
    """
    Роутер БД по app_label.

    Назначает приложениям отдельные подключения БД согласно aliases в settings.DATABASES.
    Для модуля version_management используется алиас БД 'version_management' из databases.yaml.
    """

    # app_label_to_db = {
    #     'version_management': 'version_management',
    # }

    route_app_labels = {'version_management'}
    
    def db_for_read(self, model, **hints):
        if model._meta.app_label in self.route_app_labels:
            return 'version_management'
        return None

    def db_for_write(self, model, **hints):
        if model._meta.app_label in self.route_app_labels:
            return 'version_management'
        return None

    def allow_relation(self, obj1, obj2, **hints):
        if (
            obj1._meta.app_label in self.route_app_labels or
            obj2._meta.app_label in self.route_app_labels
        ):
        if db1 and db2:
            return True
        return None

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        if app_label in self.route_app_labels:
            return db == target_db
        else:
            return db != target_db