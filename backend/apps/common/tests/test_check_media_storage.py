"""La commande de verification doit elle-meme etre fiable.

Un outil de diagnostic qui annonce "operationnel" sans avoir rien ecrit est
pire que pas d'outil: il transforme une panne en fausse assurance.
"""

import tempfile
from io import StringIO

from django.core.files.storage import FileSystemStorage, default_storage
from django.core.management import CommandError, call_command
from django.test import SimpleTestCase, override_settings
from unittest.mock import patch


class CheckMediaStorageTests(SimpleTestCase):
    def test_it_refuses_when_no_object_storage_is_configured(self):
        with override_settings(USE_OBJECT_STORAGE=False):
            with self.assertRaises(CommandError) as raised:
                call_command("check_media_storage")

        self.assertIn("Aucun stockage objet configure", str(raised.exception))

    @override_settings(
        USE_OBJECT_STORAGE=True,
        AWS_STORAGE_BUCKET_NAME="bucket-de-test",
        AWS_S3_ENDPOINT_URL="https://exemple.invalid/storage/v1/s3",
        AWS_QUERYSTRING_AUTH=True,
    )
    def test_the_round_trip_leaves_nothing_behind(self):
        with tempfile.TemporaryDirectory() as workdir:
            probe = FileSystemStorage(location=workdir, base_url="/media/")
            with patch.object(default_storage, "_wrapped", probe):
                out = StringIO()
                call_command("check_media_storage", stdout=out)

                from pathlib import Path

                leftovers = list(Path(workdir).rglob("*.txt"))

        rendered = out.getvalue()
        for step in ("ecriture", "relecture", "URL", "suppression"):
            self.assertIn(step, rendered)
        self.assertEqual(leftovers, [], "le fichier de sonde n'a pas ete supprime")

    @override_settings(
        USE_OBJECT_STORAGE=True,
        AWS_STORAGE_BUCKET_NAME="bucket-de-test",
        AWS_S3_ENDPOINT_URL="",
        AWS_QUERYSTRING_AUTH=False,
    )
    def test_a_public_bucket_is_called_out(self):
        with tempfile.TemporaryDirectory() as workdir:
            probe = FileSystemStorage(location=workdir, base_url="/media/")
            with patch.object(default_storage, "_wrapped", probe):
                out = StringIO()
                call_command("check_media_storage", stdout=out)

        rendered = out.getvalue()
        self.assertIn("PUBLIQUES", rendered)
        self.assertIn("Bucket public", rendered)
        self.assertNotIn("Stockage operationnel", rendered)
