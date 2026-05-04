from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Subject, Teacher, TeacherAssignment


class RoleGuardrailsApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etab Guardrails",
            address="Kalaban",
            phone="770011223",
            email="guardrails@example.com",
        )

        self.super_admin = User.objects.create_user(
            username="sa_guard",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
        )
        self.director = User.objects.create_user(
            username="director_guard",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.promoter = User.objects.create_user(
            username="promoter_guard",
            password="Pass1234!",
            role=UserRole.PROMOTER,
            etablissement=self.etablissement,
        )
        self.censor = User.objects.create_user(
            username="censor_guard",
            password="Pass1234!",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )
        self.supervisor = User.objects.create_user(
            username="supervisor_guard",
            password="Pass1234!",
            role=UserRole.SUPERVISOR,
            etablissement=self.etablissement,
        )

        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        self.classroom = ClassRoom.objects.create(
            name="5e A",
            academic_year=self.year,
            etablissement=self.etablissement,
        )
        self.subject = Subject.objects.create(
            name="Mathematiques",
            code="MATH-GUARD",
            coefficient=1,
            classroom=self.classroom,
        )
        teacher_user = User.objects.create_user(
            username="teacher_guard",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        teacher = Teacher.objects.create(
            user=teacher_user,
            employee_code="ENS-GUARD-01",
            hire_date=date(2024, 9, 1),
            salary_base=150000,
            etablissement=self.etablissement,
        )
        self.assignment = TeacherAssignment.objects.create(
            teacher=teacher,
            subject=self.subject,
            classroom=self.classroom,
        )

    def _expense_payload(self):
        return {
            "label": "Fournitures",
            "amount": "20000",
            "date": str(date.today()),
            "category": "fournitures",
            "notes": "Test guardrails roles",
        }

    def _schedule_slot_payload(self):
        return {
            "assignment": self.assignment.id,
            "day_of_week": "MON",
            "start_time": "08:00",
            "end_time": "10:00",
            "room": "A1",
        }

    def _announcement_payload(self):
        return {
            "title": "Info discipline",
            "message": "Point de coordination hebdomadaire",
            "audience": "all",
        }

    def test_supervisor_is_blocked_from_transferred_modules(self):
        self.client.force_authenticate(self.supervisor)

        timetable_create = self.client.post(
            "/api/teacher-schedule-slots/",
            self._schedule_slot_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(timetable_create.status_code, status.HTTP_403_FORBIDDEN)

        expense_create = self.client.post(
            "/api/expenses/",
            self._expense_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(expense_create.status_code, status.HTTP_403_FORBIDDEN)

        announcement_create = self.client.post(
            "/api/announcements/",
            self._announcement_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(announcement_create.status_code, status.HTTP_403_FORBIDDEN)

    def test_censor_can_access_transferred_operational_modules(self):
        self.client.force_authenticate(self.censor)

        timetable_create = self.client.post(
            "/api/teacher-schedule-slots/",
            self._schedule_slot_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(timetable_create.status_code, status.HTTP_201_CREATED)

        announcement_create = self.client.post(
            "/api/announcements/",
            self._announcement_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(announcement_create.status_code, status.HTTP_201_CREATED)

    def test_promoter_matches_direction_for_finance_writes(self):
        self.client.force_authenticate(self.director)
        director_expense = self.client.post(
            "/api/expenses/",
            self._expense_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(director_expense.status_code, status.HTTP_201_CREATED)

        self.client.force_authenticate(self.promoter)
        promoter_expense = self.client.post(
            "/api/expenses/",
            self._expense_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(promoter_expense.status_code, status.HTTP_201_CREATED)

    def test_promoter_cannot_validate_level_one_expense(self):
        self.client.force_authenticate(self.super_admin)
        created = self.client.post(
            "/api/expenses/",
            self._expense_payload(),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(created.status_code, status.HTTP_201_CREATED)
        expense_id = int(created.data["id"])

        self.client.force_authenticate(self.promoter)
        level_one = self.client.post(
            f"/api/expenses/{expense_id}/validate_level_one/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(level_one.status_code, status.HTTP_400_BAD_REQUEST)
