"""Ce qu'une famille tape pour entrer, et ce qui lui ouvre.

L'ecole remet a l'eleve son matricule et au parent son numero. Les comptes
ouverts depuis le module d'admission les portent effectivement comme
identifiant; ceux d'avant portent un nom compose -- « ousmane.bagayoko ».
Ces familles-la tapaient ce qu'on leur avait remis et lisaient
« identifiants invalides ».
"""

from datetime import date
from unittest.mock import patch

from django.contrib.auth import authenticate
from django.core.cache import cache
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework.throttling import ScopedRateThrottle

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ParentProfile,
    Student,
)

MOT_DE_PASSE = "Pass1234!"


class ConnexionDeLaFamilleTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Connexion", code="EC")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 EC",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="1ère Année EM1",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )

        # Un compte d'avant l'admission: son identifiant vient du nom.
        cls.compte_parent = User.objects.create_user(
            username="bakary.sangare",
            password=MOT_DE_PASSE,
            role=UserRole.PARENT,
            first_name="Bakary",
            last_name="Sangare",
            phone="73 65 83 34",
            etablissement=cls.etablissement,
        )
        cls.parent = ParentProfile.objects.create(
            user=cls.compte_parent, etablissement=cls.etablissement
        )
        cls.compte_eleve = User.objects.create_user(
            username="ousmane.bagayoko",
            password=MOT_DE_PASSE,
            role=UserRole.STUDENT,
            first_name="Ousmane",
            last_name="Bagayoko",
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=cls.compte_eleve,
            matricule="IO1EM125E0028M",
            classroom=cls.classe,
            parent=cls.parent,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        # La route de connexion porte un quota etroit, et ces tests la
        # sollicitent plus qu'un humain ne le ferait. On le desarme ici: ce
        # qu'il protege est verifie par `test_session_security`.
        cache.clear()
        self.addCleanup(cache.clear)
        patcher = patch.object(
            ScopedRateThrottle, "THROTTLE_RATES", {"login": "1000/min"}
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def _connexion(self, identifiant, mot_de_passe=MOT_DE_PASSE):
        return self.client.post(
            "/api/auth/login/",
            {"username": identifiant, "password": mot_de_passe},
        )

    def test_l_identifiant_du_compte_ouvre_toujours(self):
        """La correction n'enleve rien a ceux qui se connectent deja."""
        self.assertEqual(
            self._connexion("ousmane.bagayoko").status_code, status.HTTP_200_OK
        )

    def test_le_matricule_ouvre_le_compte_de_l_eleve(self):
        reponse = self._connexion("IO1EM125E0028M")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertIn("access", reponse.data)

    def test_le_matricule_se_recopie_comme_il_se_lit(self):
        """Casse, espaces et tirets: une carte plastifiee se recopie a la main."""
        for ecriture in (
            "io1em125e0028m",
            "IO1-EM1-25E0028M",
            "  IO1 EM1 25E0028M  ",
        ):
            with self.subTest(ecriture=ecriture):
                self.assertEqual(
                    self._connexion(ecriture).status_code, status.HTTP_200_OK
                )

    def test_le_numero_ouvre_le_compte_du_parent(self):
        for ecriture in ("73658334", "73 65 83 34", "+223 73 65 83 34"):
            with self.subTest(ecriture=ecriture):
                self.assertEqual(
                    self._connexion(ecriture).status_code, status.HTTP_200_OK
                )

    def test_le_mot_de_passe_reste_le_seul_secret(self):
        """Le matricule ouvre la porte, il ne la deverrouille pas."""
        self.assertEqual(
            self._connexion("IO1EM125E0028M", "mauvais-mot-de-passe").status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    def test_un_matricule_inconnu_est_refuse(self):
        self.assertEqual(
            self._connexion("IO1DB125E0011M").status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    def test_un_compte_desactive_ne_rouvre_pas_par_son_matricule(self):
        self.compte_eleve.is_active = False
        self.compte_eleve.save(update_fields=["is_active"])
        self.addCleanup(
            lambda: User.objects.filter(pk=self.compte_eleve.pk).update(is_active=True)
        )

        self.assertEqual(
            self._connexion("IO1EM125E0028M").status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    def test_un_identifiant_ne_se_fait_pas_prendre_par_le_matricule_d_un_autre(self):
        """L'identifiant du compte passe avant tout le reste.

        Sans cet ordre, un compte dont l'identifiant vaut le matricule d'un
        autre eleve aurait ouvert le mauvais dossier -- avec un mot de passe
        juste, donc sans que rien ne le signale.
        """
        homonyme = User.objects.create_user(
            username="IO1EM125E0028M",
            password="AutrePass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )

        compte = authenticate(username="IO1EM125E0028M", password="AutrePass1234!")

        self.assertEqual(compte, homonyme)

    def test_le_numero_ouvre_meme_note_avec_des_espaces(self):
        """Le champ telephone est un champ de repertoire, rempli a la main.

        Un signal en recopie la forme normalisee sur la fiche du parent, et
        c'est elle qu'on interroge: sans quoi « 73 65 83 34 » n'aurait
        jamais repondu a « 73658334 ».
        """
        self.assertEqual(
            self.parent.whatsapp_phone,
            "+22373658334",
            "Le signal de propagation ne remplit plus le numero normalise: "
            "la connexion par numero ne tient plus qu'aux fiches saisies "
            "sans separateur.",
        )

    def test_un_numero_partage_par_deux_familles_n_ouvre_ni_l_une_ni_l_autre(self):
        """Deviner entre deux comptes ouvrirait celui qu'on n'a pas demande."""
        autre = User.objects.create_user(
            username="fatoumata.sangare",
            password=MOT_DE_PASSE,
            role=UserRole.PARENT,
            phone="73 65 83 34",
            etablissement=self.etablissement,
        )
        ParentProfile.objects.create(user=autre, etablissement=self.etablissement)

        self.assertEqual(
            self._connexion("73658334").status_code, status.HTTP_401_UNAUTHORIZED
        )

    def test_une_saisie_vide_ne_designe_personne(self):
        self.assertEqual(
            self._connexion("").status_code, status.HTTP_400_BAD_REQUEST
        )

    def test_un_numero_trop_court_ne_designe_personne(self):
        """« 3334 » ramenerait tous les numeros qui s'y terminent."""
        self.assertIsNone(authenticate(username="8334", password=MOT_DE_PASSE))
