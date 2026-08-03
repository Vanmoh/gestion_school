"""Les controles de deploiement doivent parler quand la panne est possible.

Chacun de ces avertissements correspond a une panne qui a reellement eu lieu
en production sans qu'aucune erreur ne la signale au demarrage.
"""

from django.test import SimpleTestCase, override_settings

from apps.common import checks


class PersistentConnectionsCheckTests(SimpleTestCase):
    """Regression: CONN_MAX_AGE=600 en ASGI a sature le pooler a 15 connexions."""

    @override_settings(DATABASES={"default": {"CONN_MAX_AGE": 600}})
    def test_it_warns_on_persistent_connections(self):
        found = checks.persistent_connections_leak_under_asgi(None)

        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].id, checks.W002_CONN_MAX_AGE)
        self.assertIn("600", found[0].msg)

    @override_settings(DATABASES={"default": {"CONN_MAX_AGE": 0}})
    def test_it_stays_silent_when_connections_are_closed_per_request(self):
        self.assertEqual(checks.persistent_connections_leak_under_asgi(None), [])

    @override_settings(DATABASES={"default": {}})
    def test_an_absent_setting_is_not_a_warning(self):
        """CONN_MAX_AGE absent vaut 0 chez Django: rien a signaler."""
        self.assertEqual(checks.persistent_connections_leak_under_asgi(None), [])


class MediaStorageCheckTests(SimpleTestCase):
    @override_settings(DEBUG=False, USE_OBJECT_STORAGE=False)
    def test_it_warns_when_uploads_live_on_the_container_disk(self):
        found = checks.uploaded_files_survive_a_deployment(None)

        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].id, checks.W001_MEDIA_LOCAL)

    @override_settings(DEBUG=False, USE_OBJECT_STORAGE=True)
    def test_it_stays_silent_with_object_storage(self):
        self.assertEqual(checks.uploaded_files_survive_a_deployment(None), [])

    @override_settings(DEBUG=True, USE_OBJECT_STORAGE=False)
    def test_local_development_is_not_concerned(self):
        self.assertEqual(checks.uploaded_files_survive_a_deployment(None), [])


class SignedUrlRegionCheckTests(SimpleTestCase):
    """Regression: region vide -> signature v2 -> 403 sur toutes les photos."""

    @override_settings(USE_OBJECT_STORAGE=True, AWS_S3_REGION_NAME="")
    def test_it_warns_when_the_region_is_missing(self):
        found = checks.signed_media_urls_need_a_region(None)

        self.assertEqual(len(found), 1)
        self.assertEqual(found[0].id, checks.W003_S3_REGION)
        self.assertIn("AWS_S3_REGION_NAME", found[0].msg)

    @override_settings(USE_OBJECT_STORAGE=True, AWS_S3_REGION_NAME="eu-west-3")
    def test_it_stays_silent_once_the_region_is_set(self):
        self.assertEqual(checks.signed_media_urls_need_a_region(None), [])

    @override_settings(USE_OBJECT_STORAGE=False)
    def test_local_storage_needs_no_region(self):
        self.assertEqual(checks.signed_media_urls_need_a_region(None), [])
