from django.db import models
from django.conf import settings


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class ActivityLog(TimeStampedModel):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    etablissement = models.ForeignKey("school.Etablissement", on_delete=models.SET_NULL, null=True, blank=True)
    role = models.CharField(max_length=20, blank=True)
    action = models.CharField(max_length=120)
    method = models.CharField(max_length=10)
    path = models.CharField(max_length=255)
    module = models.CharField(max_length=80, blank=True)
    target = models.CharField(max_length=120, blank=True)
    status_code = models.PositiveIntegerField(default=0)
    success = models.BooleanField(default=True)
    ip_address = models.CharField(max_length=45, blank=True)
    user_agent = models.CharField(max_length=255, blank=True)
    details = models.TextField(blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [
            models.Index(fields=["-created_at"], name="actlog_created_desc_idx"),
            models.Index(fields=["user", "-created_at"], name="actlog_user_created_idx"),
            models.Index(fields=["etablissement", "-created_at"], name="actlog_etab_created_idx"),
            models.Index(fields=["module", "-created_at"], name="actlog_module_created_idx"),
            models.Index(fields=["success", "-created_at"], name="actlog_success_created_idx"),
        ]

    def __str__(self):
        return f"{self.created_at} | {self.action} | {self.path}"


class BackupArchive(TimeStampedModel):
    class Scope(models.TextChoices):
        GLOBAL = "global", "Globale plateforme"
        ETABLISSEMENT = "etablissement", "Etablissement"

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        RUNNING = "running", "En cours"
        COMPLETED = "completed", "Terminee"
        FAILED = "failed", "Echec"

    class Kind(models.TextChoices):
        PORTABLE = "portable", "Portable ZIP"

    scope = models.CharField(max_length=20, choices=Scope.choices, default=Scope.GLOBAL)
    kind = models.CharField(max_length=20, choices=Kind.choices, default=Kind.PORTABLE)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)

    etablissement = models.ForeignKey(
        "school.Etablissement",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="backups",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_backups",
    )
    restored_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="restored_backups",
    )

    filename = models.CharField(max_length=255, blank=True)
    file_path = models.CharField(max_length=500, blank=True)
    file_size_bytes = models.BigIntegerField(default=0)
    sha256 = models.CharField(max_length=64, blank=True)
    include_media = models.BooleanField(default=True)
    manifest = models.JSONField(default=dict, blank=True)
    notes = models.TextField(blank=True)
    restore_log = models.TextField(blank=True)
    restored_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [
            models.Index(fields=["scope", "-created_at"], name="backup_scope_created_idx"),
            models.Index(fields=["status", "-created_at"], name="backup_status_created_idx"),
            models.Index(fields=["etablissement", "-created_at"], name="backup_etab_created_idx"),
        ]

    def __str__(self):
        return f"{self.get_scope_display()} | {self.filename or '-'} | {self.status}"
