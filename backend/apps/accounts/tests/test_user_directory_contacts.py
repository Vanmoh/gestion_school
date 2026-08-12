"""L'annuaire donne des coordonnees a qui gere le personnel, pas aux familles.

Il est servi a tout compte authentifie -- c'est voulu, sans quoi les ecrans
qui choisissent un destinataire se fermeraient a tous sauf a la direction. Y
verser en clair le telephone et la photo des enseignants les exposerait donc
aussi aux parents et aux eleves.
"""

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import Etablissement

CHAMPS_SENSIBLES = ("email", "phone", "profile_photo")


class UserDirectoryContactsTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.enseignant = User.objects.create_user(
            username="prof_maths",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
            email="prof.maths@ecole.test",
            phone="76112233",
            first_name="Amadou",
            last_name="Diallo",
        )

    def _make_user(self, username, role):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=role,
            etablissement=self.etablissement,
        )

    def _annuaire(self, user):
        self.client.force_authenticate(user)
        response = self.client.get(
            "/api/auth/users/directory/",
            {"role": "teacher"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data

    def test_the_staff_receives_the_contacts(self):
        # Le surveillant n'y figure pas: la matrice lui ferme le module
        # « teachers » (colonne SUR a "-"). C'est elle qui decide, pas cette
        # vue -- une liste de roles recopiee ici finirait par en diverger.
        for role in (
            UserRole.DIRECTOR,
            UserRole.CENSOR,
            UserRole.ACCOUNTANT,
        ):
            with self.subTest(role=role):
                lecteur = self._make_user(f"lecteur_{role}", role)
                lignes = self._annuaire(lecteur)

                self.assertTrue(lignes)
                ligne = lignes[0]
                for champ in CHAMPS_SENSIBLES:
                    self.assertIn(champ, ligne, champ)
                self.assertEqual(ligne["phone"], "76112233")
                self.assertEqual(ligne["email"], "prof.maths@ecole.test")

    def test_those_without_the_module_never_see_them(self):
        """Un parent choisit un destinataire; il n'a pas a obtenir son numero.

        Le surveillant et l'enseignant y figurent aussi: la matrice leur ferme
        « teachers », et l'annuaire suit cette decision sans la redupliquer.
        """
        for role in (
            UserRole.PARENT,
            UserRole.STUDENT,
            UserRole.SUPERVISOR,
            UserRole.TEACHER,
        ):
            with self.subTest(role=role):
                lecteur = self._make_user(f"sans_module_{role}", role)
                lignes = self._annuaire(lecteur)

                self.assertTrue(lignes)
                ligne = lignes[0]
                for champ in CHAMPS_SENSIBLES:
                    self.assertNotIn(champ, ligne, champ)

    def test_the_minimal_fields_stay_available_to_everyone(self):
        """Les ecrans qui choisissent un destinataire ne doivent pas casser."""
        parent = self._make_user("parent_annuaire", UserRole.PARENT)
        lignes = self._annuaire(parent)

        ligne = lignes[0]
        for champ in ("id", "username", "full_name", "role", "etablissement"):
            self.assertIn(champ, ligne, champ)
        self.assertEqual(ligne["full_name"], "Amadou Diallo")

    def test_a_teacher_without_photo_reports_none_not_a_broken_link(self):
        directeur = self._make_user("directeur_annuaire", UserRole.DIRECTOR)
        lignes = self._annuaire(directeur)

        self.assertIsNone(lignes[0]["profile_photo"])

    def test_it_requires_authentication(self):
        self.client.force_authenticate(None)
        response = self.client.get("/api/auth/users/directory/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
