from django.apps import AppConfig


class SchoolConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.school"

    def ready(self):
        from . import signals  # noqa: F401  (l'import enregistre les recepteurs)
