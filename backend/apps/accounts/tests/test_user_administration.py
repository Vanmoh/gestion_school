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

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ParentProfile,
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

    def test_le_provisoire_ne_sert_qu_une_fois(self):
        """Il est dicte au guichet: il doit cesser des qu'il a servi.

        C'est la seule chose qui le rende sans danger, et la
        reinitialisation l'oubliait -- un mot de passe donne de vive voix
        restait valable indefiniment.
        """
        self._reinitialiser(self.employe, "Provisoire123")

        self.employe.refresh_from_db()
        self.assertTrue(self.employe.doit_changer_mot_de_passe)


class ReinitialisationSelonLaRegleTests(_ComptesMixin, APITestCase):
    """Rendre son acces a une famille inscrite avant l'application.

    Ces comptes n'ont jamais recu de mot de passe compose par la regle: on
    demandait au secretariat d'en inventer un, donc de le noter quelque
    part. Sans `password`, la reinitialisation applique la regle que
    « Personnalisation » affiche, et rend le mot de passe pour qu'on le
    lise a la famille.
    """

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Regle")
        cls.compte_eleve = cls._compte("ousmane.bagayoko", UserRole.STUDENT)
        cls.compte_eleve.first_name = "Ousmane"
        cls.compte_eleve.last_name = "Bagayoko"
        cls.compte_eleve.save(update_fields=["first_name", "last_name"])
        cls.eleve = Student.objects.create(
            user=cls.compte_eleve,
            matricule="ER1EM125E0028M",
            classroom=cls.classe,
            etablissement=cls.etablissement,
        )
        cls.compte_parent = cls._compte("bakary.sangare", UserRole.PARENT)
        cls.compte_parent.phone = "73 65 83 34"
        cls.compte_parent.save(update_fields=["phone"])

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.super_admin)

    def _selon_la_regle(self, cible):
        return self.client.post(
            f"/api/auth/users/{cible.id}/reset-password/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_l_eleve_retrouve_son_matricule_pour_mot_de_passe(self):
        reponse = self._selon_la_regle(self.compte_eleve)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertTrue(reponse.data["selon_la_regle"])
        self.assertEqual(reponse.data["mot_de_passe"], "ER1EM125E0028M")
        self.compte_eleve.refresh_from_db()
        self.assertTrue(self.compte_eleve.check_password("ER1EM125E0028M"))

    def test_le_parent_retrouve_son_numero(self):
        reponse = self._selon_la_regle(self.compte_parent)

        self.assertEqual(reponse.data["mot_de_passe"], "73658334")
        self.compte_parent.refresh_from_db()
        self.assertTrue(self.compte_parent.check_password("73658334"))

    def test_la_regle_de_l_ecole_prime(self):
        Etablissement.objects.filter(pk=self.etablissement.pk).update(
            mot_de_passe_eleve_modele="{nom}{annee}"
        )

        reponse = self._selon_la_regle(self.compte_eleve)

        self.assertEqual(reponse.data["mot_de_passe"], "Bagayoko2026")

    def test_une_regle_trop_courte_est_completee_ici_aussi(self):
        """Huit caracteres au moins: le meme remplissage qu'a l'inscription."""
        Etablissement.objects.filter(pk=self.etablissement.pk).update(
            mot_de_passe_eleve_modele="{sigle}"
        )

        reponse = self._selon_la_regle(self.compte_eleve)

        rendu = reponse.data["mot_de_passe"]
        self.assertGreaterEqual(len(rendu), 8)
        self.compte_eleve.refresh_from_db()
        self.assertTrue(self.compte_eleve.check_password(rendu))

    def test_la_famille_se_reconnecte_avec_ce_qu_on_lui_dicte(self):
        """Le mot de passe rendu, et le matricule pour identifiant."""
        reponse = self._selon_la_regle(self.compte_eleve)
        self.client.force_authenticate(None)

        connexion = self.client.post(
            "/api/auth/login/",
            {
                "username": self.eleve.matricule,
                "password": reponse.data["mot_de_passe"],
            },
            format="json",
        )

        self.assertEqual(connexion.status_code, status.HTTP_200_OK, connexion.data)

    def test_le_personnel_n_a_pas_de_regle_et_le_dit(self):
        """Inventer un mot de passe pour un comptable n'aurait aucun sens."""
        comptable = self._compte("comptable_sans_regle", UserRole.ACCOUNTANT)

        reponse = self._selon_la_regle(comptable)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        comptable.refresh_from_db()
        self.assertTrue(comptable.check_password("Pass1234!"))

    def test_un_mot_de_passe_fourni_reste_prioritaire(self):
        reponse = self.client.post(
            f"/api/auth/users/{self.compte_eleve.id}/reset-password/",
            {"password": "ChoisiALaMain1"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertFalse(reponse.data["selon_la_regle"])
        # Le mot de passe n'est pas renvoye: l'appelant l'a ecrit lui-meme,
        # et le rendre le ferait traverser les journaux pour rien.
        self.assertEqual(reponse.data["mot_de_passe"], "")
        self.compte_eleve.refresh_from_db()
        self.assertTrue(self.compte_eleve.check_password("ChoisiALaMain1"))


class ReouvertureDesAccesTests(_ComptesMixin, APITestCase):
    """Rendre ses acces a une classe entiere, sans toucher a ceux qui entrent.

    Les familles inscrites avant l'application portent un identifiant
    compose a partir du nom et un mot de passe que personne ne leur a jamais
    remis. Les reprendre une par une, pour huit cents eleves, ne se fait
    pas.
    """

    URL = "/api/auth/users/rouvrir-les-acces/"

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Reouverture")
        cls.autre_classe = ClassRoom.objects.create(
            name="5ème B", academic_year=cls.annee, etablissement=cls.etablissement
        )

        cls.compte_parent = cls._compte("bakary.sangare", UserRole.PARENT)
        cls.compte_parent.phone = "73 65 83 34"
        cls.compte_parent.save(update_fields=["phone"])
        cls.parent = ParentProfile.objects.create(
            user=cls.compte_parent, etablissement=cls.etablissement
        )

        cls.eleve = cls._eleve_de_la_classe("ousmane.bagayoko", "RO1EM125E0028M")
        cls.cadet = cls._eleve_de_la_classe("awa.bagayoko", "RO1EM125E0029F")
        cls.voisin = cls._eleve_de_la_classe(
            "modibo.keita", "RO1DB125E0011M", classe=cls.autre_classe
        )

    @classmethod
    def _eleve_de_la_classe(cls, username, matricule, classe=None):
        compte = cls._compte(username, UserRole.STUDENT)
        prenom, nom = username.split(".")
        compte.first_name = prenom.capitalize()
        compte.last_name = nom.capitalize()
        compte.save(update_fields=["first_name", "last_name"])
        return Student.objects.create(
            user=compte,
            matricule=matricule,
            classroom=classe or cls.classe,
            parent=cls.parent,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.super_admin)

    def _rouvrir(self, **charge):
        return self.client.post(
            self.URL,
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_une_classe_entiere_retrouve_ses_acces(self):
        reponse = self._rouvrir(classroom=self.classe.id)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        matricules = {ligne["matricule"] for ligne in reponse.data["comptes"]}
        self.assertEqual(matricules, {"RO1EM125E0028M", "RO1EM125E0029F"})

    def test_les_acces_sont_rendus_en_clair(self):
        """Ils n'existent qu'a cet instant: le serveur les hache aussitot."""
        reponse = self._rouvrir(classroom=self.classe.id)

        ligne = next(
            l for l in reponse.data["comptes"] if l["matricule"] == "RO1EM125E0028M"
        )
        self.assertEqual(ligne["mot_de_passe"], "RO1EM125E0028M")
        self.eleve.user.refresh_from_db()
        self.assertTrue(self.eleve.user.check_password("RO1EM125E0028M"))

    def test_une_autre_classe_n_est_pas_touchee(self):
        self._rouvrir(classroom=self.classe.id)

        self.voisin.user.refresh_from_db()
        self.assertTrue(self.voisin.user.check_password("Pass1234!"))

    def test_un_compte_deja_utilise_garde_son_mot_de_passe(self):
        """La garde qui rend le geste sur: on ne met personne dehors."""
        self.eleve.user.last_login = timezone.now()
        self.eleve.user.save(update_fields=["last_login"])

        reponse = self._rouvrir(classroom=self.classe.id)

        self.eleve.user.refresh_from_db()
        self.assertTrue(self.eleve.user.check_password("Pass1234!"))
        self.assertEqual(reponse.data["deja_utilises"], 1)

    def test_le_parent_de_la_fratrie_n_a_qu_un_mot_de_passe(self):
        """Trois freres, un seul pere: le recomposer par enfant en poserait
        trois, dont seul le dernier fonctionnerait."""
        reponse = self._rouvrir(classroom=self.classe.id)

        rendus = {
            ligne["parent_mot_de_passe"] for ligne in reponse.data["comptes"]
        }
        self.assertEqual(rendus, {"73658334"})
        self.compte_parent.refresh_from_db()
        self.assertTrue(self.compte_parent.check_password("73658334"))

    def test_le_provisoire_ne_sert_qu_une_fois(self):
        self._rouvrir(classroom=self.classe.id)

        self.eleve.user.refresh_from_db()
        self.compte_parent.refresh_from_db()
        self.assertTrue(self.eleve.user.doit_changer_mot_de_passe)
        self.assertTrue(self.compte_parent.doit_changer_mot_de_passe)

    def test_la_famille_entre_avec_ce_qu_on_lui_dicte(self):
        reponse = self._rouvrir(classroom=self.classe.id)
        ligne = next(
            l for l in reponse.data["comptes"] if l["matricule"] == "RO1EM125E0028M"
        )
        self.client.force_authenticate(None)

        connexion = self.client.post(
            "/api/auth/login/",
            {"username": ligne["matricule"], "password": ligne["mot_de_passe"]},
            format="json",
        )

        self.assertEqual(connexion.status_code, status.HTTP_200_OK, connexion.data)

    def test_une_liste_d_eleves_fait_aussi_l_affaire(self):
        reponse = self._rouvrir(students=[self.voisin.id])

        matricules = {ligne["matricule"] for ligne in reponse.data["comptes"]}
        self.assertEqual(matricules, {"RO1DB125E0011M"})

    def test_sans_perimetre_le_geste_est_refuse(self):
        """Rouvrir « tout » d'un seul appel n'est demande par aucun ecran."""
        reponse = self._rouvrir()

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_enseignant_ne_rouvre_pas_les_acces(self):
        self.client.force_authenticate(self._compte("prof_reouverture", UserRole.TEACHER))

        reponse = self._rouvrir(classroom=self.classe.id)

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_une_autre_ecole_reste_hors_de_portee(self):
        ailleurs = Etablissement.objects.create(name="Etab Voisin", code="EV")
        direction_voisine = User.objects.create_user(
            username="dir_voisin",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=ailleurs,
        )
        self.client.force_authenticate(direction_voisine)

        reponse = self.client.post(
            self.URL,
            {"classroom": self.classe.id},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(ailleurs.id),
        )

        self.assertEqual(reponse.data["comptes"], [])
        self.eleve.user.refresh_from_db()
        self.assertTrue(self.eleve.user.check_password("Pass1234!"))


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

    def test_un_compte_sans_donnees_liees_attend_lui_aussi_la_confirmation(self):
        # Ce test figeait l'inverse: un compte nu partait au premier appel.
        # L'ecran obtenait pourtant l'inventaire de ce qu'une suppression
        # emporterait en lancant cette suppression -- un compte sans rien
        # d'attache etait donc detruit a l'instant ou l'on cherchait a savoir
        # ce qu'il emportait, sans qu'aucune question ait ete posee.
        simple = self._compte("compte_nu", UserRole.ACCOUNTANT)

        reponse = self._supprimer(simple)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=simple.pk).exists())

    def test_un_compte_sans_donnees_liees_se_supprime_une_fois_confirme(self):
        simple = self._compte("compte_nu_confirme", UserRole.ACCOUNTANT)

        reponse = self._supprimer(simple, confirme=True)

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
