"""Ce qui ferme reellement une session, et ce qui protege la porte d'entree.

Deux regressions sont visees ici:
  1. la revocation silencieusement inactive (BLACKLIST_AFTER_ROTATION declare
     sans l'app token_blacklist: SimpleJWT avale l'erreur et le token reste
     valide jusqu'a son expiration naturelle);
  2. l'absence de quota sur le login, qui laisse deviner un mot de passe.
"""

from unittest.mock import patch

from django.core.cache import cache
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework.throttling import ScopedRateThrottle

from apps.accounts.models import User, UserRole
from apps.accounts.views import CustomTokenObtainPairView


class LogoutRevocationTests(APITestCase):
    def setUp(self):
        self.password = "Pass1234!"
        self.user = User.objects.create_user(
            username="logout_user",
            password=self.password,
            role=UserRole.SUPERVISOR,
        )

    def _login(self):
        response = self.client.post(
            "/api/auth/login/",
            {"username": self.user.username, "password": self.password},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data["access"], response.data["refresh"]

    def test_refresh_token_is_unusable_after_logout(self):
        access, refresh = self._login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

        logout = self.client.post(
            "/api/auth/logout/", {"refresh": refresh}, format="json"
        )
        self.assertEqual(logout.status_code, status.HTTP_205_RESET_CONTENT)

        self.client.credentials()
        replay = self.client.post(
            "/api/auth/refresh/", {"refresh": refresh}, format="json"
        )
        self.assertEqual(replay.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_rotated_refresh_token_cannot_be_replayed(self):
        """La rotation doit revoquer l'ancien token, pas seulement en emettre un neuf."""
        _, refresh = self._login()

        rotated = self.client.post(
            "/api/auth/refresh/", {"refresh": refresh}, format="json"
        )
        self.assertEqual(rotated.status_code, status.HTTP_200_OK)
        self.assertNotEqual(rotated.data["refresh"], refresh)

        replay = self.client.post(
            "/api/auth/refresh/", {"refresh": refresh}, format="json"
        )
        self.assertEqual(replay.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_logout_requires_the_refresh_token(self):
        access, _ = self._login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")

        response = self.client.post("/api/auth/logout/", {}, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_logout_succeeds_on_an_already_dead_token(self):
        """Un echec ici laisserait le client croire qu'il est encore connecte."""
        access, refresh = self._login()
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        self.client.post("/api/auth/logout/", {"refresh": refresh}, format="json")

        again = self.client.post(
            "/api/auth/logout/", {"refresh": refresh}, format="json"
        )
        self.assertEqual(again.status_code, status.HTTP_205_RESET_CONTENT)

    def test_logout_requires_authentication(self):
        self.client.credentials()
        response = self.client.post(
            "/api/auth/logout/", {"refresh": "peu-importe"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class LoginThrottleTests(APITestCase):
    """Le quota est abaisse sur la classe de throttle, pas via les settings.

    Les vues DRF figent `throttle_classes` a l'import: un override_settings sur
    REST_FRAMEWORK n'atteindrait pas les vues deja chargees et le test
    passerait a cote de ce qu'il croit verifier.
    """

    RATES = {"login": "3/min"}

    def setUp(self):
        cache.clear()
        self.addCleanup(cache.clear)
        patcher = patch.object(ScopedRateThrottle, "THROTTLE_RATES", self.RATES)
        patcher.start()
        self.addCleanup(patcher.stop)
        User.objects.create_user(
            username="throttled_user",
            password="Pass1234!",
            role=UserRole.SUPERVISOR,
        )

    def test_the_login_view_actually_carries_a_scoped_throttle(self):
        """Sans ce garde-fou, retirer le scope rendrait les tests suivants vides."""
        self.assertEqual(CustomTokenObtainPairView.throttle_scope, "login")
        self.assertIn(ScopedRateThrottle, CustomTokenObtainPairView.throttle_classes)

    def _attempt(self, password):
        return self.client.post(
            "/api/auth/login/",
            {"username": "throttled_user", "password": password},
            format="json",
        )

    def test_password_guessing_is_cut_off(self):
        for _ in range(3):
            self.assertEqual(
                self._attempt("mauvais").status_code, status.HTTP_401_UNAUTHORIZED
            )

        blocked = self._attempt("mauvais")
        self.assertEqual(blocked.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_quota_covers_the_valid_password_too(self):
        """Sinon le quota ne dit que 'ce mot de passe est faux' et n'arrete rien."""
        for _ in range(3):
            self._attempt("mauvais")

        blocked = self._attempt("Pass1234!")
        self.assertEqual(blocked.status_code, status.HTTP_429_TOO_MANY_REQUESTS)

    def test_refresh_endpoint_is_throttled_as_well(self):
        for _ in range(3):
            self.client.post(
                "/api/auth/refresh/", {"refresh": "invalide"}, format="json"
            )

        blocked = self.client.post(
            "/api/auth/refresh/", {"refresh": "invalide"}, format="json"
        )
        self.assertEqual(blocked.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
