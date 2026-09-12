"""Les recettes de la periode, comptees par la base et non par la page.

L'ecran Finances additionnait les lignes qu'il avait chargees. Le journal
etant pagine par vingt-cinq, « Recettes de la periode » decrivait la page et
non la periode: au-dela de vingt-cinq versements dans le mois, le chiffre
etait faux, et il changeait en tournant la page.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import Expense, Payment
from apps.school.tests.test_finance_payments import _FinanceMixin


class TotauxDeLaPeriodeTests(_FinanceMixin, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._decor("Etab Totaux")
        cls.eleve = cls._eleve("eleve_totaux")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)

    def _totaux(self, periode="mois"):
        return self.client.get(
            "/api/payments/totaux/",
            {"periode": periode},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def _versement(self, montant, methode="Especes"):
        frais = self._frais(self.eleve, montant)
        return Payment.objects.create(
            fee=frais,
            amount=Decimal(montant),
            method=methode,
            etablissement=self.etablissement,
            received_by=self.comptable,
        )

    def test_le_total_couvre_tout_le_mois_et_pas_une_page(self):
        # Trente versements: plus que la page de vingt-cinq du journal.
        for _ in range(30):
            self._versement("1000.00")

        reponse = self._totaux()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertEqual(Decimal(reponse.data["recettes"]), Decimal("30000.00"))
        self.assertEqual(reponse.data["encaissements"], 30)

    def test_les_recettes_se_ventilent_par_methode(self):
        # C'est ce qui permet de rapprocher la caisse du releve Mobile Money.
        self._versement("5000.00", "Especes")
        self._versement("7000.00", "Especes")
        self._versement("3000.00", "Mobile Money")

        reponse = self._totaux()

        ventilation = reponse.data["recettes_par_methode"]
        self.assertEqual(Decimal(ventilation["Especes"]), Decimal("12000.00"))
        self.assertEqual(Decimal(ventilation["Mobile Money"]), Decimal("3000.00"))

    def test_un_versement_du_mois_dernier_sort_du_mois_courant(self):
        ancien = self._versement("9000.00")
        Payment.objects.filter(pk=ancien.pk).update(
            created_at=timezone.now() - timedelta(days=45)
        )
        self._versement("1000.00")

        self.assertEqual(
            Decimal(self._totaux("mois").data["recettes"]), Decimal("1000.00")
        )
        self.assertEqual(
            Decimal(self._totaux("tout").data["recettes"]), Decimal("10000.00")
        )

    def test_seules_les_depenses_validees_amputent_le_resultat(self):
        # Le circuit de validation a deux niveaux existe precisement pour
        # distinguer ce qui est engage de ce qui est seulement saisi.
        self._versement("50000.00")
        Expense.objects.create(
            label="Validee",
            amount=Decimal("10000.00"),
            date=date.today(),
            category="Fournitures",
            etablissement=self.etablissement,
            level_two_validated_at=timezone.now(),
        )
        Expense.objects.create(
            label="En attente",
            amount=Decimal("8000.00"),
            date=date.today(),
            category="Fournitures",
            etablissement=self.etablissement,
        )

        reponse = self._totaux()

        self.assertEqual(
            Decimal(reponse.data["depenses_validees"]), Decimal("10000.00")
        )
        self.assertEqual(
            Decimal(reponse.data["depenses_en_attente"]), Decimal("8000.00")
        )
        self.assertEqual(Decimal(reponse.data["resultat"]), Decimal("40000.00"))

    def test_une_periode_inconnue_est_refusee(self):
        # « None » signifie deja « depuis toujours »: une faute de frappe ne
        # doit pas passer pour une demande de tout l'historique.
        self.assertEqual(
            self._totaux("trimestre").status_code, status.HTTP_400_BAD_REQUEST
        )

    def test_la_famille_voit_ses_versements_sans_les_depenses(self):
        self._versement("4000.00")
        parent = User.objects.create_user(
            username="parent_totaux",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(parent)

        reponse = self._totaux()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertNotIn("depenses_validees", reponse.data)
        self.assertNotIn("resultat", reponse.data)
        # Aucun enfant rattache: elle ne voit donc aucun versement.
        self.assertEqual(Decimal(reponse.data["recettes"]), Decimal("0"))

    def test_l_enseignant_n_atteint_pas_les_totaux(self):
        enseignant = User.objects.create_user(
            username="ens_totaux",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(enseignant)

        self.assertEqual(self._totaux().status_code, status.HTTP_403_FORBIDDEN)
