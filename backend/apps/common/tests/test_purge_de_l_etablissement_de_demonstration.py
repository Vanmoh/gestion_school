"""Retirer une ecole de demonstration sans emporter une ecole reelle.

`bootstrap.sh` et `deploy_one_click.sh` appellent `seed_demo_data` a chaque
montage: l'ecole de demonstration reapparait donc toute seule, et se melange
aux etablissements reels dans le selecteur. `purger_comptes_demo` retirait les
comptes; rien ne retirait l'ecole.

La commande detruit des donnees. Ces tests tiennent les trois proprietes qui
rendent cela acceptable: elle montre avant d'agir, elle refuse ce qui ne
ressemble pas a un decor, et elle ne laisse rien derriere elle.
"""

from datetime import date
from io import StringIO

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.chat.models import Conversation
from apps.school.models import (
    AcademicYear,
    Announcement,
    ClassRoom,
    Etablissement,
    ExamPlanning,
    ExamSession,
    Student,
    Subject,
)

NOM_DU_DECOR = "Établissement Démo"


class SocleDeLaPurge(TestCase):
    """Une ecole de demonstration, et une ecole reelle a cote.

    La seconde n'est pas decorative: tout l'enjeu est qu'elle survive.
    """

    @classmethod
    def setUpTestData(cls):
        cls.decor = Etablissement.objects.create(name=NOM_DU_DECOR, code="ED")
        cls.reelle = Etablissement.objects.create(
            name="Lycée de la Liberté", code="LLIB"
        )

        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.decor,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6A", academic_year=cls.annee, etablissement=cls.decor
        )
        cls.matiere = Subject.objects.create(
            name="Mathématiques", code="MATH-6A", coefficient=4, classroom=cls.classe
        )

        # Trois eleves aux noms que les commandes de peuplement produisent.
        for indice, nom in enumerate(["TRAORE", "DIALLO", "KEITA"]):
            compte = User.objects.create_user(
                username=f"eleve{indice:03d}",
                password="x",
                role=UserRole.STUDENT,
                first_name="Amadou",
                last_name=nom,
                etablissement=cls.decor,
            )
            Student.objects.create(
                user=compte,
                matricule=f"ED{indice:05d}M",
                classroom=cls.classe,
                etablissement=cls.decor,
            )

        cls.session = ExamSession.objects.create(
            title="Composition T1",
            term="T1",
            academic_year=cls.annee,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 6),
        )
        ExamPlanning.objects.create(
            session=cls.session,
            classroom=cls.classe,
            subject=cls.matiere,
            exam_date=date(2025, 12, 2),
            start_time="08:00",
            end_time="10:00",
        )
        Announcement.objects.create(
            etablissement=cls.decor, title="Essai", message="m", audience="all"
        )
        Conversation.objects.create(etablissement=cls.decor, title="Équipe")

        # L'ecole reelle, avec ce qu'il faut pour qu'on voie si on l'abime.
        cls.annee_reelle = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.reelle,
        )
        cls.classe_reelle = ClassRoom.objects.create(
            name="1ère Année EM1",
            academic_year=cls.annee_reelle,
            etablissement=cls.reelle,
        )
        compte_reel = User.objects.create_user(
            username="eleve.reel",
            password="x",
            role=UserRole.STUDENT,
            first_name="Fanta",
            last_name="SANGARE",
            etablissement=cls.reelle,
        )
        Student.objects.create(
            user=compte_reel,
            matricule="IFP00001F",
            classroom=cls.classe_reelle,
            etablissement=cls.reelle,
        )

    def _purger(self, **options):
        sortie = StringIO()
        call_command(
            "purger_l_etablissement_de_demonstration",
            stdout=sortie,
            stderr=StringIO(),
            **options,
        )
        return sortie.getvalue()


class ElleMontreAvantDAgirTests(SocleDeLaPurge):
    def test_sans_confirmation_elle_ne_supprime_rien(self):
        """Une commande destructive dont le defaut est de ne rien detruire."""
        sortie = self._purger()

        self.assertIn("Rien n'a ete supprime", sortie)
        self.assertTrue(Etablissement.objects.filter(name=NOM_DU_DECOR).exists())
        self.assertEqual(Student.objects.filter(etablissement=self.decor).count(), 3)

    def test_elle_dit_ce_qu_elle_emporterait(self):
        sortie = self._purger()

        self.assertIn("Eleves", sortie)
        self.assertIn("Classes", sortie)
        self.assertIn("Annees scolaires", sortie)

    def test_une_ecole_absente_ne_fait_pas_echouer(self):
        """Relancer la commande deux fois doit rester sans effet."""
        sortie = self._purger(etablissement="École qui n'existe pas")

        self.assertIn("rien a retirer", sortie)


class ElleRefuseCeQuiNEstPasUnDecorTests(SocleDeLaPurge):
    def test_un_seul_nom_inconnu_l_arrete(self):
        """Mieux vaut refuser une suppression legitime que detruire du reel."""
        compte = User.objects.create_user(
            username="eleve900",
            password="x",
            role=UserRole.STUDENT,
            first_name="Marie",
            last_name="Dupont",
            etablissement=self.decor,
        )
        Student.objects.create(
            user=compte,
            matricule="REEL0001F",
            classroom=self.classe,
            etablissement=self.decor,
        )

        with self.assertRaises(CommandError):
            self._purger(confirmer=True)

        self.assertTrue(Etablissement.objects.filter(name=NOM_DU_DECOR).exists())

    def test_forcer_passe_outre_mais_il_faut_le_demander(self):
        compte = User.objects.create_user(
            username="eleve901",
            password="x",
            role=UserRole.STUDENT,
            first_name="Marie",
            last_name="Dupont",
            etablissement=self.decor,
        )
        Student.objects.create(
            user=compte,
            matricule="REEL0002F",
            classroom=self.classe,
            etablissement=self.decor,
        )

        self._purger(confirmer=True, forcer=True)

        self.assertFalse(Etablissement.objects.filter(name=NOM_DU_DECOR).exists())


class ElleNeLaissseRienDerriereTests(SocleDeLaPurge):
    def test_le_decor_disparait_entierement(self):
        self._purger(confirmer=True)

        self.assertFalse(Etablissement.objects.filter(name=NOM_DU_DECOR).exists())
        self.assertEqual(Student.objects.filter(etablissement=self.decor).count(), 0)
        self.assertEqual(ClassRoom.objects.filter(etablissement=self.decor).count(), 0)
        self.assertEqual(ExamPlanning.objects.count(), 0)
        self.assertEqual(ExamSession.objects.count(), 0)
        self.assertEqual(Conversation.objects.count(), 0)

    def test_l_ecole_reelle_est_intacte(self):
        """Le seul resultat qui compte vraiment."""
        self._purger(confirmer=True)

        self.assertTrue(
            Etablissement.objects.filter(name="Lycée de la Liberté").exists()
        )
        self.assertEqual(Student.objects.filter(etablissement=self.reelle).count(), 1)
        self.assertEqual(
            ClassRoom.objects.filter(etablissement=self.reelle).count(), 1
        )
        self.assertTrue(User.objects.filter(username="eleve.reel").exists())

    def test_les_comptes_orphelins_partent_aussi(self):
        """`seed_ltob_data` cree ses eleves sans etablissement.

        Ils survivaient donc a la suppression de leur ecole: cinquante et un
        comptes qui ne pointaient plus vers rien.
        """
        User.objects.create_user(
            username="student_9_0_1", password="x", role=UserRole.STUDENT
        )

        self._purger(confirmer=True)

        self.assertFalse(User.objects.filter(username="student_9_0_1").exists())

    def test_un_compte_encore_rattache_n_est_pas_emporte(self):
        """Un orphelin est un compte sans profil, pas un compte sans ecole."""
        compte = User.objects.create_user(
            username="enseignant.sans.ecole", password="x", role=UserRole.TEACHER
        )
        from apps.school.models import Teacher

        Teacher.objects.create(
            user=compte, employee_code="T-999", hire_date=date(2024, 9, 1)
        )

        self._purger(confirmer=True)

        self.assertTrue(
            User.objects.filter(username="enseignant.sans.ecole").exists()
        )

    def test_elle_annonce_les_ecoles_qui_restent(self):
        sortie = self._purger(confirmer=True)

        self.assertIn("Ecoles presentes en base", sortie)
        self.assertIn("Lycée de la Liberté", sortie)
