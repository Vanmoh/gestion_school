"""Sauvegarde de la base, deposee sur un stockage durable quand il existe.

Ecrite dans le conteneur, une sauvegarde disparait au deploiement suivant:
elle donne l'illusion d'exister sans rien proteger. Des qu'un stockage objet
est configure, le dump y est donc transfere et la copie locale supprimee.
"""

from datetime import datetime
import os
from pathlib import Path
import subprocess
import tempfile

from decouple import config
from django.conf import settings
from django.core.files.base import File
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand, CommandError

REMOTE_PREFIX = "db-backups"


class Command(BaseCommand):
    help = "Cree une sauvegarde de la base (MySQL ou PostgreSQL)"

    def add_arguments(self, parser):
        parser.add_argument(
            "--local-only",
            action="store_true",
            help="Force l'ecriture dans ./backups meme si un stockage objet existe.",
        )

    def handle(self, *args, **options):
        database = settings.DATABASES.get("default", {})
        engine = str(database.get("ENGINE", "")).lower()
        filename = f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"

        use_remote = (
            getattr(settings, "USE_OBJECT_STORAGE", False)
            and not options["local_only"]
        )
        if use_remote and not getattr(settings, "AWS_QUERYSTRING_AUTH", True):
            raise CommandError(
                "Le stockage objet sert des URL publiques "
                "(AWS_QUERYSTRING_AUTH=False): un dump de base y serait lisible "
                "par n'importe qui. Sauvegarde interrompue."
            )

        if use_remote:
            with tempfile.TemporaryDirectory() as workdir:
                local_path = Path(workdir) / filename
                self._dump(engine, database, local_path)
                with local_path.open("rb") as dump:
                    stored = default_storage.save(
                        f"{REMOTE_PREFIX}/{filename}", File(dump)
                    )
            self.stdout.write(
                self.style.SUCCESS(f"Sauvegarde transferee sur le stockage objet: {stored}")
            )
            return

        backup_dir = Path("backups")
        backup_dir.mkdir(parents=True, exist_ok=True)
        local_path = backup_dir / filename
        self._dump(engine, database, local_path)
        self.stdout.write(self.style.SUCCESS(f"Sauvegarde locale creee: {local_path}"))
        if not settings.DEBUG:
            self.stdout.write(
                self.style.WARNING(
                    "Aucun stockage objet configure: cette sauvegarde vit sur le "
                    "disque du conteneur et ne survivra pas au prochain deploiement."
                )
            )

    def _dump(self, engine: str, database: dict, destination: Path) -> None:
        if "postgresql" in engine:
            self._dump_postgresql(database, destination)
        else:
            self._dump_mysql(database, destination)

    def _dump_postgresql(self, database: dict, destination: Path) -> None:
        db_name = database.get("NAME") or config("DB_NAME", default="postgres")
        db_user = database.get("USER") or config("DB_USER", default="postgres")
        db_password = database.get("PASSWORD") or config("DB_PASSWORD", default="")
        db_host = database.get("HOST") or config("DB_HOST", default="localhost")
        db_port = str(database.get("PORT") or config("DB_PORT", default="5432"))

        env = os.environ.copy()
        env["PGPASSWORD"] = str(db_password)
        subprocess.run(
            [
                "pg_dump",
                "-h", str(db_host),
                "-p", db_port,
                "-U", str(db_user),
                "-d", str(db_name),
                "--no-owner",
                "--no-privileges",
                "-f", str(destination),
            ],
            env=env,
            check=True,
        )

    def _dump_mysql(self, database: dict, destination: Path) -> None:
        db_name = database.get("NAME") or config("DB_NAME", default="gestion_school")
        db_user = database.get("USER") or config("DB_USER", default="gestion_user")
        db_password = database.get("PASSWORD") or config(
            "DB_PASSWORD", default="gestion_password"
        )
        db_host = database.get("HOST") or config("DB_HOST", default="db")
        db_port = str(database.get("PORT") or config("DB_PORT", default="3306"))

        with destination.open("w", encoding="utf-8") as output_file:
            subprocess.run(
                [
                    "mysqldump",
                    f"-h{db_host}",
                    f"-P{db_port}",
                    f"-u{db_user}",
                    f"-p{db_password}",
                    str(db_name),
                ],
                stdout=output_file,
                check=True,
            )
