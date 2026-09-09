"""La commande qui donne un programme aux classes qui n'en ont aucun.

Une classe sans matière est un angle mort: elle apparaît partout — listes,
effectifs, emploi du temps — mais aucune note ne peut y être saisie, aucun
bulletin édité.

La commande est partie en production sans test alors qu'elle écrit en masse:
elle crée autant de matières que de classes démunies multipliées par la
taille du programme copié. Ce qui suit fixe ce dont elle promet de ne pas
s'écarter — d'où vient le programme, et ce qu'elle refuse de faire.
"""

from datetime import date
from io import StringIO

from django.core.management import call_command
from django.test import TestCase

from apps.school.models import AcademicYear, ClassRoom, Etablissement, Subject


class DoterLesClassesSansMatiereTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Dote")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.annee_voisine = AcademicYear.objects.create(
            name="2025-2026 voisin",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            etablissement=self.autre,
        )

    def _classe(self, nom, etablissement=None, annee=None):
        return ClassRoom.objects.create(
            name=nom,
            academic_year=annee or self.annee,
            etablissement=etablissement or self.etablissement,
        )

    def _programme(self, classe, matieres):
        for code, nom, coef, seances in matieres:
            Subject.objects.create(
                classroom=classe,
                code=code,
                name=nom,
                coefficient=coef,
                weekly_slots=seances,
            )

    def _appeler(self, *args):
        sortie = StringIO()
        call_command("doter_les_classes_sans_matiere", *args, stdout=sortie)
        return sortie.getvalue()

    # ----- ce qu'elle fait ----------------------------------------------

    def test_elle_copie_le_programme_sur_la_classe_demunie(self):
        pourvue = self._classe("6A")
        self._programme(pourvue, [("MAT", "Mathematiques", 4, 3), ("FRA", "Francais", 4, 4)])
        demunie = self._classe("6B")

        self._appeler()

        self.assertEqual(Subject.objects.filter(classroom=demunie).count(), 2)
        self.assertEqual(
            sorted(Subject.objects.filter(classroom=demunie).values_list("code", flat=True)),
            ["FRA", "MAT"],
        )

    def test_le_coefficient_et_le_volume_horaire_suivent(self):
        """Un programme copié sans ses coefficients ne sert à rien."""
        pourvue = self._classe("6A")
        self._programme(pourvue, [("MAT", "Mathematiques", 4, 3)])
        demunie = self._classe("6B")

        self._appeler()

        copie = Subject.objects.get(classroom=demunie, code="MAT")
        self.assertEqual(copie.name, "Mathematiques")
        self.assertEqual(int(copie.coefficient), 4)
        self.assertEqual(copie.weekly_slots, 3)

    def test_le_modele_est_la_classe_la_mieux_pourvue(self):
        """Une classe qui ne porte qu'une matière serait un mauvais patron."""
        maigre = self._classe("6A")
        self._programme(maigre, [("SPT", "Sport", 1, 1)])
        riche = self._classe("6B")
        self._programme(
            riche,
            [("MAT", "Mathematiques", 4, 3), ("FRA", "Francais", 4, 4), ("HG", "Histoire", 2, 2)],
        )
        demunie = self._classe("6C")

        self._appeler()

        self.assertEqual(Subject.objects.filter(classroom=demunie).count(), 3)
        self.assertNotIn(
            "SPT",
            Subject.objects.filter(classroom=demunie).values_list("code", flat=True),
        )

    def test_une_classe_deja_pourvue_n_est_pas_touchee(self):
        pourvue = self._classe("6A")
        self._programme(pourvue, [("MAT", "Mathematiques", 4, 3), ("FRA", "Francais", 4, 4)])
        partielle = self._classe("6B")
        self._programme(partielle, [("SPT", "Sport", 1, 1)])

        self._appeler()

        self.assertEqual(Subject.objects.filter(classroom=partielle).count(), 1)

    # ----- ce qu'elle refuse de faire -----------------------------------

    def test_sans_modele_la_classe_est_laissee_et_signalee(self):
        """Mieux vaut une classe visiblement vide qu'un programme emprunté."""
        self._classe("6A")

        sortie = self._appeler()

        self.assertEqual(Subject.objects.count(), 0)
        self.assertIn("Laissee en l'etat", sortie)
        self.assertIn("Lycee Dote", sortie)

    def test_elle_n_emprunte_pas_le_programme_d_un_autre_etablissement(self):
        """Une école ne donne pas les enseignements d'une autre."""
        voisine = self._classe("6A voisin", etablissement=self.autre, annee=self.annee_voisine)
        self._programme(voisine, [("LATIN", "Latin", 2, 2)])
        demunie = self._classe("6A")

        self._appeler()

        self.assertEqual(Subject.objects.filter(classroom=demunie).count(), 0)

    def test_la_simulation_n_ecrit_rien(self):
        pourvue = self._classe("6A")
        self._programme(pourvue, [("MAT", "Mathematiques", 4, 3)])
        demunie = self._classe("6B")

        sortie = self._appeler("--dry-run")

        self.assertEqual(Subject.objects.filter(classroom=demunie).count(), 0)
        self.assertIn("seraient creees", sortie)

    def test_l_etablissement_vise_se_restreint(self):
        pourvue = self._classe("6A")
        self._programme(pourvue, [("MAT", "Mathematiques", 4, 3)])
        self._classe("6B")

        voisine_pourvue = self._classe(
            "6A voisin", etablissement=self.autre, annee=self.annee_voisine
        )
        self._programme(voisine_pourvue, [("LATIN", "Latin", 2, 2)])
        voisine_demunie = self._classe(
            "6B voisin", etablissement=self.autre, annee=self.annee_voisine
        )

        self._appeler(f"--etab-id={self.etablissement.id}")

        self.assertEqual(Subject.objects.filter(classroom=voisine_demunie).count(), 0)

    def test_la_relancer_ne_double_pas_les_matieres(self):
        """La contrainte (classe, code) ferait échouer toute la transaction."""
        pourvue = self._classe("6A")
        self._programme(pourvue, [("MAT", "Mathematiques", 4, 3)])
        demunie = self._classe("6B")

        self._appeler()
        # La deuxième passe ne voit plus la classe: elle n'est plus démunie.
        self._appeler()

        self.assertEqual(Subject.objects.filter(classroom=demunie).count(), 1)

    def test_le_niveau_de_la_classe_n_entre_pas_en_ligne_de_compte(self):
        """Une limite assumée, fixée ici pour qu'elle reste visible.

        La commande copie le programme de la classe la mieux pourvue de
        l'établissement, quel que soit son niveau: une Terminale démunie
        reçoit donc le programme d'une 6e. C'est acceptable pour un
        établissement à tronc commun, faux ailleurs — et la direction doit
        relire ce que la commande a posé avant de saisir des notes.
        """
        sixieme = self._classe("6A")
        self._programme(sixieme, [("MAT6", "Mathematiques 6e", 4, 4)])
        terminale = self._classe("Terminale")

        self._appeler()

        self.assertEqual(
            list(Subject.objects.filter(classroom=terminale).values_list("code", flat=True)),
            ["MAT6"],
        )

    def test_sur_une_base_sans_classe_demunie_elle_ne_fait_rien(self):
        pourvue = self._classe("6A")
        self._programme(pourvue, [("MAT", "Mathematiques", 4, 3)])

        sortie = self._appeler()

        self.assertIn("0 matieres creees", sortie)
