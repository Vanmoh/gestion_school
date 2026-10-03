"""Chaque role ne lit du tableau de bord que ce qui le concerne.

`/dashboard/` rendait **la meme charge utile a tout le monde**. Un parent et un
eleve recevaient donc le recouvrement de l'ecole (93,0 %), ses 5 040 000 FCFA
d'impayes et sa **masse salariale de 29 913 950 FCFA**. Un censeur et un
surveillant aussi, alors que la matrice leur interdit le module `finance`. Un
comptable recevait la moyenne generale et les absences des eleves, qui ne le
concernent pas.

La matrice classait pourtant parent, eleve et enseignant en `L*` -- lecture
**restreinte**. L'etoile y est documentaire: c'est au code de l'appliquer, et la
vue ne regardait pas le role. Le meme defaut avait ete corrige pour les depenses
et les baremes (`ExpenseViewSet` rend `none()` a une famille); il restait sur
l'ecran le plus regarde.

Ces tests n'enumerent pas une politique a la main: ils interrogent la matrice
par `can_read` et `is_scoped`, de sorte qu'un droit modifie dans `access.py` se
repercute ici sans qu'on y pense. Un test qui recopierait la liste des cles
autorisees finirait par la contredire.
"""

from datetime import date
from decimal import Decimal

from django.core.cache import cache
from django.utils import timezone
from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.access import can_read, is_scoped
from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    FeeType,
    Payment,
    Student,
    StudentFee,
)
from apps.school.portee_du_tableau_de_bord import (
    MODULE_DU_CHIFFRE,
    peut_lire_globalement,
)

TOUS_LES_ROLES = (
    UserRole.DIRECTOR,
    UserRole.CENSOR,
    UserRole.ACCOUNTANT,
    UserRole.SUPERVISOR,
    UserRole.TEACHER,
    UserRole.PARENT,
    UserRole.STUDENT,
)


class SocleDesRoles(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des rôles", code="LDR"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        compte = User.objects.create_user(
            username="ldr.eleve",
            password="x",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=compte,
            matricule="LDR0001",
            classroom=cls.classe,
            etablissement=cls.etablissement,
        )
        # De quoi faire exister un recouvrement: sans frais, les cles de
        # finance valent zero et le test ne prouverait rien.
        frais = StudentFee.objects.create(
            student=cls.eleve,
            academic_year=cls.annee,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("10000"),
            due_date=date(2025, 10, 5),
        )
        Payment.objects.create(
            fee=frais,
            etablissement=cls.etablissement,
            amount=Decimal("6000"),
            method="especes",
        )

        cls.comptes = {}
        for role in TOUS_LES_ROLES:
            cls.comptes[role] = User.objects.create_user(
                username=f"ldr.{role}",
                password="x",
                role=role,
                etablissement=cls.etablissement,
            )

    def setUp(self):
        cache.clear()

    def _bord(self, role, route="/api/dashboard/"):
        client = APIClient()
        client.force_authenticate(user=self.comptes[role])
        return client.get(
            route,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
            HTTP_X_ACADEMIC_YEAR_ID=str(self.annee.id),
        )


class LaMatriceDecideDesCleTests(SocleDesRoles):
    def test_chaque_role_recoit_exactement_ce_que_la_matrice_accorde(self):
        """Le test central: la matrice, pas une liste recopiee.

        Pour chaque role et chaque chiffre, la cle est presente si et seulement
        si le role lit ce module **sans restriction**. Un droit modifie dans
        `access.py` se repercute donc ici sans qu'on y pense.
        """
        for role in TOUS_LES_ROLES:
            with self.subTest(role=role):
                reponse = self._bord(role)
                self.assertEqual(
                    reponse.status_code, status.HTTP_200_OK, reponse.data
                )
                for cle, module in MODULE_DU_CHIFFRE.items():
                    attendu = peut_lire_globalement(role, module)
                    self.assertEqual(
                        cle in reponse.data,
                        attendu,
                        f"{role}: « {cle} » ({module}) devrait "
                        f"{'etre rendu' if attendu else 'etre retire'}",
                    )

    def test_l_annee_et_l_ecole_restent_pour_tous(self):
        """Ce ne sont pas des chiffres, ce sont les coordonnees de la lecture.

        Un ecran qui les cacherait ne saurait plus de quoi il parle.
        """
        for role in TOUS_LES_ROLES:
            with self.subTest(role=role):
                rendu = self._bord(role).data
                self.assertIn("academic_year", rendu)
                self.assertEqual(rendu["academic_year"]["name"], "2025-2026")


class LaFamilleNeLitPasLesComptesDeLEcoleTests(SocleDesRoles):
    """Le cas qui a motive ce lot, nomme explicitement."""

    def test_un_parent_ne_recoit_ni_recouvrement_ni_masse_salariale(self):
        rendu = self._bord(UserRole.PARENT).data

        for interdit in (
            "collection_rate",
            "fees_due",
            "fees_collected",
            "fees_outstanding",
            "students_unpaid",
            "payroll_total",
            "payroll_count",
            "monthly_revenue",
        ):
            self.assertNotIn(interdit, rendu, interdit)

    def test_un_eleve_non_plus(self):
        rendu = self._bord(UserRole.STUDENT).data

        self.assertNotIn("collection_rate", rendu)
        self.assertNotIn("payroll_total", rendu)

    def test_un_parent_ne_recoit_pas_la_moyenne_de_l_ecole(self):
        """`grades` est `L*` pour une famille: les notes de son enfant.

        Une moyenne generale n'a pas de version restreinte -- c'est une somme
        sur toute l'ecole -- donc elle ne lui revient pas du tout.
        """
        self.assertNotIn("general_average", self._bord(UserRole.PARENT).data)

    def test_un_parent_ne_suit_pas_l_assiduite_des_enseignants(self):
        rendu = self._bord(UserRole.PARENT).data

        self.assertNotIn("teacher_absences", rendu)
        self.assertNotIn("teacher_late", rendu)


class ChaqueProfilDEncadrementVoitSonDomaineTests(SocleDesRoles):
    """Et pas celui du voisin: la restriction coupe dans les deux sens."""

    def test_le_comptable_a_l_argent_mais_pas_les_notes(self):
        rendu = self._bord(UserRole.ACCOUNTANT).data

        self.assertIn("collection_rate", rendu)
        self.assertIn("payroll_total", rendu)
        # `grades` et `attendance` sont a « - » pour lui.
        self.assertNotIn("general_average", rendu)
        self.assertNotIn("monthly_absences", rendu)

    def test_le_censeur_a_le_pedagogique_mais_pas_la_caisse(self):
        rendu = self._bord(UserRole.CENSOR).data

        self.assertIn("general_average", rendu)
        self.assertIn("teacher_absences", rendu)
        self.assertIn("payroll_total", rendu)
        # `finance` est a « - » pour lui.
        self.assertNotIn("collection_rate", rendu)
        self.assertNotIn("fees_outstanding", rendu)

    def test_le_surveillant_suit_les_eleves_et_rien_d_autre(self):
        rendu = self._bord(UserRole.SUPERVISOR).data

        self.assertIn("students", rendu)
        self.assertIn("monthly_absences", rendu)
        self.assertNotIn("collection_rate", rendu)
        self.assertNotIn("payroll_total", rendu)
        # L'emargement des enseignants ne le concerne pas.
        self.assertNotIn("teacher_absences", rendu)

    def test_le_directeur_garde_tout(self):
        rendu = self._bord(UserRole.DIRECTOR).data

        for cle in MODULE_DU_CHIFFRE:
            self.assertIn(cle, rendu, cle)


class LeCacheNeContournePasLaRestrictionTests(SocleDesRoles):
    def test_une_lecture_de_directeur_ne_remplit_pas_l_ecran_d_un_parent(self):
        """Le piege du cache, et la raison de restreindre aussi a sa sortie.

        La charge utile est mise en cache **complete** -- elle ne depend que de
        l'etablissement et de l'annee, pas du compte qui lit, et une cle par
        role multiplierait le cache par neuf. Mais sans restriction au sortir du
        cache, le premier directeur a consulter l'ecran remplissait la cle, et
        la famille qui lisait dans la minute recevait sa charge utile entiere.
        """
        du_directeur = self._bord(UserRole.DIRECTOR).data
        self.assertIn("payroll_total", du_directeur)

        # Sans vider le cache: c'est tout l'objet du test.
        du_parent = self._bord(UserRole.PARENT).data

        self.assertNotIn("payroll_total", du_parent)
        self.assertNotIn("collection_rate", du_parent)


class LEcheancierEstUnEtatDeCaisseTests(SocleDesRoles):
    """Il releve de `finance`, donc il se refuse comme le reste."""

    def test_le_directeur_et_le_comptable_y_ont_droit(self):
        for role in (UserRole.DIRECTOR, UserRole.ACCOUNTANT):
            with self.subTest(role=role):
                reponse = self._bord(role, route="/api/dashboard/echeancier/")
                self.assertEqual(reponse.status_code, status.HTTP_200_OK)

    def test_le_censeur_le_surveillant_et_la_famille_non(self):
        for role in (
            UserRole.CENSOR,
            UserRole.SUPERVISOR,
            UserRole.TEACHER,
            UserRole.PARENT,
            UserRole.STUDENT,
        ):
            with self.subTest(role=role):
                reponse = self._bord(role, route="/api/dashboard/echeancier/")
                self.assertEqual(
                    reponse.status_code, status.HTTP_403_FORBIDDEN, reponse.data
                )


class LaTableDesPorteesEstCompleteTests(TestCase):
    """Un chiffre ajoute sans portee serait rendu a tout le monde.

    C'est ainsi que la masse salariale est arrivee dans l'ecran d'un parent: on
    ajoute une cle a la charge utile, et rien ne demande a quel module elle
    appartient. Ce test ferme la porte.
    """

    def test_chaque_module_cite_existe_dans_la_matrice(self):
        for cle, module in MODULE_DU_CHIFFRE.items():
            with self.subTest(cle=cle):
                # `can_read` leve `UnknownModule` sur un module inconnu: une
                # faute de frappe dans la table se verrait ici et non en
                # production.
                can_read(UserRole.DIRECTOR, module)
                is_scoped(UserRole.DIRECTOR, module)


class ToutChiffreRenduEstClasseTests(SocleDesRoles):
    """Un chiffre ajoute sans portee serait rendu a tout le monde.

    C'est ainsi que la masse salariale est arrivee dans l'ecran d'un parent: on
    ajoute une cle a la charge utile, et rien ne demande a quel module elle
    appartient.

    Le test interroge la **reponse reelle** d'un directeur -- qui recoit tout --
    et non le source de la vue: une premiere version analysait le texte du
    fichier et ramassait les cles imbriquees de `academic_year`, ce qui en dit
    long sur la solidite de cette approche.
    """

    # Les coordonnees de la lecture, qui ne sont pas des chiffres: un ecran qui
    # les cacherait ne saurait plus de quoi il parle.
    COORDONNEES = {"academic_year", "active_etablissement"}

    def test_aucune_cle_ne_sort_sans_module_declare(self):
        rendu = self._bord(UserRole.DIRECTOR).data

        sans_portee = sorted(
            set(rendu) - set(MODULE_DU_CHIFFRE) - self.COORDONNEES
        )

        self.assertEqual(
            sans_portee,
            [],
            "Ces cles de la charge utile n'ont pas de module declare dans "
            "MODULE_DU_CHIFFRE, donc elles seraient rendues a tous les "
            "roles:\n  " + "\n  ".join(sans_portee),
        )


class LaPresenceEstUneInformationDAdministrationTests(SocleDesRoles):
    """Qui est en ligne maintenant, et qui n'a jamais commence.

    La presence n'est pas un indicateur approximatif ici: le projet tient une
    websocket ouverte, le client bat toutes les vingt secondes, et chaque appel
    REST la rafraichit. La regle vit dans `apps.common.presence` -- un signe de
    vie dans les soixante-quinze secondes -- et elle ignore deliberement le
    compteur de connexions, qui reste bloque quand un socket meurt sans
    prevenir.

    Ces tests portent sur **qui a le droit de la lire** et sur l'exactitude des
    comptes, pas sur le mecanisme de presence lui-meme, qui a les siens.
    """

    def _presence(self, role):
        return self._bord(role, route="/api/dashboard/presence/")

    def test_seule_l_administration_y_a_droit(self):
        """`users` est a « - » pour tout le monde sauf SA, PRO et DIR.

        Savoir qui est connecte releve de l'administration des comptes, pas du
        pilotage pedagogique: un censeur n'a pas a savoir si le comptable est
        devant son ecran.
        """
        self.assertEqual(
            self._presence(UserRole.DIRECTOR).status_code, status.HTTP_200_OK
        )
        for role in (
            UserRole.CENSOR,
            UserRole.ACCOUNTANT,
            UserRole.SUPERVISOR,
            UserRole.TEACHER,
            UserRole.PARENT,
            UserRole.STUDENT,
        ):
            with self.subTest(role=role):
                self.assertEqual(
                    self._presence(role).status_code, status.HTTP_403_FORBIDDEN
                )

    def test_la_fenetre_rendue_est_celle_du_projet(self):
        """Et non une seconde definition de « en ligne ».

        L'ecran l'affiche telle quelle plutot que de la recopier: deux regles
        concurrentes dans la meme application finissent par se contredire.
        """
        from apps.common.presence import FENETRE_PRESENCE

        rendu = self._presence(UserRole.DIRECTOR).data

        self.assertEqual(
            rendu["fenetre_secondes"], int(FENETRE_PRESENCE.total_seconds())
        )

    def test_un_signe_de_vie_recent_compte_pour_en_ligne(self):
        from apps.chat.models import ChatPresence

        ChatPresence.objects.update_or_create(
            user=self.comptes[UserRole.TEACHER],
            defaults={"last_seen_at": timezone.now(), "is_online": True},
        )

        rendu = self._presence(UserRole.DIRECTOR).data

        self.assertEqual(rendu["en_ligne_par_role"].get(UserRole.TEACHER), 1)

    def test_un_compteur_bloque_ne_suffit_pas_a_etre_en_ligne(self):
        """Le defaut que la fenetre corrige, verifie ici.

        Un socket qui meurt sans prevenir laisse `connection_count` a 1 pour
        toujours: « un utilisateur restait vert des jours apres sa derniere
        visite ». Seul l'horodatage fait foi.
        """
        from datetime import timedelta

        from apps.chat.models import ChatPresence

        ChatPresence.objects.update_or_create(
            user=self.comptes[UserRole.TEACHER],
            defaults={
                "is_online": True,
                "connection_count": 1,
                "last_seen_at": timezone.now() - timedelta(hours=5),
            },
        )

        rendu = self._presence(UserRole.DIRECTOR).data

        self.assertEqual(rendu["total_en_ligne"], 0)

    def test_les_comptes_jamais_ouverts_sont_comptes_une_seule_fois(self):
        """Le piege de la jointure externe, et la somme qui l'a trahi.

        `chat_presence__last_seen_at__isnull=True` produit une jointure
        externe, donc elle attrape **aussi** les comptes sans ligne de
        presence. Une seconde requete pour ceux-la les comptait une fois de
        plus: 1 216 eleves « jamais connectes » pour 610 comptes.
        """
        rendu = self._presence(UserRole.DIRECTOR).data

        for role, combien in rendu["jamais_connectes_par_role"].items():
            with self.subTest(role=role):
                self.assertLessEqual(
                    combien,
                    rendu["comptes_par_role"][role],
                    f"{role}: {combien} jamais connectes pour "
                    f"{rendu['comptes_par_role'][role]} comptes",
                )

    def test_un_compte_deja_vu_n_est_plus_jamais_connecte(self):
        from apps.chat.models import ChatPresence

        avant = self._presence(UserRole.DIRECTOR).data
        self.assertEqual(
            avant["jamais_connectes_par_role"].get(UserRole.TEACHER), 1
        )

        ChatPresence.objects.update_or_create(
            user=self.comptes[UserRole.TEACHER],
            defaults={"last_seen_at": timezone.now()},
        )

        apres = self._presence(UserRole.DIRECTOR).data
        self.assertIsNone(
            apres["jamais_connectes_par_role"].get(UserRole.TEACHER)
        )
