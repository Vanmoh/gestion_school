"""Une depense sans ecole est invisible deux fois.

`Expense.etablissement` est nullable. Dix depenses de la base reelle en
profitaient -- « Achat fournitures », 120 000 F chacune, du 13 au 22 avril
2026 -- soit **1 200 000 F de charges** qu'aucun ecran ne montrait et qu'aucune
tresorerie ne comptait.

Deux fois, parce que l'orphelinat se propage: absente de la liste de chaque
etablissement, et absente de chaque annee, puisque sans ecole le rattachement a
l'annee ne peut meme pas se deduire d'une date.

Rien ne distingue ces dix lignes: meme libelle, meme montant, meme categorie,
dates consecutives. La commande ne pretend donc pas deduire a qui elles
appartiennent -- elle repartit a tour de role, et le dit.
"""

from datetime import date
from decimal import Decimal

from django.core.management import call_command
from django.test import TestCase

from apps.school.models import AcademicYear, Etablissement, Expense


class SocleDesDepensesOrphelines(TestCase):
    """Trois ecoles a nous, avec chacune son annee active.

    La base de test n'est pas vide: `9999_insert_etablissements` y cree les
    quatre ecoles reelles, **sans** annee scolaire. Elles ne sont donc pas
    candidates a la repartition -- une ecole sans annee ouverte ne peut pas
    recevoir une charge datee -- et les comptes ci-dessous ne portent que sur
    les trois que ces tests montent.
    """

    @classmethod
    def setUpTestData(cls):
        cls.ecoles = []
        for rang, (nom, code) in enumerate(
            (("École A", "ECA"), ("École B", "ECB"), ("École C", "ECC"))
        ):
            ecole = Etablissement.objects.create(name=nom, code=code)
            AcademicYear.objects.create(
                name="2025-2026",
                start_date=date(2025, 9, 1),
                end_date=date(2026, 7, 31),
                etablissement=ecole,
                is_active=True,
            )
            cls.ecoles.append(ecole)

    def _orphelines(self, combien, jour=date(2026, 4, 13)):
        for rang in range(combien):
            Expense.objects.create(
                label="Achat fournitures",
                amount=Decimal("120000"),
                date=jour,
                category="Fournitures",
                etablissement=None,
            )


class LaRepartitionTests(SocleDesDepensesOrphelines):
    def test_un_essai_a_blanc_n_ecrit_rien(self):
        """Le defaut de la commande: montrer, pas ecrire.

        Une commande qui rattache des charges a des ecoles au hasard doit se
        laisser relire avant d'agir.
        """
        self._orphelines(5)

        call_command("repartir_les_depenses_sans_ecole")

        self.assertEqual(
            Expense.objects.filter(etablissement__isnull=True).count(), 5
        )

    def test_appliquer_repartit_a_tour_de_role(self):
        self._orphelines(7)

        call_command("repartir_les_depenses_sans_ecole", "--appliquer")

        self.assertEqual(Expense.objects.filter(etablissement__isnull=True).count(), 0)
        comptes = sorted(
            Expense.objects.filter(etablissement=ecole).count()
            for ecole in self.ecoles
        )
        # Sept entre trois ecoles: 3, 2, 2. Aucune ecole n'est chargee de deux
        # lignes de plus qu'une autre.
        self.assertEqual(comptes, [2, 2, 3])

    def test_chaque_depense_recoit_l_annee_de_son_ecole(self):
        """Et non « l'annee active », qui n'existe pas au singulier.

        Chaque ecole a la sienne. C'est tout l'objet de `AcademicYear.courante(
        etablissement)`: sans portee, elle rendrait l'annee d'une ecole au
        hasard.
        """
        self._orphelines(3)

        call_command("repartir_les_depenses_sans_ecole", "--appliquer")

        for depense in Expense.objects.all():
            self.assertIsNotNone(depense.academic_year)
            self.assertEqual(
                depense.academic_year.etablissement_id, depense.etablissement_id
            )

    def test_une_depense_hors_de_l_annee_garde_son_ecole_sans_annee(self):
        """Aout n'appartient a aucune annee scolaire, et on ne triche pas.

        La depense devient visible -- elle a une ecole -- mais la ranger dans
        une annee qui ne couvre pas sa date fausserait un bilan sans jamais se
        signaler. `controler_la_dotation` continuera donc de la mentionner, ce
        qui est le comportement voulu.
        """
        self._orphelines(1, jour=date(2026, 8, 15))

        call_command("repartir_les_depenses_sans_ecole", "--appliquer")

        depense = Expense.objects.get()
        self.assertIsNotNone(depense.etablissement)
        self.assertIsNone(depense.academic_year)

    def test_une_seule_ecole_peut_tout_recevoir(self):
        """Quand la comptabilite sait, elle doit pouvoir le dire."""
        self._orphelines(4)

        call_command(
            "repartir_les_depenses_sans_ecole", "--appliquer", "--etablissement=ECB"
        )

        cible = next(ecole for ecole in self.ecoles if ecole.code == "ECB")
        self.assertEqual(Expense.objects.filter(etablissement=cible).count(), 4)

    def test_une_ecole_inconnue_ne_touche_a_rien(self):
        self._orphelines(2)

        call_command(
            "repartir_les_depenses_sans_ecole", "--appliquer", "--etablissement=ZZZ"
        )

        self.assertEqual(
            Expense.objects.filter(etablissement__isnull=True).count(), 2
        )

    def test_relancer_ne_redistribue_pas_ce_qui_est_deja_range(self):
        """L'idempotence: la commande ne travaille que sur les orphelines."""
        self._orphelines(3)
        call_command("repartir_les_depenses_sans_ecole", "--appliquer")
        avant = {
            depense.id: depense.etablissement_id for depense in Expense.objects.all()
        }

        call_command("repartir_les_depenses_sans_ecole", "--appliquer")

        apres = {
            depense.id: depense.etablissement_id for depense in Expense.objects.all()
        }
        self.assertEqual(avant, apres)
