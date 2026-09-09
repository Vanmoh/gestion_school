"""Le rapport financier annuel, mois par mois.

L'écran d'accueil traçait une courbe fabriquée: trois points obtenus en
multipliant le montant du mois courant par des coefficients écrits en dur,
étiquetés « S-3, S-2, S-1 ». La direction lisait une tendance qui n'existait
pas — et le cahier des charges demandait un rapport annuel, avec graphiques.
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
    Expense,
    FeeType,
    Payment,
    Student,
    StudentFee,
)


class FinancesAnnuellesTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Annuel")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")
        # L'année couvre le mois courant: les paiements sont horodatés par
        # `created_at`, que le test ne peut pas antidater simplement.
        aujourd_hui = timezone.now().date()
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(aujourd_hui.year, 1, 1),
            end_date=date(aujourd_hui.year, 12, 31),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.classe = ClassRoom.objects.create(
            name="6A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.directeur = User.objects.create_user(
            username="directeur_annuel",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_annuel",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.eleve = Student.objects.create(
            user=eleve_user,
            matricule="A001",
            classroom=self.classe,
            etablissement=self.etablissement,
        )
        self.frais = StudentFee.objects.create(
            student=self.eleve,
            academic_year=self.annee,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("200000"),
            due_date=date(aujourd_hui.year, 6, 5),
        )
        self.client.force_authenticate(self.directeur)

    def _appeler(self):
        reponse = self.client.get("/api/dashboard/finances-annuelles/")
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        return reponse.data

    def _paiement(self, montant, etablissement=None):
        return Payment.objects.create(
            fee=self.frais,
            etablissement=etablissement or self.etablissement,
            amount=Decimal(montant),
            method="Especes",
        )

    def _depense(self, montant, quand=None, validee=True):
        depense = Expense.objects.create(
            label="Charges",
            amount=Decimal(montant),
            date=quand or timezone.now().date(),
            category="Fournitures",
            etablissement=self.etablissement,
        )
        if validee:
            depense.level_one_validated_at = timezone.now()
            depense.level_two_validated_at = timezone.now()
            depense.save()
        return depense

    def test_la_serie_couvre_tous_les_mois_de_l_annee(self):
        """Un trou dans la série se lirait comme une baisse, pas un vide."""
        donnees = self._appeler()

        self.assertEqual(len(donnees["mois"]), 12)
        self.assertEqual(donnees["mois"][0]["libelle"][:2], "01")
        self.assertEqual(donnees["mois"][-1]["libelle"][:2], "12")

    def test_un_mois_sans_mouvement_vaut_zero(self):
        donnees = self._appeler()

        self.assertTrue(
            all(Decimal(str(mois["recettes"])) == 0 for mois in donnees["mois"])
        )

    def test_un_encaissement_apparait_sur_son_mois(self):
        self._paiement("150000")
        mois_courant = timezone.now().date().month

        donnees = self._appeler()
        ligne = donnees["mois"][mois_courant - 1]

        self.assertEqual(Decimal(str(ligne["recettes"])), Decimal("150000"))
        self.assertEqual(Decimal(str(donnees["total_recettes"])), Decimal("150000"))

    def test_le_benefice_annuel_retranche_les_depenses(self):
        self._paiement("150000")
        self._depense("40000")

        donnees = self._appeler()

        self.assertEqual(Decimal(str(donnees["total_depenses"])), Decimal("40000"))
        self.assertEqual(Decimal(str(donnees["benefice"])), Decimal("110000"))

    def test_une_depense_non_validee_ne_compte_pas(self):
        """Même règle que le bénéfice mensuel: un brouillon n'est pas une charge."""
        self._paiement("150000")
        self._depense("40000", validee=False)

        donnees = self._appeler()

        self.assertEqual(Decimal(str(donnees["total_depenses"])), Decimal("0"))
        self.assertEqual(Decimal(str(donnees["benefice"])), Decimal("150000"))

    def test_un_paiement_annule_ne_compte_pas(self):
        paiement = self._paiement("150000")
        paiement.is_cancelled = True
        paiement.save()

        donnees = self._appeler()

        self.assertEqual(Decimal(str(donnees["total_recettes"])), Decimal("0"))

    def test_les_chiffres_d_un_autre_etablissement_restent_dehors(self):
        autre_annee = AcademicYear.objects.create(
            name="2025-2026 voisin",
            start_date=self.annee.start_date,
            end_date=self.annee.end_date,
            etablissement=self.autre,
        )
        autre_classe = ClassRoom.objects.create(
            name="6A voisin", academic_year=autre_annee, etablissement=self.autre
        )
        user = User.objects.create_user(
            username="eleve_voisin_annuel",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.autre,
        )
        eleve = Student.objects.create(
            user=user,
            matricule="V001",
            classroom=autre_classe,
            etablissement=self.autre,
        )
        frais = StudentFee.objects.create(
            student=eleve,
            academic_year=autre_annee,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("50000"),
            due_date=date(self.annee.start_date.year, 6, 5),
        )
        Payment.objects.create(
            fee=frais,
            etablissement=self.autre,
            amount=Decimal("50000"),
            method="Especes",
        )
        self._paiement("150000")

        donnees = self._appeler()

        self.assertEqual(Decimal(str(donnees["total_recettes"])), Decimal("150000"))

    def test_l_annee_visee_se_choisit(self):
        ancienne = AcademicYear.objects.create(
            name="2024-2025",
            start_date=date(self.annee.start_date.year - 1, 1, 1),
            end_date=date(self.annee.start_date.year - 1, 12, 31),
            etablissement=self.etablissement,
        )

        reponse = self.client.get(
            f"/api/dashboard/finances-annuelles/?academic_year={ancienne.id}"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["academic_year"], ancienne.id)
        self.assertEqual(Decimal(str(reponse.data["total_recettes"])), Decimal("0"))

    def test_sans_annee_active_la_reponse_reste_lisible(self):
        self.annee.is_active = False
        self.annee.save(update_fields=["is_active"])

        reponse = self.client.get("/api/dashboard/finances-annuelles/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["mois"], [])
        self.assertIn("Aucune année", reponse.data["detail"])
