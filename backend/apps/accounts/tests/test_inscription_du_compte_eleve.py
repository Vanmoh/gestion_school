"""Inscrire un eleve, c'est d'abord lui creer un compte.

Le formulaire d'inscription cree le compte (POST /auth/users/) puis la fiche
eleve (POST /students/). Une garde posee pour empecher un changement de mot de
passe muet en modification ne distinguait pas creer de modifier: elle a ferme
la creation aussi, et plus personne ne pouvait inscrire.

Ces tests tiennent les deux bouts: la creation passe et donne un compte dont
le mot de passe fonctionne, la modification refuse toujours.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class InscriptionDuCompteEleveTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etab = Etablissement.objects.create(
            name="Complexe scolaire de l'inscription", code="CSIN"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 inscription",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="1ere Annee EM1", academic_year=cls.annee, etablissement=cls.etab
        )
        cls.directeur = User.objects.create_user(
            username="directeur_inscription",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etab,
        )

    def setUp(self):
        self.client.force_authenticate(self.directeur)
        self.entetes = {"HTTP_X_ETABLISSEMENT_ID": str(self.etab.id)}

    def _creer_le_compte(self, **remplacements):
        charge = {
            "username": "adiarra",
            "first_name": "Amadou",
            "last_name": "Diarra",
            "email": "",
            "password": "Eleve@12345",
            "role": "student",
            "phone": "",
        }
        charge.update(remplacements)
        return self.client.post(
            "/api/auth/users/", charge, format="json", **self.entetes
        )

    def test_le_formulaire_va_jusqu_au_bout(self):
        """Les deux appels que fait l'ecran, dans l'ordre."""
        compte = self._creer_le_compte()
        self.assertEqual(compte.status_code, status.HTTP_201_CREATED, compte.data)

        eleve = self.client.post(
            "/api/students/",
            {
                "user": compte.data["id"],
                "gender": "M",
                "classroom": self.classe.id,
                "birth_date": "2005-01-01",
            },
            format="json",
            **self.entetes,
        )

        self.assertEqual(eleve.status_code, status.HTTP_201_CREATED, eleve.data)
        self.assertTrue(Student.objects.filter(user_id=compte.data["id"]).exists())

    def test_l_eleve_peut_se_connecter_avec_le_mot_de_passe_donne(self):
        """Le vrai test de la correction.

        Accepter le champ ne suffit pas: sans `set_password`, le compte est
        cree et l'eleve ne peut jamais ouvrir sa session. Le defaut serait
        invisible jusqu'a sa premiere tentative de connexion.
        """
        self._creer_le_compte()
        self.client.force_authenticate(None)

        connexion = self.client.post(
            "/api/auth/login/",
            {"username": "adiarra", "password": "Eleve@12345"},
            format="json",
        )

        self.assertEqual(connexion.status_code, status.HTTP_200_OK)
        self.assertIn("access", connexion.data)

    def test_le_compte_est_rattache_a_l_etablissement(self):
        compte = self._creer_le_compte()

        cree = User.objects.get(pk=compte.data["id"])
        self.assertEqual(cree.etablissement_id, self.etab.id)

    def test_un_compte_cree_sans_mot_de_passe_ne_s_ouvre_pas(self):
        """Cette route sert aussi a creer du personnel sans mot de passe.

        C'est admis -- l'administration depanne ensuite par « Réinitialiser le
        mot de passe » -- mais le compte ne doit s'ouvrir avec rien: un
        hachage vide se laisserait forcer par une chaine vide.
        """
        reponse = self._creer_le_compte(password="")
        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)

        cree = User.objects.get(pk=reponse.data["id"])
        self.assertFalse(cree.has_usable_password())
        self.assertFalse(cree.check_password(""))

    def test_un_mot_de_passe_trop_court_est_refuse(self):
        reponse = self._creer_le_compte(password="1234")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", reponse.data)

    def test_la_modification_renvoie_toujours_vers_la_reinitialisation(self):
        """La garde d'origine tient: c'est elle qui a ferme l'acquiescement muet."""
        compte = self._creer_le_compte()

        reponse = self.client.patch(
            f"/api/auth/users/{compte.data['id']}/",
            {"password": "AutreMotDePasse1"},
            format="json",
            **self.entetes,
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Réinitialiser", str(reponse.data["password"]))

    def test_le_mot_de_passe_n_est_pas_ecrit_en_clair(self):
        compte = self._creer_le_compte()

        cree = User.objects.get(pk=compte.data["id"])
        self.assertNotEqual(cree.password, "Eleve@12345")
        self.assertTrue(cree.check_password("Eleve@12345"))
