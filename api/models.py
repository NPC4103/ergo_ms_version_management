# models.py
from django.db import models
from django.core.validators import MinLengthValidator
from django.core.exceptions import ValidationError


class Repository(models.Model):
    """
    Репозиторий - контейнер для веток.
    """
    name = models.CharField(
        max_length=100,
        validators=[MinLengthValidator(1)],
        help_text="Название репозитория",
        unique=True
    )
    description = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'repositories'
        verbose_name_plural = 'Repositories'
        app_label = 'version_management'  # Для AppLabelRouter
        ordering = ['name']
    
    def __str__(self):
        return str(self.name)
    
    def clean(self):
        """Базовая валидация названия репозитория"""
        name = str(self.name).strip()
        if not name:
            raise ValidationError({'name': 'Название не может быть пустым'})
        if name in ('.', '..'):
            raise ValidationError({'name': 'Некорректное название'})
    
    def save(self, *args, **kwargs):
        """Сохранение с валидацией"""
        self.clean()
        super().save(*args, **kwargs)


class Branch(models.Model):
    """
    Ветка репозитория.
    """
    repository = models.ForeignKey(
        Repository,
        on_delete = models.CASCADE,
        related_name ='branches'
    )
    name = models.CharField(
        max_length = 255,
        validators = [MinLengthValidator(1)],
        help_text = "Имя ветки (например: main, develop, feature/x)"
    )
    is_default = models.BooleanField(
        default = False,
        help_text = "Ветка по умолчанию для этого репозитория"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        db_table = 'branches'
        verbose_name_plural = 'Branches'
        app_label = 'version_management'  # Для AppLabelRouter
        ordering = ['repository', '-is_default', 'name']
        constraints = [
            models.UniqueConstraint(
                fields=['repository', 'name'],
                name='unique_branch_name_per_repository'
            ),
            models.UniqueConstraint(
                fields=['repository'],
                condition=models.Q(is_default=True),
                name='only_one_default_branch_per_repository'
            )
        ]
        indexes = [
            models.Index(fields=['repository', 'created_at']),
            models.Index(fields=['repository', 'is_default']),
        ]
    
    def __str__(self):
        """Безопасный вывод для отладки"""
        try:
            if self.repository_id:
                if hasattr(self.repository, 'name'):
                    return f"{self.repository.name}/{self.name}"
                return f"repo_{self.repository_id}/{self.name}"
        except:
            pass
        return f"branch_{self.id or 'new'}/{self.name}"
    
    def clean(self):
        """Базовая валидация имени ветки"""
        name = str(self.name).strip()
        if not name:
            raise ValidationError({'name': 'Имя ветки не может быть пустым'})
        
        # Только самые важные ограничения
        if name in ('HEAD', 'ORIG_HEAD'):
            raise ValidationError({'name': 'Зарезервированное системой имя'})
        
        if '..' in name:
            raise ValidationError({'name': 'Нельзя использовать .. в имени'})
    
    def save(self, *args, **kwargs):
        """Простой save для студенческого проекта"""
        # Если это новая ветка и первая в репозитории
        if self.pk is None:
            if not Branch.objects.filter(repository_id=self.repository_id).exists():
                self.is_default = True
        
        # Базовая валидация
        self.clean()
        super().save(*args, **kwargs)
    
    @classmethod
    def set_default_branch(cls, branch):
        """Простая установка ветки по умолчанию (для API)"""
        # Снимаем флаг у всех веток репозитория
        cls.objects.filter(
            repository_id=branch.repository_id,
            is_default=True
        ).update(is_default=False)
        
        # Устанавливаем флаг выбранной ветке
        branch.is_default = True
        branch.save(update_fields=['is_default'])