"""Le libelle d'annee imprime vient de l'ecole du document.

`_active_academic_year_label()` ne prenait aucune portee. Sans portee,
`AcademicYear.courante(None)` rend `filter(is_active=True)` trie par
`-start_date`: l'annee active de **n'importe quelle** ecole, en pratique celle
qui a commence le plus tard.

Le defaut est invisible aujourd'hui. Les quatre etablissements reels nomment
tous leur annee « 2025-2026 », donc le mauvais choix rend le bon libelle. Il se
declenchera le jour ou l'un ouvre 2026-2027 en active: les cartes, certificats
et bulletins des trois autres porteraient cette annee-la. Sur un document
imprime et remis a une famille, que personne ne peut plus corriger.

C'est pourquoi ces tests donnent a chaque ecole une annee de **nom different**:
un test ou les deux s'appellent pareil ne pourrait rien voir -- et c'est
exactement ce qui a laisse le defaut vivre.
"""

from datetime import date

from django.test import TestCase

from apps.reports.views import _active_academic_year, _active_academic_year_label
from apps.school.models import AcademicYear, Etablissement


class LAnneeImprimeeSuitLEcoleTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        # `courante(None)` trie par `-start_date`: l'ecole dont l'annee commence
        # le plus tard gagne. On la cree donc en second pour que le defaut, s'il
        # revenait, designe bien elle et non la premiere venue.
        cls.ecole_a = Etablissement.objects.create(name="École A", code="ECA")
        cls.annee_a = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.ecole_a,
            is_active=True,
        )
        cls.ecole_b = Etablissement.objects.create(name="École B", code="ECB")
        cls.annee_b = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 7, 31),
            etablissement=cls.ecole_b,
            is_active=True,
        )

    def test_le_libelle_est_celui_de_l_ecole_demandee(self):
        self.assertEqual(_active_academic_year_label(self.ecole_a), "2025-2026")
        self.assertEqual(_active_academic_year_label(self.ecole_b), "2026-2027")

    def test_l_annee_resolue_est_celle_de_l_ecole_demandee(self):
        """La date de validite d'une carte vient de la meme annee que son libelle."""
        self.assertEqual(_active_academic_year(self.ecole_a), self.annee_a)
        self.assertEqual(
            _active_academic_year(self.ecole_a).end_date, date(2026, 7, 31)
        )

    def test_sans_portee_le_choix_est_arbitraire(self):
        """Ce que fait l'appel sans portee, ecrit noir sur blanc.

        Ce test ne defend pas ce comportement: il le documente, pour qu'un
        appel sans portee reintroduit un jour se lise comme un choix et non
        comme un oubli. Il rend l'annee de l'ecole B alors que rien ne la
        designe.
        """
        self.assertEqual(_active_academic_year_label(), "2026-2027")

    def test_sans_annee_active_le_libelle_reste_lisible(self):
        """Une ecole sans annee active doit imprimer quelque chose de plausible.

        Le repli sur l'annee civile est deja dans le code; ce test le fige,
        parce qu'un libelle vide sur une carte scolaire est pire qu'un libelle
        approximatif.
        """
        ecole_c = Etablissement.objects.create(name="École C", code="ECC")

        libelle = _active_academic_year_label(ecole_c)

        self.assertRegex(libelle, r"^\d{4} - \d{4}$")
