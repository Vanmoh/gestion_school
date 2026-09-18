"""Le matricule d'un enseignant se genere, comme celui d'un eleve.

    RC15    ENS   25   0042
    ecole   type  an   sequence

Le champ existait -- unique a l'echelle de la plateforme -- mais rien ne le
produisait: il fallait l'inventer a la saisie, et deux ecoles pouvaient se
disputer le meme « P001 ».
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.matricule import FORMAT_MATRICULE_ENSEIGNANT
from apps.school.models import Etablissement, Teacher


class MatriculeEnseignantTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée Kalaban", code="LKB"
        )
        cls.voisine = Etablissement.objects.create(name="Lycée Ségou", code="LSG")

    def _enseignant(self, username, *, etablissement=None, embauche=date(2025, 9, 1), code=""):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=etablissement or self.etablissement,
        )
        return Teacher.objects.create(
            user=user,
            employee_code=code,
            hire_date=embauche,
            etablissement=etablissement or self.etablissement,
        )

    def test_un_code_absent_se_fabrique(self):
        enseignant = self._enseignant("ens_auto")

        self.assertTrue(enseignant.employee_code)
        self.assertTrue(
            FORMAT_MATRICULE_ENSEIGNANT.match(enseignant.employee_code),
            enseignant.employee_code,
        )

    def test_le_code_porte_l_ecole_et_l_annee_d_embauche(self):
        enseignant = self._enseignant("ens_format", embauche=date(2024, 10, 1))

        self.assertTrue(enseignant.employee_code.startswith("LKBENS24"))

    def test_l_annee_est_celle_de_l_embauche_pas_celle_du_jour(self):
        # Un enseignant traverse les annees: son code reste celui de son
        # entree dans l'ecole.
        ancien = self._enseignant("ens_ancien", embauche=date(2019, 9, 2))

        self.assertTrue(ancien.employee_code.startswith("LKBENS19"))

    def test_la_sequence_avance_sans_se_repeter(self):
        premier = self._enseignant("ens_un")
        second = self._enseignant("ens_deux")

        self.assertNotEqual(premier.employee_code, second.employee_code)
        self.assertEqual(premier.employee_code[:-4], second.employee_code[:-4])
        self.assertEqual(
            int(second.employee_code[-4:]), int(premier.employee_code[-4:]) + 1
        )

    def test_deux_ecoles_ne_se_disputent_pas_un_code(self):
        # C'est le defaut que le prefixe evite: le code est unique pour toute
        # la plateforme, et deux ecoles produisaient le meme « P001 ».
        ici = self._enseignant("ens_ici")
        ailleurs = self._enseignant("ens_ailleurs", etablissement=self.voisine)

        self.assertNotEqual(ici.employee_code, ailleurs.employee_code)
        self.assertTrue(ailleurs.employee_code.startswith("LSGENS"))

    def test_un_code_saisi_a_la_main_est_respecte(self):
        # Une reprise de donnees apporte les codes de l'ancien systeme: les
        # reecrire ferait perdre la correspondance avec les dossiers papier.
        enseignant = self._enseignant("ens_repris", code="ANCIEN-042")

        self.assertEqual(enseignant.employee_code, "ANCIEN-042")

    def test_l_api_cree_un_enseignant_sans_code(self):
        admin = User.objects.create_user(
            username="admin_matricule",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(admin)
        user = User.objects.create_user(
            username="ens_api",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )

        reponse = self.client.post(
            "/api/teachers/",
            {"user": user.id, "hire_date": "2025-09-01"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertTrue(reponse.data["employee_code"].startswith("LKBENS25"))
