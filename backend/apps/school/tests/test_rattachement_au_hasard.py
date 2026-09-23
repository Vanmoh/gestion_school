"""La commande de demonstration qui rattache les eleves au hasard.

Elle tire au sort: sur de vraies familles, elle donnerait a des inconnus
l'acces aux notes et aux frais d'enfants qui ne sont pas les leurs. Ces tests
verifient ses trois garde-fous: elle ne fait rien sans qu'on le demande, elle
ecrit de quoi tout defaire, et son annulation respecte les corrections faites
entre-temps.
"""

from datetime import date
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory

from django.contrib.auth import get_user_model
from django.core.management import CommandError, call_command
from django.test import TestCase

from apps.accounts.models import UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, ParentProfile, Student

User = get_user_model()


class RattachementAuHasardTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etab = Etablissement.objects.create(name="Ecole du hasard", code="EHAS")
        annee = AcademicYear.objects.create(
            name="2025-2026 hasard",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        classe = ClassRoom.objects.create(
            name="6eme C", academic_year=annee, etablissement=cls.etab
        )

        for rang in range(3):
            compte = User.objects.create_user(
                username=f"eleve_hasard_{rang}",
                password="Pass1234!",
                role=UserRole.STUDENT,
                etablissement=cls.etab,
            )
            Student.objects.create(
                user=compte, classroom=classe, etablissement=cls.etab, gender="M"
            )

        compte_parent = User.objects.create_user(
            username="parent_hasard",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=cls.etab,
        )
        cls.parent = ParentProfile.objects.create(
            user=compte_parent, etablissement=cls.etab
        )

    def test_sans_confirmation_rien_n_est_ecrit(self):
        sortie = StringIO()
        call_command("rattacher_parents_au_hasard", stdout=sortie)

        self.assertIn("Essai a blanc", sortie.getvalue())
        self.assertEqual(Student.objects.filter(parent__isnull=True).count(), 3)

    def test_avec_confirmation_les_eleves_sont_rattaches(self):
        with TemporaryDirectory() as dossier:
            trace = Path(dossier) / "liens.json"
            call_command(
                "rattacher_parents_au_hasard",
                confirmer=True,
                trace=str(trace),
                stdout=StringIO(),
            )

            self.assertEqual(Student.objects.filter(parent__isnull=True).count(), 0)
            self.assertTrue(trace.exists())

    def test_l_annulation_defait_ce_qui_a_ete_tire(self):
        with TemporaryDirectory() as dossier:
            trace = Path(dossier) / "liens.json"
            call_command(
                "rattacher_parents_au_hasard",
                confirmer=True,
                trace=str(trace),
                stdout=StringIO(),
            )

            call_command(
                "rattacher_parents_au_hasard", annuler=str(trace), stdout=StringIO()
            )

        self.assertEqual(Student.objects.filter(parent__isnull=True).count(), 3)

    def test_l_annulation_respecte_une_correction_faite_entre_temps(self):
        """Quelqu'un a corrige la fiche a la main: on n'efface pas son travail."""
        with TemporaryDirectory() as dossier:
            trace = Path(dossier) / "liens.json"
            call_command(
                "rattacher_parents_au_hasard",
                confirmer=True,
                trace=str(trace),
                stdout=StringIO(),
            )

            # Cree apres le tirage: sinon le sort pouvait le designer
            # lui-meme, et la « correction » n'en aurait pas ete une.
            autre_compte = User.objects.create_user(
                username="vrai_parent",
                password="Pass1234!",
                role=UserRole.PARENT,
                etablissement=self.etab,
            )
            vrai_parent = ParentProfile.objects.create(
                user=autre_compte, etablissement=self.etab
            )

            corrige = Student.objects.first()
            Student.objects.filter(pk=corrige.pk).update(parent=vrai_parent)

            call_command(
                "rattacher_parents_au_hasard", annuler=str(trace), stdout=StringIO()
            )

        corrige.refresh_from_db()
        self.assertEqual(corrige.parent_id, vrai_parent.id)

    def test_des_parents_sont_crees_pour_faire_des_familles_credibles(self):
        """Six parents pour six cents eleves donneraient cent enfants chacun."""
        with TemporaryDirectory() as dossier:
            trace = Path(dossier) / "liens.json"
            call_command(
                "rattacher_parents_au_hasard",
                confirmer=True,
                creer_des_parents=True,
                trace=str(trace),
                stdout=StringIO(),
            )

            # 3 eleves, 1 parent existant: il en faut deux de plus pour
            # descendre a deux ou trois enfants par famille.
            self.assertGreater(ParentProfile.objects.count(), 1)
            self.assertEqual(Student.objects.filter(parent__isnull=True).count(), 0)

    def test_l_annulation_retire_aussi_les_parents_inventes(self):
        """Sans cela, defaire les rattachements laisserait des fantomes."""
        comptes_avant = User.objects.count()

        with TemporaryDirectory() as dossier:
            trace = Path(dossier) / "liens.json"
            call_command(
                "rattacher_parents_au_hasard",
                confirmer=True,
                creer_des_parents=True,
                trace=str(trace),
                stdout=StringIO(),
            )
            call_command(
                "rattacher_parents_au_hasard", annuler=str(trace), stdout=StringIO()
            )

        self.assertEqual(ParentProfile.objects.count(), 1)
        self.assertEqual(User.objects.count(), comptes_avant)

    def test_sans_aucun_parent_la_commande_le_dit(self):
        ParentProfile.objects.all().delete()

        with self.assertRaises(CommandError):
            call_command("rattacher_parents_au_hasard", confirmer=True, stdout=StringIO())
