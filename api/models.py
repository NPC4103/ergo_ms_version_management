from django.db import models


class VersionedModule(models.Model):
    """
    Система управления версиями: описывает управляемый модуль/компонент системы.
    """

    slug = models.SlugField(max_length=80, unique=True, verbose_name="Идентификатор модуля")
    title = models.CharField(max_length=200, verbose_name="Название")
    description = models.TextField(blank=True, verbose_name="Описание")
    repository_url = models.URLField(blank=True, verbose_name="URL репозитория")
    is_active = models.BooleanField(default=True, verbose_name="Активен")

    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Создано")
    updated_at = models.DateTimeField(auto_now=True, verbose_name="Обновлено")

    class Meta:
        db_table = 'vm_versioned_module'
        verbose_name = "Модуль"
        verbose_name_plural = "Модули"
        ordering = ("slug",)

    def __str__(self) -> str:
        return f"{self.slug}"


class Release(models.Model):
    """
    Релиз модуля с семантической версией и сопутствующей информацией.
    """

    class ReleaseStatus(models.TextChoices):
        DRAFT = 'draft', 'Черновик'
        RELEASED = 'released', 'Выпущен'
        DEPRECATED = 'deprecated', 'Устарел'

    module = models.ForeignKey(
        VersionedModule,
        on_delete=models.CASCADE,
        related_name='releases',
        verbose_name="Модуль",
    )
    version = models.CharField(max_length=50, verbose_name="Версия (SemVer)")
    summary = models.CharField(max_length=255, blank=True, verbose_name="Краткое описание")
    changelog = models.TextField(blank=True, verbose_name="Изменения")
    commit_hash = models.CharField(max_length=64, blank=True, verbose_name="Commit hash")
    status = models.CharField(max_length=16, choices=ReleaseStatus.choices, default=ReleaseStatus.DRAFT, verbose_name="Статус")
    is_required = models.BooleanField(default=False, verbose_name="Обязательное обновление")

    created_at = models.DateTimeField(auto_now_add=True, verbose_name="Создано")
    released_at = models.DateTimeField(null=True, blank=True, verbose_name="Дата релиза")

    class Meta:
        db_table = 'vm_release'
        verbose_name = "Релиз"
        verbose_name_plural = "Релизы"
        constraints = [
            models.UniqueConstraint(fields=["module", "version"], name="uniq_module_version"),
        ]
        indexes = [
            models.Index(fields=["module", "status"], name="idx_release_module_status"),
        ]
        ordering = ("-created_at",)

    def __str__(self) -> str:
        return f"{self.module.slug}@{self.version}"
