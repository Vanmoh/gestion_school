"""Une sauvegarde n'en est une que si elle survit au deploiement suivant.

Ecrite dans le conteneur, elle disparait sans que rien ne le signale: le
service beat annonce une tache reussie et il ne reste aucun fichier.
"""

import os
import tempfile
from pathlib import Path
from unittest.mock import patch

from django.core.files.storage import default_storage
from django.core.management import CommandError, call_command
from django.test import SimpleTestCase, override_settings


def _fake_dump(self, engine, database, destination: Path) -> None:
    """Remplace pg_dump/mysqldump, absents de l'environnement de test."""
    destination.write_text("-- dump factice\n", encoding="utf-8")


@patch(
    "apps.common.management.commands.backup_db.Command._dump",
    autospec=True,
    side_effect=_fake_dump,
)
class BackupDestinationTests(SimpleTestCase):
    @override_settings(USE_OBJECT_STORAGE=True, AWS_QUERYSTRING_AUTH=True)
    def test_the_dump_goes_to_object_storage_when_configured(self, _dump):
        saved = {}

        def capture(name, content):
            saved["name"] = name
            saved["body"] = content.read()
            return name

        with patch.object(default_storage, "save", side_effect=capture):
            call_command("backup_db")

        self.assertTrue(saved["name"].startswith("db-backups/backup_"))
        self.assertTrue(saved["name"].endswith(".sql"))
        self.assertEqual(saved["body"], b"-- dump factice\n")

    @override_settings(USE_OBJECT_STORAGE=True, AWS_QUERYSTRING_AUTH=False)
    def test_a_public_bucket_stops_the_backup(self, _dump):
        """Un dump de base dans un bucket public, c'est la base entiere en ligne."""
        with patch.object(default_storage, "save") as save:
            with self.assertRaises(CommandError) as raised:
                call_command("backup_db")

        self.assertIn("URL publiques", str(raised.exception))
        save.assert_not_called()

    @override_settings(USE_OBJECT_STORAGE=True, AWS_QUERYSTRING_AUTH=True)
    def test_local_only_bypasses_object_storage(self, _dump):
        # La commande ecrit dans ./backups: on deplace le repertoire courant
        # pour ne pas semer un dump dans l'arborescence du projet.
        with tempfile.TemporaryDirectory() as workdir:
            previous = os.getcwd()
            os.chdir(workdir)
            try:
                with patch.object(default_storage, "save") as save:
                    call_command("backup_db", "--local-only")
                written = list((Path(workdir) / "backups").glob("backup_*.sql"))
            finally:
                os.chdir(previous)

        save.assert_not_called()
        self.assertEqual(len(written), 1)
