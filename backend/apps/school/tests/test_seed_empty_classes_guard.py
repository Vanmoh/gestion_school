"""La commande de peuplement refuse de s'executer sur une base reelle.

`seed_empty_classes` ne cree pas que des eleves de demonstration: elle ouvre
pour chacun un compte utilisateur au mot de passe faible. Et elle vise un
effectif plutot que le vide, donc elle complete aussi les classes deja
peuplees -- une classe reelle de vingt-deux eleves en recoit huit de plus si
la cible est trente.

Lancee par megarde sur la production, elle melerait donc des eleves inventes
aux inscrits. Rien ne l'en empechait: son seul garde-fou etait une phrase de
docstring qui affirmait, a tort, qu'elle ne touchait jamais une classe
peuplee.
"""

from __future__ import annotations

from datetime import date

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase, override_settings

from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class SeedEmptyClassesGuardTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="LTOB Garde")
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.classe = ClassRoom.objects.create(
            name="6e A",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )

    @override_settings(DEBUG=False)
    def test_refuse_hors_debug(self):
        """DEBUG faux: la base ressemble a une base reelle, on n'y touche pas."""
        with self.assertRaises(CommandError):
            call_command("seed_empty_classes", "--cible=3")

        self.assertEqual(
            Student.objects.count(),
            0,
            "le refus doit preceder toute ecriture, pas l'interrompre a moitie",
        )

    @override_settings(DEBUG=False)
    def test_forcer_passe_outre(self):
        """L'echappement reste possible, mais il faut le demander en toutes lettres."""
        call_command("seed_empty_classes", "--cible=3", "--forcer")

        self.assertEqual(Student.objects.filter(classroom=self.classe).count(), 3)

    @override_settings(DEBUG=True)
    def test_autorise_en_developpement(self):
        """C'est le cas d'usage de la commande: une base de developpement."""
        call_command("seed_empty_classes", "--cible=3")

        self.assertEqual(Student.objects.filter(classroom=self.classe).count(), 3)

    @override_settings(DEBUG=False)
    def test_le_refus_nomme_les_classes_deja_peuplees(self):
        """Le message doit dire le vrai danger, pas seulement « refus ».

        Croire que la commande ne remplit que le vide est precisement l'erreur
        qui la ferait lancer sur la production.
        """
        with self.assertRaises(CommandError) as capture:
            call_command("seed_empty_classes")

        self.assertIn("deja peuplees", str(capture.exception))
