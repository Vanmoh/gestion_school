"""L'administration des comptes: desactiver, reinitialiser, supprimer.

Trois operations que l'API annoncait sans les faire. `is_active` et
`password` etaient absents du serializer, et DRF ecarte en silence ce qu'il
ne connait pas: une demande de desactivation recevait 200 et le compte
restait ouvert, une reinitialisation recevait 200 et le mot de passe ne
changeait pas. L'administration croyait avoir coupe un acces; l'employe parti
gardait le sien.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
)


class _ComptesMixin:
    @classmethod
    def _decor(cls, nom="Etab Comptes"):
        cls.etablissement = Etablissement.objects.create(name=nom, code="EC")
        cls.annee = AcademicYear.objects.create(
            name=f"2025-2026 {nom[-3:]}",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.direction = cls._compte("dir_comptes", UserRole.DIRECTOR)
        cls.super_admin = cls._compte("sa_comptes", UserRole.SUPER_ADMIN)

    @classmethod
    def _compte(cls, username, role, etablissement=None):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=role,
            etablissement=etablissement or cls.etablissement,
        )

    def _modifier(self, cible, **charge):
        return self.client.patch(
            f"/api/auth/users/{cible.id}/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )


class DesactivationTests(_ComptesMixin, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._decor()
        cls.employe = cls._compte("employe", UserRole.ACCOUNTANT)

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def test_un_compte_se_desactive(self):
        """Il recevait 200 sans rien changer: l'acces restait ouvert."""
        reponse = self._modifier(self.employe, is_active=False)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.employe.refresh_from_db()
        self.assertFalse(self.employe.is_active)

    def test_un_compte_desactive_se_reactive(self):
        self.employe.is_active = False
        self.employe.save(update_fields=["is_active"])

        self._modifier(self.employe, is_active=True)

        self.employe.refresh_from_db()
        self.assertTrue(self.employe.is_active)

    def test_on_ne_se_desactive_pas_soi_meme(self):
        """On se retrouverait dehors sans pouvoir revenir."""
        reponse = self._modifier(self.direction, is_active=False)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.direction.refresh_from_db()
        self.assertTrue(self.direction.is_active)

    def test_le_dernier_super_administrateur_ne_se_coupe_pas(self):
        """Sans lui, plus personne ne pourrait rien reactiver."""
        self.client.force_authenticate(self.super_admin)
        autre = self._compte("sa_second", UserRole.SUPER_ADMIN)

        # Tant qu'il en reste un autre, la desactivation passe.
        premiere = self._modifier(autre, is_active=False)
        self.assertEqual(premiere.status_code, status.HTTP_200_OK, premiere.data)

        # Le dernier actif, non.
        encore_un = self._compte("sa_troisieme", UserRole.SUPER_ADMIN)
        self.client.force_authenticate(encore_un)
        derniere = self._modifier(self.super_admin, is_active=False)
        self.assertEqual(derniere.status_code, status.HTTP_200_OK, derniere.data)

        # Il ne reste plus qu'`encore_un`, qui ne peut pas se couper.
        ultime = self._modifier(encore_un, is_active=False)
        self.assertEqual(ultime.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_etat_du_compte_est_visible(self):
        lignes = self.client.get(
            "/api/auth/users/", HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        ).data["results"]

        ligne = next(l for l in lignes if l["id"] == self.employe.id)
        self.assertIn("is_active", ligne)
        self.assertIn("last_login", ligne)
        self.assertIn("date_joined", ligne)

    def test_un_compte_jamais_utilise_se_signale(self):
        """C'est ce qu'on cherche en faisant le menage des comptes."""
        lignes = self.client.get(
            "/api/auth/users/", HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        ).data["results"]

        ligne = next(l for l in lignes if l["id"] == self.employe.id)
        self.assertTrue(ligne["has_never_logged_in"])


class ReinitialisationTests(_ComptesMixin, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Mot De Passe")
        cls.employe = cls._compte("employe_mdp", UserRole.ACCOUNTANT)

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def _reinitialiser(self, cible, mot_de_passe):
        return self.client.post(
            f"/api/auth/users/{cible.id}/reset-password/",
            {"password": mot_de_passe},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_l_administration_fixe_un_mot_de_passe_provisoire(self):
        reponse = self._reinitialiser(self.employe, "Provisoire123")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.employe.refresh_from_db()
        self.assertTrue(self.employe.check_password("Provisoire123"))

    def test_le_nouveau_mot_de_passe_ouvre_la_session(self):
        self._reinitialiser(self.employe, "Provisoire123")

        connexion = self.client.post(
            "/api/auth/login/",
            {"username": self.employe.username, "password": "Provisoire123"},
            format="json",
        )

        self.assertEqual(connexion.status_code, status.HTTP_200_OK, connexion.data)

    def test_un_mot_de_passe_trop_court_est_refuse(self):
        reponse = self._reinitialiser(self.employe, "court")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.employe.refresh_from_db()
        self.assertTrue(self.employe.check_password("Pass1234!"))

    def test_le_mot_de_passe_ne_passe_plus_en_silence_par_la_modification(self):
        """Il recevait 200 et ne changeait rien: le refus indique la porte."""
        reponse = self._modifier(self.employe, password="AutreMotDePasse1")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Réinitialiser", str(reponse.data))
        self.employe.refresh_from_db()
        self.assertTrue(self.employe.check_password("Pass1234!"))

    def test_l_enseignant_ne_reinitialise_pas_les_mots_de_passe(self):
        enseignant = self._compte("prof_curieux", UserRole.TEACHER)
        self.client.force_authenticate(enseignant)

        reponse = self._reinitialiser(self.employe, "Provisoire123")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)


class SuppressionTests(_ComptesMixin, APITestCase):
    """La suppression reste possible, mais dit d'abord ce qu'elle emporte."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Suppression")
        cls.matiere = Subject.objects.create(
            name="Mathématiques", code="MA", coefficient=1, classroom=cls.classe
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.super_admin)

    def _enseignant_avec_donnees(self):
        compte = self._compte("prof_lie", UserRole.TEACHER)
        enseignant = Teacher.objects.create(
            user=compte,
            employee_code="PL1",
            hire_date=date(2025, 9, 1),
            hourly_rate=Decimal("1000.00"),
            etablissement=self.etablissement,
        )
        TeacherAssignment.objects.create(
            teacher=enseignant, subject=self.matiere, classroom=self.classe
        )
        return compte

    def _supprimer(self, cible, confirme=False):
        url = f"/api/auth/users/{cible.id}/"
        if confirme:
            url = f"{url}?confirm=true"
        return self.client.delete(
            url, HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )

    def test_un_compte_sans_donnees_liees_se_supprime(self):
        simple = self._compte("compte_nu", UserRole.ACCOUNTANT)

        reponse = self._supprimer(simple)

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(pk=simple.pk).exists())

    def test_un_compte_lie_annonce_ce_qu_il_emporte(self):
        compte = self._enseignant_avec_donnees()

        reponse = self._supprimer(compte)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("fiche enseignant", str(reponse.data))
        self.assertTrue(User.objects.filter(pk=compte.pk).exists())

    def test_le_refus_oriente_vers_la_desactivation(self):
        compte = self._enseignant_avec_donnees()

        reponse = self._supprimer(compte)

        self.assertIn("ésactivez", str(reponse.data))

    def test_la_confirmation_explicite_autorise_la_suppression(self):
        compte = self._enseignant_avec_donnees()

        reponse = self._supprimer(compte, confirme=True)

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Teacher.objects.filter(user_id=compte.pk).exists())

    def test_on_ne_supprime_pas_son_propre_compte(self):
        reponse = self._supprimer(self.super_admin)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=self.super_admin.pk).exists())

    def test_l_inventaire_nomme_la_fiche_eleve(self):
        compte = self._compte("eleve_lie", UserRole.STUDENT)
        Student.objects.create(
            user=compte,
            classroom=self.classe,
            etablissement=self.etablissement,
            gender="F",
        )

        reponse = self._supprimer(compte)

        self.assertIn("fiche élève", str(reponse.data))


class FiltreParEtatTests(_ComptesMixin, APITestCase):
    """Sortir les comptes restes ouverts apres un depart."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Filtre")
        cls.actif = cls._compte("toujours_la", UserRole.ACCOUNTANT)
        cls.parti = cls._compte("deja_parti", UserRole.TEACHER)
        cls.parti.is_active = False
        cls.parti.save(update_fields=["is_active"])

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def _lister(self, **params):
        return self.client.get(
            "/api/auth/users/",
            params,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        ).data["results"]

    def test_le_filtre_isole_les_comptes_desactives(self):
        lignes = self._lister(is_active="false")

        identifiants = {ligne["id"] for ligne in lignes}
        self.assertIn(self.parti.id, identifiants)
        self.assertNotIn(self.actif.id, identifiants)

    def test_le_filtre_isole_les_comptes_ouverts(self):
        lignes = self._lister(is_active="true")

        identifiants = {ligne["id"] for ligne in lignes}
        self.assertIn(self.actif.id, identifiants)
        self.assertNotIn(self.parti.id, identifiants)

    def test_sans_filtre_les_deux_apparaissent(self):
        identifiants = {ligne["id"] for ligne in self._lister()}

        self.assertIn(self.actif.id, identifiants)
        self.assertIn(self.parti.id, identifiants)


class RechercheTests(_ComptesMixin, APITestCase):
    """Chercher un compte par ce qui l'identifie, pas par son domaine.

    L'email entier entrait dans la recherche. Tous les comptes d'une ecole
    partageant « @ifp-obk.com », taper une lettre qu'il contient -- le « o »
    du domaine -- ramenait l'annuaire complet, et la recherche paraissait
    cassee: on cherchait « o » et Ali Cisse ressortait.
    """

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Recherche")
        cls.cisse = cls._compte("stu_014", UserRole.STUDENT)
        cls.cisse.first_name = "Ali"
        cls.cisse.last_name = "Cisse"
        cls.cisse.email = "stu_014@ifp-obk.com"
        cls.cisse.phone = "78785913"
        cls.cisse.save()

        cls.konate = cls._compte("stu_020", UserRole.STUDENT)
        cls.konate.first_name = "Oumou"
        cls.konate.last_name = "Konate"
        cls.konate.email = "oumou.konate@ifp-obk.com"
        cls.konate.save()

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def _chercher(self, terme):
        lignes = self.client.get(
            "/api/auth/users/",
            {"search": terme},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        ).data["results"]
        return {ligne["id"] for ligne in lignes}

    def test_le_domaine_de_l_email_ne_ramene_plus_tout_le_monde(self):
        """« o » ne doit plus trouver Ali Cisse via « @ifp-obk.com »."""
        trouves = self._chercher("o")

        self.assertNotIn(self.cisse.id, trouves)
        self.assertIn(self.konate.id, trouves)

    def test_le_domaine_seul_ne_ramene_pas_ses_porteurs(self):
        """« com » ne doit plus trouver un compte par son seul email.

        Il en trouve d'autres par leur identifiant -- « dir_comptes » en
        contient --, et c'est legitime: c'est le domaine qui est ecarte, pas
        la chaine.
        """
        trouves = self._chercher("com")

        self.assertNotIn(self.cisse.id, trouves)
        self.assertNotIn(self.konate.id, trouves)

    def test_le_prenom_trouve_son_titulaire(self):
        self.assertIn(self.cisse.id, self._chercher("ali"))

    def test_le_nom_trouve_son_titulaire(self):
        self.assertIn(self.konate.id, self._chercher("konate"))

    def test_l_identifiant_trouve_son_compte(self):
        self.assertEqual(self._chercher("stu_014"), {self.cisse.id})

    def test_le_debut_de_l_email_reste_cherchable(self):
        """« ali » trouve « ali.cisse@… »: c'est le domaine qui est écarté."""
        self.assertIn(self.konate.id, self._chercher("oumou.konate"))

    def test_le_telephone_trouve_son_titulaire(self):
        """L'écran l'annonçait parmi les critères."""
        self.assertEqual(self._chercher("78785913"), {self.cisse.id})

    def test_une_recherche_vide_ne_filtre_rien(self):
        trouves = self._chercher("")

        self.assertIn(self.cisse.id, trouves)
        self.assertIn(self.konate.id, trouves)

    def test_la_recherche_reste_bornee_a_l_etablissement(self):
        autre = Etablissement.objects.create(name="Ecole voisine recherche")
        etranger = User.objects.create_user(
            username="oumou_ailleurs",
            password="Pass1234!",
            role=UserRole.STUDENT,
            first_name="Oumou",
            etablissement=autre,
        )

        self.assertNotIn(etranger.id, self._chercher("oumou"))
