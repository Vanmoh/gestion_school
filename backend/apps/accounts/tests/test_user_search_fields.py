"""Chercher un compte par ce que l'ecran annonce chercher.

La grande barre du module « Gestion des utilisateurs » enumere ses criteres:
nom, identifiant, e-mail, telephone. Le champ `phone` existe sur le compte et
figure dans le serializer depuis l'origine, mais il ne faisait pas partie des
`search_fields`: taper un numero ne ramenait rien, alors que le meme geste
fonctionne dans le module eleve. Une barre qui annonce un critere doit le
servir.
"""

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import Etablissement

URL = "/api/auth/users/"


class UserSearchFieldsTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB Recherche", code="LTR")
        cls.cible = User.objects.create_user(
            username="a.keita",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
            first_name="Aminata",
            last_name="Keita",
            email="a.keita@ltob.ml",
            phone="78785913",
        )
        cls.autre = User.objects.create_user(
            username="m.diarra",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
            first_name="Mamadou",
            last_name="Diarra",
            email="m.diarra@ltob.ml",
            phone="66112233",
        )
        cls.direction = User.objects.create_user(
            username="dir_recherche",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def _chercher(self, terme):
        self.client.force_authenticate(self.direction)
        response = self.client.get(
            URL,
            {"search": terme},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        donnees = response.data
        lignes = donnees["results"] if isinstance(donnees, dict) else donnees
        return [ligne["username"] for ligne in lignes]

    def test_a_phone_number_finds_its_owner(self):
        self.assertIn("a.keita", self._chercher("78785913"))

    def test_a_phone_number_does_not_drag_the_others_along(self):
        """Un critere qui ramene tout le monde ne filtre rien."""
        trouves = self._chercher("78785913")

        self.assertNotIn("m.diarra", trouves)

    def test_a_partial_phone_number_is_enough(self):
        # On retient rarement le numero entier; les derniers chiffres, si.
        self.assertIn("a.keita", self._chercher("785913"))

    def test_the_other_criteria_still_answer(self):
        for terme, attendu in (
            ("Keita", "a.keita"),
            ("a.keita", "a.keita"),
            ("a.keita@ltob.ml", "a.keita"),
        ):
            with self.subTest(terme=terme):
                self.assertIn(attendu, self._chercher(terme))
