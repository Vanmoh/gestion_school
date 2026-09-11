from django.core.management.base import BaseCommand, CommandError
from django.db import close_old_connections

from apps.common.models import BackupArchive
from apps.common.views import BackupArchiveViewSet


class Command(BaseCommand):
    help = "Ecrit une archive de sauvegarde dans un processus detache."

    def add_arguments(self, parser):
        parser.add_argument("--backup-id", type=int, required=True)

    def handle(self, *args, **options):
        backup_id = int(options["backup_id"])

        close_old_connections()
        viewset = BackupArchiveViewSet()
        try:
            backup = BackupArchive.objects.filter(pk=backup_id).first()
            if backup is None:
                raise CommandError(f"Sauvegarde introuvable: {backup_id}")
            viewset._build_archive(backup)
        except Exception as exc:
            viewset._mark_build_failed(backup_id, exc)
            raise
        finally:
            close_old_connections()
