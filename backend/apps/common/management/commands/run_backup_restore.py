from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import close_old_connections

from apps.accounts.models import User
from apps.common.models import BackupArchive
from apps.common.views import BackupArchiveViewSet


class Command(BaseCommand):
    help = "Run a backup restore job in a detached process."

    def add_arguments(self, parser):
        parser.add_argument("--backup-id", type=int, required=True)
        parser.add_argument("--archive-path", type=str, required=True)
        parser.add_argument("--actor-id", type=int, required=False)

    def handle(self, *args, **options):
        backup_id = int(options["backup_id"])
        archive_path = Path(str(options["archive_path"]).strip()).expanduser()
        actor_id = options.get("actor_id")

        if not archive_path.exists() or not archive_path.is_file():
            raise CommandError(f"Archive introuvable: {archive_path}")

        close_old_connections()
        viewset = BackupArchiveViewSet()
        try:
            backup = BackupArchive.objects.get(pk=backup_id)
            actor = User.objects.filter(pk=actor_id).first() if actor_id else None
            viewset._set_restore_progress(backup, progress=5, phase="Traitement demarre")
            viewset._restore_from_archive(backup, archive_path, actor=actor)
        except Exception as exc:
            viewset._mark_restore_failed(backup_id, exc)
            raise
        finally:
            close_old_connections()
