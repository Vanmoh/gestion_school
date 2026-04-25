from datetime import date, timedelta

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import Etablissement, Expense


class ExpenseWorkflowApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etab Finance",
            address="Centre",
            phone="770000111",
            email="finance@example.com",
        )

        self.super_admin = User.objects.create_user(
            username="sa_expense",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
        )
        self.supervisor = User.objects.create_user(
            username="sup_expense",
            password="Pass1234!",
            role=UserRole.SUPERVISOR,
            etablissement=self.etablissement,
        )
        self.accountant = User.objects.create_user(
            username="acc_expense",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )

    def _create_expense(self):
        self.client.force_authenticate(self.super_admin)
        response = self.client.post(
            "/api/expenses/",
            {
                "label": "Internet",
                "amount": "45000",
                "date": str(date.today() - timedelta(days=1)),
                "category": "internet",
                "notes": "Facture mensuelle",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        return int(response.data["id"])

    def test_expense_two_level_validation_workflow_and_lock(self):
        expense_id = self._create_expense()

        self.client.force_authenticate(self.supervisor)
        level_one = self.client.post(
            f"/api/expenses/{expense_id}/validate_level_one/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(level_one.status_code, status.HTTP_200_OK)
        self.assertEqual(level_one.data.get("validation_stage"), "level_one")

        self.client.force_authenticate(self.accountant)
        level_two = self.client.post(
            f"/api/expenses/{expense_id}/validate_level_two/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(level_two.status_code, status.HTTP_200_OK)
        self.assertEqual(level_two.data.get("validation_stage"), "level_two")

        lock_patch = self.client.patch(
            f"/api/expenses/{expense_id}/",
            {"amount": "35000"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(lock_patch.status_code, status.HTTP_400_BAD_REQUEST)

        lock_delete = self.client.delete(
            f"/api/expenses/{expense_id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(lock_delete.status_code, status.HTTP_400_BAD_REQUEST)

        expense = Expense.objects.get(id=expense_id)
        self.assertIsNotNone(expense.paid_by)
        self.assertIsNotNone(expense.paid_on)
        self.assertEqual(expense.validation_stage, "level_two")

    def test_expense_validation_roles_and_reset(self):
        expense_id = self._create_expense()

        self.client.force_authenticate(self.accountant)
        invalid_level_one = self.client.post(
            f"/api/expenses/{expense_id}/validate_level_one/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(invalid_level_one.status_code, status.HTTP_400_BAD_REQUEST)

        self.client.force_authenticate(self.supervisor)
        invalid_level_two = self.client.post(
            f"/api/expenses/{expense_id}/validate_level_two/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(invalid_level_two.status_code, status.HTTP_400_BAD_REQUEST)

        level_one = self.client.post(
            f"/api/expenses/{expense_id}/validate_level_one/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(level_one.status_code, status.HTTP_200_OK)

        self.client.force_authenticate(self.super_admin)
        reset = self.client.post(
            f"/api/expenses/{expense_id}/reset_validation/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(reset.status_code, status.HTTP_200_OK)
        self.assertEqual(reset.data.get("validation_stage"), "draft")

        expense = Expense.objects.get(id=expense_id)
        self.assertIsNone(expense.level_one_validated_at)
        self.assertIsNone(expense.level_two_validated_at)
        self.assertIsNone(expense.paid_on)
