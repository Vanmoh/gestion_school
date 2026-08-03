"""La commande de verification doit elle-meme etre fiable.

Un outil de diagnostic qui annonce "operationnel" sans avoir rien ecrit est
pire que pas d'outil: il transforme une panne en fausse assurance.
"""

import tempfile
import urllib.error
from io import BytesIO, StringIO

from django.core.files.storage import FileSystemStorage, default_storage
from django.core.management import CommandError, call_command
from django.test import SimpleTestCase, override_settings
from unittest.mock import patch


class _RemoteStorage(FileSystemStorage):
    """Stockage local qui expose des URL absolues, comme un bucket."""

    def url(self, name):
        return f"https://exemple.invalid/bucket/{name}?X-Amz-Signature=abc"


def _http_error(status, body):
    return urllib.error.HTTPError(
        url="https://exemple.invalid/bucket/probe",
        code=status,
        msg="Forbidden",
        hdrs=None,
        fp=BytesIO(body),
    )


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

    @override_settings(
        USE_OBJECT_STORAGE=True,
        AWS_STORAGE_BUCKET_NAME="bucket-de-test",
        AWS_S3_ENDPOINT_URL="https://exemple.invalid/storage/v1/s3",
        AWS_S3_REGION_NAME="",
        AWS_QUERYSTRING_AUTH=True,
    )
    def test_an_url_refused_by_the_provider_fails_the_command(self):
        """Regression: la commande annoncait "operationnel" sur une URL en 403.

        C'est la panne vue en production: signature v2 faute de region, donc
        "Missing signature" cote Supabase, alors que l'ecriture et la relecture
        passaient sans erreur.
        """
        refusal = (
            b'<?xml version="1.0" encoding="UTF-8"?><Error>'
            b"<Code>AccessDenied</Code><Message>Missing signature</Message></Error>"
        )
        with tempfile.TemporaryDirectory() as workdir:
            probe = _RemoteStorage(location=workdir, base_url="/media/")
            with patch.object(default_storage, "_wrapped", probe):
                with patch(
                    "urllib.request.urlopen", side_effect=_http_error(403, refusal)
                ):
                    out = StringIO()
                    with self.assertRaises(CommandError) as raised:
                        call_command("check_media_storage", stdout=out)

            leftovers = list(__import__("pathlib").Path(workdir).rglob("*.txt"))

        message = str(raised.exception)
        self.assertIn("HTTP 403", message)
        self.assertIn("AccessDenied", message)
        self.assertIn("AWS_S3_SIGNATURE_VERSION", message)
        self.assertNotIn("Stockage operationnel", out.getvalue())
        self.assertEqual(leftovers, [], "la sonde doit etre supprimee malgre l'echec")

    @override_settings(
        USE_OBJECT_STORAGE=True,
        AWS_STORAGE_BUCKET_NAME="bucket-de-test",
        AWS_S3_ENDPOINT_URL="https://exemple.invalid/storage/v1/s3",
        AWS_S3_REGION_NAME="us-east-1",
        AWS_QUERYSTRING_AUTH=True,
    )
    def test_a_region_mismatch_names_the_expected_region(self):
        refusal = (
            b"<Error><Code>AuthorizationHeaderMalformed</Code><Message>"
            b"the region 'us-east-1' is wrong; expecting 'eu-west-3'"
            b"</Message></Error>"
        )
        with tempfile.TemporaryDirectory() as workdir:
            probe = _RemoteStorage(location=workdir, base_url="/media/")
            with patch.object(default_storage, "_wrapped", probe):
                with patch(
                    "urllib.request.urlopen", side_effect=_http_error(400, refusal)
                ):
                    with self.assertRaises(CommandError) as raised:
                        call_command("check_media_storage", stdout=StringIO())

        message = str(raised.exception)
        self.assertIn("AWS_S3_REGION_NAME", message)
        self.assertIn("'eu-west-3' est attendu", message)

    @override_settings(
        USE_OBJECT_STORAGE=True,
        AWS_STORAGE_BUCKET_NAME="bucket-de-test",
        AWS_S3_ENDPOINT_URL="https://exemple.invalid/storage/v1/s3",
        AWS_S3_REGION_NAME="eu-west-3",
        AWS_QUERYSTRING_AUTH=True,
    )
    def test_a_reachable_url_completes_the_round_trip(self):
        from apps.common.management.commands.check_media_storage import PROBE_BODY

        class _Response:
            def read(self):
                return PROBE_BODY

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

        with tempfile.TemporaryDirectory() as workdir:
            probe = _RemoteStorage(location=workdir, base_url="/media/")
            with patch.object(default_storage, "_wrapped", probe):
                with patch("urllib.request.urlopen", return_value=_Response()):
                    out = StringIO()
                    call_command("check_media_storage", stdout=out)

        rendered = out.getvalue()
        self.assertIn("telechargement  OK", rendered)
        self.assertIn("Stockage operationnel", rendered)
