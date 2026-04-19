from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
    TeacherTimeEntry,
)


class TeacherPayrollWorkflowApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Etab Payroll")
        self.academic_year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        self.classroom = ClassRoom.objects.create(
            name="6A",
            academic_year=self.academic_year,
            etablissement=self.etablissement,
        )
        self.subject = Subject.objects.create(
            name="Mathematiques",
            code="MAT",
            coefficient=1,
            classroom=self.classroom,
        )
        self.subject_other = Subject.objects.create(
            name="Physique",
            code="PHY",
            coefficient=1,
            classroom=self.classroom,
        )

        self.supervisor = User.objects.create_user(
            username="supervisor_payroll",
            password="Pass1234!",
            role=UserRole.SUPERVISOR,
            etablissement=self.etablissement,
        )
        self.director = User.objects.create_user(
            username="director_payroll",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.accountant = User.objects.create_user(
            username="accountant_payroll",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )
        self.teacher_user = User.objects.create_user(
            username="teacher_payroll",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
            first_name="Ada",
            last_name="Lovelace",
        )
        self.teacher = Teacher.objects.create(
            user=self.teacher_user,
            employee_code="ENS-PAY-01",
            hire_date=date(2024, 9, 1),
            hourly_rate=Decimal("1000.00"),
            etablissement=self.etablissement,
        )
        self.other_teacher_user = User.objects.create_user(
            username="teacher_other",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
            first_name="Grace",
            last_name="Hopper",
        )
        self.other_teacher = Teacher.objects.create(
            user=self.other_teacher_user,
            employee_code="ENS-PAY-02",
            hire_date=date(2024, 9, 1),
            hourly_rate=Decimal("1000.00"),
            etablissement=self.etablissement,
        )

        self.assignment = TeacherAssignment.objects.create(
            teacher=self.teacher,
            subject=self.subject,
            classroom=self.classroom,
        )
        self.assignment_other = TeacherAssignment.objects.create(
            teacher=self.other_teacher,
            subject=self.subject_other,
            classroom=self.classroom,
        )
        TeacherScheduleSlot.objects.create(
            assignment=self.assignment,
            day_of_week="MON",
            start_time="08:00",
            end_time="10:00",
        )
        TeacherScheduleSlot.objects.create(
            assignment=self.assignment_other,
            day_of_week="MON",
            start_time="10:00",
            end_time="12:00",
        )

    def _create_time_entry(self, payload):
        self.client.force_authenticate(self.supervisor)
        return self.client.post("/api/teacher-time-entries/", payload, format="json")

    def test_late_tolerance_keeps_full_paid_hours(self):
        response = self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-06",  # Monday
                "check_in_time": "08:10:00",
                "check_out_time": "10:00:00",
            }
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        row = TeacherTimeEntry.objects.get(id=response.data["id"])
        self.assertEqual(row.late_minutes, 10)
        self.assertEqual(row.tolerated_late_minutes, 10)
        self.assertEqual(row.worked_hours, Decimal("2.00"))

    def test_missing_checkout_is_auto_closed(self):
        response = self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-13",  # Monday
                "check_in_time": "08:15:00",
            }
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        row = TeacherTimeEntry.objects.get(id=response.data["id"])
        self.assertTrue(row.is_auto_closed)
        self.assertEqual(row.auto_closed_reason, "auto_close_schedule_end")
        self.assertEqual(str(row.check_out_time), "10:00:00")
        self.assertEqual(row.worked_hours, Decimal("2.00"))

    def test_pointage_sunday_is_forbidden(self):
        response = self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-12",  # Sunday
                "check_in_time": "08:10:00",
                "check_out_time": "10:00:00",
            }
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("entry_date", response.data)

    def test_pointage_without_schedule_slot_for_day_is_forbidden(self):
        response = self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-07",  # Tuesday (no slot configured)
                "check_in_time": "08:10:00",
                "check_out_time": "10:00:00",
            }
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("entry_date", response.data)

    def test_director_has_read_only_access_on_teacher_time_entries(self):
        self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-06",
                "check_in_time": "08:10:00",
                "check_out_time": "10:00:00",
            }
        )

        self.client.force_authenticate(self.director)
        list_response = self.client.get("/api/teacher-time-entries/")
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)

        create_response = self.client.post(
            "/api/teacher-time-entries/",
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-13",
                "check_in_time": "08:10:00",
                "check_out_time": "10:00:00",
            },
            format="json",
        )
        self.assertEqual(create_response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn("lecture seule", str(create_response.data.get("detail", "")).lower())

    def test_teacher_sees_only_own_time_entries_and_can_create_only_for_self(self):
        self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-06",
                "check_in_time": "08:10:00",
                "check_out_time": "10:00:00",
            }
        )
        self._create_time_entry(
            {
                "teacher": self.other_teacher.id,
                "entry_date": "2026-04-06",
                "check_in_time": "10:05:00",
                "check_out_time": "12:00:00",
            }
        )

        self.client.force_authenticate(self.teacher_user)
        list_response = self.client.get("/api/teacher-time-entries/")
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        results = list_response.data.get("results", list_response.data)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["teacher"], self.teacher.id)

        own_create_response = self.client.post(
            "/api/teacher-time-entries/",
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-13",
                "check_in_time": "08:05:00",
                "check_out_time": "10:00:00",
            },
            format="json",
        )
        self.assertEqual(own_create_response.status_code, status.HTTP_201_CREATED)

        other_create_response = self.client.post(
            "/api/teacher-time-entries/",
            {
                "teacher": self.other_teacher.id,
                "entry_date": "2026-04-13",
                "check_in_time": "10:05:00",
                "check_out_time": "12:00:00",
            },
            format="json",
        )
        self.assertEqual(other_create_response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn("propre pointage", str(other_create_response.data.get("detail", "")).lower())

    def test_salary_generation_and_two_level_validation_workflow(self):
        self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-06",
                "check_in_time": "08:10:00",
                "check_out_time": "10:00:00",
            }
        )
        self._create_time_entry(
            {
                "teacher": self.teacher.id,
                "entry_date": "2026-04-13",
                "check_in_time": "08:15:00",
            }
        )

        self.client.force_authenticate(self.supervisor)
        generate_response = self.client.post(
            "/api/teacher-payrolls/generate_monthly/",
            {"month": "2026-04", "teacher": self.teacher.id},
            format="json",
        )
        self.assertEqual(generate_response.status_code, status.HTTP_200_OK)
        self.assertEqual(generate_response.data["count"], 1)

        payroll = generate_response.data["results"][0]
        self.assertEqual(Decimal(str(payroll["hours_worked"])), Decimal("4.00"))
        self.assertEqual(Decimal(str(payroll["hourly_rate"])), Decimal("1000.00"))
        self.assertEqual(Decimal(str(payroll["amount"])), Decimal("4000.00"))

        payroll_id = payroll["id"]

        level_one_response = self.client.post(
            f"/api/teacher-payrolls/{payroll_id}/validate_level_one/",
            {},
            format="json",
        )
        self.assertEqual(level_one_response.status_code, status.HTTP_200_OK)
        self.assertEqual(level_one_response.data["validation_stage"], "level_one")

        self.client.force_authenticate(self.accountant)
        level_two_response = self.client.post(
            f"/api/teacher-payrolls/{payroll_id}/validate_level_two/",
            {},
            format="json",
        )
        self.assertEqual(level_two_response.status_code, status.HTTP_200_OK)
        self.assertEqual(level_two_response.data["validation_stage"], "level_two")

        self.client.force_authenticate(self.supervisor)
        locked_update_response = self.client.patch(
            f"/api/teacher-payrolls/{payroll_id}/",
            {"hours_worked": "5.00"},
            format="json",
        )
        self.assertEqual(locked_update_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("niveau 2", str(locked_update_response.data.get("detail", "")).lower())
