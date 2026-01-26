from email.policy import default
from django.db import models
import uuid
from django.core.validators import MinLengthValidator
from django.core.exceptions import ValidationError
from django.db.models import indexes


class Repository(models.Model):
    """
    Репозиторий - контейнер для веток.
    """

    public_id = models.UUIDField(
        default=uuid.uuid4,
        editable=False,  # Важно: нельзя редактировать через админку
        unique=True,     # Должен быть уникальным
        db_index=True,   # Для быстрого поиска
        help_text="Публичный UUID для использования в API",
        null=True,       # Разрешить NULL для существующих записей
        blank=True       # Разрешить пустое значение в формах
    )

    name = models.CharField(
        max_length=100,
        validators=[MinLengthValidator(1)],
        help_text="Название репозитория",
        unique=True
    )
    description = models.TextField(blank=True)

    is_private = models.BooleanField(
        default=False,
        help_text="Приватный репозиторий (только для владельца и коллабораторов)"
    )
    is_read_only = models.BooleanField(
        default=False,
        help_text="Режим только для чтения (для всех пользователей)"
    )
    # Владелец репозитория
    owner_id = models.IntegerField(
        help_text="ID пользователя-владельца репозитория"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'repositories'
        verbose_name_plural = 'Repositories'
        app_label = 'version_management'
        ordering = ['name']
        indexes = [
            models.Index(fields=['public_id']),
            models.Index(fields=['created_at']),
            models.Index(fields=['owner_id']),
            models.Index(fields=['is_private']),
        ]
    
    def __str__(self):
        return str(self.name)
    
    def clean(self):
        """Базовая валидация названия репозитория"""
        name = str(self.name).strip()
        if not name:
            raise ValidationError({'name': 'Название не может быть пустым'})
        if name in ('.', '..', '/'):
            raise ValidationError({'name': 'Некорректное название'})
    
    def save(self, *args, **kwargs):
        """Сохранение с валидацией"""
        # Автоматически генерируем public_id если он не установлен
        if not self.public_id:
            self.public_id = uuid.uuid4()
        self.clean()
        super().save(*args, **kwargs)



    def can_user_modify(self, user_id):
        '''Проверяет, может ли пользователь изменять репозиторий'''
        if user_id == self.owner_id:
            return True # Владелец всегда может изменять

        if self.is_read_only:
            return False # Режим только для чтения

        # Проверяем, есть ли пользователь среди коллабораторов с правами на запись
        collaborator = self.collaborators.filter(user_id=user_id).first()
        if collaborator:
            return collaborator.role in ['write', 'admin']
        return False

    def can_user_view(self, user_id):
        '''Проверяет, может ли пользователь просматривать репозиторий'''
        if not self.is_private:
            return True # Публичный репозиторий виден всем

        if user_id == self.owner_id:
            return True  # Владелец всегда может просматривать

        # Проверяем, есть ли пользователь среди коллабораторов
        return self.collaborators.filter(user_id=user_id).exists()

    def get_user_role(self, user_id):
        """Возвращает роль пользователя в репозитории"""
        if user_id == self.owner_id:
            return 'owner'

        collaborator = self.collaborators.filter(user_id=user_id).first()
        if collaborator:
            return collaborator.role
        return None

class Collaborator(models.Model):
    """
    Коллаборатор репозитория - пользователь с определенными правами доступа.
    """
    ROLE_CHOICES = [
        ('read', 'Чтение'),
        ('write', 'Запись'),
        ('admin', 'Администратор'),
    ]

    repository = models.ForeignKey(
        Repository,
        on_delete=models.CASCADE,
        related_name='collaborators'
    )
    user_id = models.IntegerField(
        help_text="ID пользователя-коллаборатора"
    )
    username = models.CharField(  # ← НОВОЕ ПОЛЕ
        max_length=150,
        help_text="Имя пользователя (username) коллаборатора",
        blank=True,
        null=True
    )
    role = models.CharField(
        max_length=20,
        choices=ROLE_CHOICES,
        default='write',
        help_text="Роль коллаборатора в репозитории"
    )
    added_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'collaborators'
        verbose_name_plural = 'Collaborators'
        app_label = 'version_management'
        ordering = ['-added_at']
        constraints = [
            models.UniqueConstraint(
                fields=['repository', 'user_id'],
                name='unique_collaborator_per_repository'
            )
        ]
        indexes = [
            models.Index(fields=['repository', 'user_id']),
            models.Index(fields=['user_id']),
            models.Index(fields=['username']),
        ]
    def __str__(self):
        username = self.username or f"User#{self.user_id}"
        return f"Коллаборатор {username} в {self.repository.name}"

    def clean(self):
        """Валидация роли коллаборатора"""
        if self.role not in dict(self.ROLE_CHOICES):
            raise ValidationError({'role': 'Некорректная роль коллаборатора'})
    
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
        on_delete=models.CASCADE,
        related_name='branches'
    )
    name = models.CharField(
        max_length=255,
        validators=[MinLengthValidator(1)],
        help_text="Имя ветки (например: main, develop, feature/x)"
    )
    is_default = models.BooleanField(
        default=False,
        help_text="Ветка по умолчанию для этого репозитория"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        db_table = 'branches'
        verbose_name_plural = 'Branches'
        app_label = 'version_management'
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
        
        if name in ('HEAD', 'ORIG_HEAD'):
            raise ValidationError({'name': 'Зарезервированное системой имя'})
        
        if '..' in name:
            raise ValidationError({'name': 'Нельзя использовать .. в имени'})
    
    def save(self, *args, **kwargs):
        """Простой save для ветки"""
        if self.pk is None:
            if not Branch.objects.filter(repository_id=self.repository_id).exists():
                self.is_default = True
        
        self.clean()
        super().save(*args, **kwargs)
    
    @classmethod
    def set_default_branch(cls, branch):
        """Простая установка ветки по умолчанию (для API)"""
        cls.objects.filter(
            repository_id=branch.repository_id,
            is_default=True
        ).update(is_default=False)
        
        branch.is_default = True
        branch.save(update_fields=['is_default'])