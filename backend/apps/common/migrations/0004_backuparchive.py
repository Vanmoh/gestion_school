from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0002_user_etablissement"),
        ("school", "0017_grade_homework_scores_and_examresult_constraint"),
        ("common", "0003_activitylog_etablissement"),
    ]

    operations = [
        migrations.CreateModel(
            name="BackupArchive",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "scope",
                    models.CharField(
                        choices=[("global", "Globale plateforme"), ("etablissement", "Etablissement")],
                        default="global",
                        max_length=20,
                    ),
                ),
                (
                    "kind",
                    models.CharField(
                        choices=[("portable", "Portable ZIP")],
                        default="portable",
                        max_length=20,
                    ),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("pending", "En attente"),
                            ("running", "En cours"),
                            ("completed", "Terminee"),
                            ("failed", "Echec"),
                        ],
                        default="pending",
                        max_length=20,
                    ),
                ),
                ("filename", models.CharField(blank=True, max_length=255)),
                ("file_path", models.CharField(blank=True, max_length=500)),
                ("file_size_bytes", models.BigIntegerField(default=0)),
                ("sha256", models.CharField(blank=True, max_length=64)),
                ("include_media", models.BooleanField(default=True)),
                ("manifest", models.JSONField(blank=True, default=dict)),
                ("notes", models.TextField(blank=True)),
                ("restore_log", models.TextField(blank=True)),
                ("restored_at", models.DateTimeField(blank=True, null=True)),
                (
                    "created_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="created_backups",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "etablissement",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="backups",
                        to="school.etablissement",
                    ),
                ),
                (
                    "restored_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="restored_backups",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at", "-id"],
                "indexes": [
                    models.Index(fields=["scope", "-created_at"], name="backup_scope_created_idx"),
                    models.Index(fields=["status", "-created_at"], name="backup_status_created_idx"),
                    models.Index(fields=["etablissement", "-created_at"], name="backup_etab_created_idx"),
                ],
            },
        ),
    ]
