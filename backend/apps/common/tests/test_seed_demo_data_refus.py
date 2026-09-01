"""Le garde-fou du jeu de démonstration.

`bootstrap.sh` appelle `seed_demo_data` à chaque montage de l'environnement,
y compris sur une base locale synchronisée depuis la production. La commande
doit alors refuser: elle ajouterait sinon sa classe de démonstration, ses
élèves fictifs et des comptes au mot de passe connu au milieu des inscrits.

Le script s'appuie sur deux propriétés précises de ce refus -- un code de
sortie non nul, et le mot « Refus: » sur la sortie -- pour distinguer ce
garde-fou d'une véritable panne et poursuivre le bootstrap sans annoncer des
comptes de test qui n'existent pas. Les deux sont vérifiées ici: sans cela,
une reformulation du message ferait échouer tout le bootstrap.
"""

from datetime import date

from django.core.management import CommandError, call_command
from django.test import TestCase

from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class SeedDemoDataRefusTests(TestCase):
    def _classe(self, name):
        etablissement = Etablissement.objects.create(name="Lycée Réel")
        annee = AcademicYear.objects.create(
            etablissement=etablissement,
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 7, 1),
        )
        return ClassRoom.objects.create(
            name=name,
            academic_year=annee,
            etablissement=etablissement,
        )

    def test_il_refuse_de_semer_sur_une_base_qui_porte_de_vraies_classes(self):
        self._classe("Terminale S2")

        with self.assertRaises(CommandError) as leve:
            call_command("seed_demo_data")

        message = str(leve.exception)
        # Le motif que `bootstrap.sh` cherche pour reconnaître le garde-fou.
        self.assertIn("Refus:", message)
        self.assertIn("Terminale S2", message)
        self.assertFalse(Student.objects.exists())

    def test_la_classe_de_demonstration_ne_compte_pas_pour_une_vraie_ecole(self):
        # Semer deux fois de suite doit rester possible: « 6A » prouve
        # seulement que la commande est déjà passée par là.
        self._classe("6A")

        call_command("seed_demo_data")

        self.assertTrue(Student.objects.exists())

    def test_forcer_passe_outre_sur_une_base_jetable(self):
        self._classe("Terminale S2")

        call_command("seed_demo_data", forcer=True)

        self.assertTrue(Student.objects.exists())
