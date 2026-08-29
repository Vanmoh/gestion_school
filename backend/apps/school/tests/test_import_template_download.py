"""Les modeles d'import doivent se telecharger dans le format demande.

Trois routes servent ces modeles, et toutes lisent `?format`. DRF reservait ce
nom pour negocier le type de reponse: il cherchait un renderer nomme « csv »
ou « xlsx », n'en trouvait aucun, et repondait 404 avant d'entrer dans la vue.
Le client envoie toujours ce parametre -- le bouton « Télécharger le modèle »
ne pouvait donc jamais aboutir, sur aucune des trois routes.

Aucune n'avait de test: la panne etait invisible tant qu'on ne cliquait pas.
"""

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import Etablissement

# Les trois portes d'entree vers le meme constructeur de modele.
ROUTES = {
    "autonome": "/api/import-templates/download/",
    "classes": "/api/classrooms/import-template/",
    "eleves": "/api/students/import-templates/download/",
}

EN_TETE_ZIP = b"PK"  # un .xlsx est un ZIP


class ImportTemplateDownloadTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.admin = User.objects.create_user(
            username="admin_modeles",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=cls.etablissement,
            is_staff=True,
            is_superuser=True,
        )

    def _get(self, route, **params):
        self.client.force_authenticate(self.admin)
        return self.client.get(
            ROUTES[route],
            params,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    # --- Les trois routes, les deux formats -----------------------------

    def test_every_route_serves_the_xlsx_template(self):
        for nom in ROUTES:
            with self.subTest(route=nom):
                response = self._get(nom, type="students", format="xlsx")

                self.assertEqual(response.status_code, status.HTTP_200_OK)
                self.assertIn("spreadsheetml", response["Content-Type"])
                self.assertTrue(response.content.startswith(EN_TETE_ZIP))

    def test_every_route_serves_the_csv_template(self):
        for nom in ROUTES:
            with self.subTest(route=nom):
                response = self._get(nom, type="students", format="csv")

                self.assertEqual(response.status_code, status.HTTP_200_OK)
                self.assertIn("text/csv", response["Content-Type"])
                self.assertIn(b"matricule", response.content)

    def test_the_file_name_carries_the_requested_extension(self):
        """Un .xlsx nomme .csv se refuse a ouvrir: l'extension doit suivre."""
        for nom in ROUTES:
            for extension in ("csv", "xlsx"):
                with self.subTest(route=nom, format=extension):
                    response = self._get(nom, type="students", format=extension)

                    self.assertIn("attachment", response["Content-Disposition"])
                    self.assertIn(f".{extension}", response["Content-Disposition"])

    # --- Ce que la vue doit encore refuser -------------------------------

    def test_an_unknown_format_is_a_clear_refusal_not_a_404(self):
        """Le 400 dit quoi corriger; le 404 laissait croire a une route absente."""
        response = self._get("autonome", type="students", format="docx")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_unknown_type_is_refused(self):
        response = self._get("autonome", type="martiens", format="csv")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
