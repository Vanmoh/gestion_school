"""La sonde doit dire la verite, y compris quand ca va mal.

Une sonde qui repond 200 quoi qu'il arrive est pire que pas de sonde: elle
maintient dans la rotation une instance incapable de servir, et personne n'est
alerte.
"""

from unittest.mock import patch

from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase


class HealthCheckTests(APITestCase):
    def test_the_probe_answers_without_any_credentials(self):
        """Le health check de l'hebergeur n'a pas de jeton a presenter."""
        response = self.client.get(reverse("healthz"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "ok")
        self.assertTrue(response.data["checks"]["database"]["ok"])
        self.assertTrue(response.data["checks"]["cache"]["ok"])

    def test_a_dead_database_produces_a_503(self):
        with patch(
            "apps.common.health._check_database",
            return_value=(False, "OperationalError"),
        ):
            response = self.client.get(reverse("healthz"))

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(response.data["status"], "degraded")
        self.assertFalse(response.data["checks"]["database"]["ok"])

    def test_a_dead_cache_produces_a_503(self):
        """Le cache porte les quotas: hors service, ils ne s'appliquent plus."""
        with patch(
            "apps.common.health._check_cache", return_value=(False, "ConnectionError")
        ):
            response = self.client.get(reverse("healthz"))

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertFalse(response.data["checks"]["cache"]["ok"])

    def test_the_probe_is_never_rate_limited(self):
        """Bridee par un quota, la sonde ferait conclure a une panne inexistante."""
        from apps.common.health import HealthCheckView

        self.assertEqual(HealthCheckView.throttle_classes, ())
