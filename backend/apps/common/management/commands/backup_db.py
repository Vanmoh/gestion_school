from datetime import datetime
import os
from pathlib import Path
import subprocess
from decouple import config
from django.conf import settings
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Create a database backup (MySQL or PostgreSQL)"

    def handle(self, *args, **options):
        database = settings.DATABASES.get("default", {})
        engine = str(database.get("ENGINE", "")).lower()

        backup_dir = Path("backups")
        backup_dir.mkdir(parents=True, exist_ok=True)

        if "postgresql" in engine:
            db_name = database.get("NAME") or config("DB_NAME", default="postgres")
            db_user = database.get("USER") or config("DB_USER", default="postgres")
            db_password = database.get("PASSWORD") or config("DB_PASSWORD", default="")
            db_host = database.get("HOST") or config("DB_HOST", default="localhost")
            db_port = str(database.get("PORT") or config("DB_PORT", default="5432"))

            filename = backup_dir / f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"
            cmd = [
                "pg_dump",
                "-h",
                str(db_host),
                "-p",
                db_port,
                "-U",
                str(db_user),
                "-d",
                str(db_name),
                "--no-owner",
                "--no-privileges",
                "-f",
                str(filename),
            ]

            env = os.environ.copy()
            env["PGPASSWORD"] = str(db_password)
            subprocess.run(cmd, env=env, check=True)
            self.stdout.write(
                self.style.SUCCESS(f"PostgreSQL backup created: {filename}")
            )
            return

        db_name = database.get("NAME") or config("DB_NAME", default="gestion_school")
        db_user = database.get("USER") or config("DB_USER", default="gestion_user")
        db_password = database.get("PASSWORD") or config("DB_PASSWORD", default="gestion_password")
        db_host = database.get("HOST") or config("DB_HOST", default="db")
        db_port = str(database.get("PORT") or config("DB_PORT", default="3306"))

        filename = backup_dir / f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"
        cmd = [
            "mysqldump",
            f"-h{db_host}",
            f"-P{db_port}",
            f"-u{db_user}",
            f"-p{db_password}",
            str(db_name),
        ]

        with open(filename, "w", encoding="utf-8") as output_file:
            subprocess.run(cmd, stdout=output_file, check=True)

        self.stdout.write(self.style.SUCCESS(f"MySQL backup created: {filename}"))
