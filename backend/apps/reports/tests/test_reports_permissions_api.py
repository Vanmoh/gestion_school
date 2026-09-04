from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import Etablissement


class ReportsPermissionsApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etab Reports",
            address="Adresse",
            phone="770000001",
            email="reports@example.com",
        )

        self.teacher = User.objects.create_user(
            username="teacher_reports",
            password="pass12345",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.accountant = User.objects.create_user(
            username="accountant_reports",
            password="pass12345",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )

    def test_l_enseignant_entre_dans_les_rapports(self):
        """La matrice lui accorde « rapports » en lecture: il doit entrer.

        Une liste de roles ecrite dans la vue le refusait, alors que son
        entree de menu s'affichait: l'ecran s'ouvrait sur une erreur.
        """
        self.client.force_authenticate(self.teacher)
        response = self.client.get("/api/reports/context/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_l_enseignant_n_y_voit_ni_eleve_hors_classe_ni_paiement(self):
        """Entrer n'est pas tout voir: l'etoile de la matrice s'applique.

        Cet enseignant n'a aucune affectation, donc aucun eleve; et les
        finances lui sont fermees, donc aucun paiement -- meme si le meme
        ecran les sert au comptable.
        """
        self.client.force_authenticate(self.teacher)
        response = self.client.get("/api/reports/context/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["students"], [])
        self.assertEqual(response.data["payments"], [])

    def test_teacher_cannot_export_payments_excel(self):
        self.client.force_authenticate(self.teacher)
        response = self.client.get("/api/reports/payments/export-excel/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_teacher_cannot_access_finance_journal_endpoints(self):
        self.client.force_authenticate(self.teacher)

        payments_page = self.client.get("/api/reports/journal/payments/")
        self.assertEqual(payments_page.status_code, status.HTTP_403_FORBIDDEN)

        payments_export = self.client.get("/api/reports/journal-payments/export/?export_format=csv")
        self.assertEqual(payments_export.status_code, status.HTTP_403_FORBIDDEN)

        expenses_page = self.client.get("/api/reports/journal/expenses/")
        self.assertEqual(expenses_page.status_code, status.HTTP_403_FORBIDDEN)

        expenses_export = self.client.get("/api/reports/journal-expenses/export/?export_format=pdf")
        self.assertEqual(expenses_export.status_code, status.HTTP_403_FORBIDDEN)

    def test_accountant_can_export_payments_excel(self):
        self.client.force_authenticate(self.accountant)
        response = self.client.get("/api/reports/payments/export-excel/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_accountant_can_access_finance_journal_endpoints(self):
        self.client.force_authenticate(self.accountant)

        payments_page = self.client.get("/api/reports/journal/payments/?page=1&page_size=50")
        self.assertEqual(payments_page.status_code, status.HTTP_200_OK)
        self.assertIn("results", payments_page.data)

        payments_export = self.client.get("/api/reports/journal-payments/export/?export_format=csv")
        self.assertEqual(payments_export.status_code, status.HTTP_200_OK)

        expenses_page = self.client.get("/api/reports/journal/expenses/?page=1&page_size=50")
        self.assertEqual(expenses_page.status_code, status.HTTP_200_OK)
        self.assertIn("results", expenses_page.data)

        expenses_export = self.client.get("/api/reports/journal-expenses/export/?export_format=pdf")
        self.assertEqual(expenses_export.status_code, status.HTTP_200_OK)
