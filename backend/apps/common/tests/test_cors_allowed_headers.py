"""La safelist CORS doit couvrir tous les en-tetes que l'application envoie.

Regression vecue: le client ajoutait `X-Academic-Year-Id` a chaque requete des
qu'une annee de travail etait choisie, mais l'en-tete ne figurait pas dans
`CORS_ALLOW_HEADERS`. Sur Android et sur le poste, rien ne bougeait -- le CORS
n'y existe pas. Sur le web, le navigateur refusait la reponse au preflight et
aucun appel n'aboutissait plus: tous les modules affichaient la meme erreur
reseau, y compris ceux qui n'ont rien a voir avec les annees scolaires.

Le premier test fixe le comportement observable (le preflight). Le second lit
le code du client et attrape l'en-tete suivant qu'on oubliera d'ajouter ici.
"""

import re
from pathlib import Path

from django.conf import settings
from django.test import Client, SimpleTestCase

REPO_ROOT = Path(settings.BASE_DIR).parent
CLIENT_SOURCE_DIR = REPO_ROOT / "frontend" / "gestion_school_app" / "lib"

# `options.headers['X-Etablissement-Id'] = ...` cote Dart.
CLIENT_HEADER_PATTERN = re.compile(r"""headers\[\s*['"](x-[\w-]+)['"]\s*\]""", re.IGNORECASE)


class PreflightAllowsClientHeadersTests(SimpleTestCase):
    def _allowed_headers(self, requested: str) -> set[str]:
        response = Client().options(
            "/api/school/students/",
            HTTP_ORIGIN="http://localhost:8080",
            HTTP_ACCESS_CONTROL_REQUEST_METHOD="GET",
            HTTP_ACCESS_CONTROL_REQUEST_HEADERS=requested,
        )
        allowed = response.headers.get("access-control-allow-headers", "")
        return {value.strip().lower() for value in allowed.split(",") if value.strip()}

    def test_the_preflight_answers_with_the_academic_year_header(self):
        allowed = self._allowed_headers("authorization,x-academic-year-id")

        self.assertIn("x-academic-year-id", allowed)

    def test_the_preflight_answers_with_the_establishment_headers(self):
        allowed = self._allowed_headers(
            "authorization,x-etablissement-id,x-etablissement-name"
        )

        self.assertIn("x-etablissement-id", allowed)
        self.assertIn("x-etablissement-name", allowed)


class ClientHeadersAreAllSafelistedTests(SimpleTestCase):
    """Le prochain en-tete ajoute au client sera signale ici, pas en production."""

    def test_every_custom_header_sent_by_the_client_is_allowed(self):
        if not CLIENT_SOURCE_DIR.is_dir():
            self.skipTest(
                f"Sources du client absentes ({CLIENT_SOURCE_DIR}): "
                "execution backend seul, rien a comparer."
            )

        sent = set()
        for source in CLIENT_SOURCE_DIR.rglob("*.dart"):
            sent.update(
                match.lower()
                for match in CLIENT_HEADER_PATTERN.findall(
                    source.read_text(encoding="utf-8", errors="ignore")
                )
            )

        self.assertTrue(sent, "Aucun en-tete personnalise trouve: le motif a du changer.")

        allowed = {header.lower() for header in settings.CORS_ALLOW_HEADERS}
        missing = sorted(sent - allowed)

        self.assertEqual(
            missing,
            [],
            "En-tetes envoyes par le client mais absents de CORS_ALLOW_HEADERS "
            f"(le web ne pourra plus rien charger): {missing}",
        )
