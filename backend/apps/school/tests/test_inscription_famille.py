"""Inscrire un eleve, c'est inscrire une famille.

Le formulaire creait un compte, puis une fiche, et rattrapait l'echec du
second appel en supprimant le premier. Le parent etait facultatif, et la
moitie des fiches n'en portaient pas: un dossier qu'on ne peut ni relancer ni
prevenir. Tout se fait desormais en une operation, parent compris.
"""

from datetime import date

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import UserRole
from apps.common.models import PersonnalisationPlateforme
from apps.school.models import AcademicYear, ClassRoom, Etablissement, ParentProfile, Student

User = get_user_model()


class InscriptionFamilleTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etab = Etablissement.objects.create(name="Ecole de la famille", code="EFAM")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 famille",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6eme A", academic_year=cls.annee, etablissement=cls.etab
        )
        cls.directeur = User.objects.create_user(
            username="dir_famille",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etab,
        )

    def setUp(self):
        self.client.force_authenticate(self.directeur)
        self.entetes = {"HTTP_X_ETABLISSEMENT_ID": str(self.etab.id)}

    def _charge(self, **remplacements):
        charge = {
            "first_name": "Amadou",
            "last_name": "Diarra",
            "gender": "M",
            "classroom": self.classe.id,
            "birth_date": "2012-03-14",
            "lien_parente": "pere",
            "parent_first_name": "Ouali",
            "parent_last_name": "Sissoko",
            "parent_phone": "76 12 34 56",
            "parent_whatsapp_phone": "76 12 34 56",
            "parent_whatsapp_consent": True,
        }
        charge.update(remplacements)
        return charge

    def _inscrire(self, **remplacements):
        return self.client.post(
            "/api/students/inscription/",
            self._charge(**remplacements),
            format="json",
            **self.entetes,
        )

    def test_l_eleve_et_sa_famille_naissent_ensemble(self):
        reponse = self._inscrire()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        eleve = Student.objects.get(id=reponse.data["eleve"]["id"])
        self.assertIsNotNone(eleve.parent)
        self.assertEqual(eleve.lien_parente, "pere")
        self.assertEqual(eleve.parent.user.last_name, "Sissoko")
        self.assertTrue(reponse.data["parent"]["cree"])

    def test_l_identifiant_de_l_eleve_est_son_matricule(self):
        reponse = self._inscrire()

        eleve = Student.objects.get(id=reponse.data["eleve"]["id"])
        self.assertEqual(eleve.user.username, eleve.matricule)
        self.assertEqual(
            reponse.data["identifiants_eleve"]["username"], eleve.matricule
        )

    def test_l_eleve_ouvre_sa_session_avec_ce_qu_on_lui_remet(self):
        """Le guichet lit ces deux lignes a la famille: elles doivent marcher."""
        reponse = self._inscrire()
        remis = reponse.data["identifiants_eleve"]
        self.client.force_authenticate(None)

        connexion = self.client.post(
            "/api/auth/login/",
            {"username": remis["username"], "password": remis["mot_de_passe"]},
            format="json",
        )

        self.assertEqual(connexion.status_code, status.HTTP_200_OK, connexion.data)

    def test_le_parent_ouvre_la_sienne(self):
        reponse = self._inscrire()
        remis = reponse.data["identifiants_parent"]
        self.client.force_authenticate(None)

        connexion = self.client.post(
            "/api/auth/login/",
            {"username": remis["username"], "password": remis["mot_de_passe"]},
            format="json",
        )

        self.assertEqual(connexion.status_code, status.HTTP_200_OK, connexion.data)

    def test_les_deux_comptes_devront_changer_de_mot_de_passe(self):
        """Le mot de passe est ecrit sur un papier et suit une regle connue."""
        reponse = self._inscrire()

        eleve = Student.objects.get(id=reponse.data["eleve"]["id"])
        self.assertTrue(eleve.user.doit_changer_mot_de_passe)
        self.assertTrue(eleve.parent.user.doit_changer_mot_de_passe)

    def test_le_numero_whatsapp_est_normalise(self):
        reponse = self._inscrire()

        eleve = Student.objects.get(id=reponse.data["eleve"]["id"])
        self.assertEqual(eleve.parent.whatsapp_phone, "+22376123456")
        self.assertTrue(eleve.parent.whatsapp_consent)

    def test_sans_parent_l_inscription_est_refusee(self):
        reponse = self.client.post(
            "/api/students/inscription/",
            {
                "first_name": "Sans",
                "last_name": "Famille",
                "gender": "F",
                "classroom": self.classe.id,
                "lien_parente": "mere",
            },
            format="json",
            **self.entetes,
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("parent", reponse.data)

    def test_le_second_enfant_rejoint_le_parent_existant(self):
        """Trois freres donnaient trois comptes parents, et trois mots de passe."""
        premier = self._inscrire()
        parent_id = premier.data["parent"]["id"]

        second = self._inscrire(
            first_name="Fatou",
            gender="F",
            parent_id=parent_id,
            lien_parente="pere",
        )

        self.assertEqual(second.status_code, status.HTTP_201_CREATED, second.data)
        self.assertFalse(second.data["parent"]["cree"])
        self.assertIsNone(second.data["identifiants_parent"])
        self.assertEqual(ParentProfile.objects.count(), 1)
        self.assertEqual(ParentProfile.objects.get(id=parent_id).children.count(), 2)

    def test_la_recherche_retrouve_le_parent_par_son_numero(self):
        self._inscrire()

        reponse = self.client.get(
            "/api/parents/recherche/",
            {"telephone": "+223 76 12 34 56"},
            **self.entetes,
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        resultats = reponse.data["resultats"]
        self.assertEqual(len(resultats), 1)
        self.assertEqual(resultats[0]["enfants"], 1)

    def test_rien_n_est_cree_quand_l_inscription_echoue(self):
        """Ou tout existe, ou rien: plus de compte orphelin a rattraper."""
        comptes = User.objects.count()

        reponse = self._inscrire(gender="X")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(User.objects.count(), comptes)
        self.assertEqual(ParentProfile.objects.count(), 0)

    def test_une_ecole_peut_avoir_son_propre_modele_de_mot_de_passe(self):
        PersonnalisationPlateforme.objects.update_or_create(
            pk=PersonnalisationPlateforme.SINGLETON_PK,
            defaults={"mot_de_passe_eleve_modele": "{matricule}"},
        )
        Etablissement.objects.filter(pk=self.etab.pk).update(
            mot_de_passe_eleve_modele="{sigle}{annee}"
        )

        reponse = self._inscrire()

        self.assertEqual(
            reponse.data["identifiants_eleve"]["mot_de_passe"], "EFAM2026"
        )

    def test_un_modele_trop_court_est_complete(self):
        """Huit caracteres au moins, sinon le guichet se ferme sans raison."""
        Etablissement.objects.filter(pk=self.etab.pk).update(
            mot_de_passe_eleve_modele="{sigle}"
        )

        reponse = self._inscrire()

        self.assertGreaterEqual(
            len(reponse.data["identifiants_eleve"]["mot_de_passe"]), 8
        )
