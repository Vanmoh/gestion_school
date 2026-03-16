from datetime import date, time

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Level,
    Section,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
    TimetablePublication,
)


class TeacherScheduleSlotApiTests(APITestCase):
    def setUp(self):
        self.admin_user = User.objects.create_user(
            username="admin_timetable",
            password="admin12345",
            role=UserRole.SUPER_ADMIN,
            first_name="Admin",
            last_name="Timetable",
        )
        self.client.force_authenticate(self.admin_user)

        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.level = Level.objects.create(name="6eme")
        self.section = Section.objects.create(name="A")

        self.class_a = ClassRoom.objects.create(
            name="6A",
            level=self.level,
            section=self.section,
            academic_year=self.year,
        )
        self.class_b = ClassRoom.objects.create(
            name="6B",
            level=self.level,
            section=self.section,
            academic_year=self.year,
        )

        teacher_user_1 = User.objects.create_user(
            username="teacher_one",
            password="teacher12345",
            role=UserRole.TEACHER,
            first_name="Alice",
            last_name="Doe",
        )
        teacher_user_2 = User.objects.create_user(
            username="teacher_two",
            password="teacher12345",
            role=UserRole.TEACHER,
            first_name="Bob",
            last_name="Roe",
        )

        self.teacher_1 = Teacher.objects.create(
            user=teacher_user_1,
            employee_code="ENS-001",
            hire_date=date(2020, 1, 10),
            salary_base=1000,
        )
        self.teacher_2 = Teacher.objects.create(
            user=teacher_user_2,
            employee_code="ENS-002",
            hire_date=date(2021, 2, 12),
            salary_base=1000,
        )

        self.subject_math = Subject.objects.create(name="Mathematiques", code="MAT-01", coefficient=1)
        self.subject_phy = Subject.objects.create(name="Physique", code="PHY-01", coefficient=1)

        self.assignment_a_math = TeacherAssignment.objects.create(
            teacher=self.teacher_1,
            subject=self.subject_math,
            classroom=self.class_a,
        )
        self.assignment_a_phy = TeacherAssignment.objects.create(
            teacher=self.teacher_2,
            subject=self.subject_phy,
            classroom=self.class_a,
        )
        self.assignment_b_math = TeacherAssignment.objects.create(
            teacher=self.teacher_1,
            subject=self.subject_math,
            classroom=self.class_b,
        )
        self.assignment_b_phy = TeacherAssignment.objects.create(
            teacher=self.teacher_1,
            subject=self.subject_phy,
            classroom=self.class_b,
        )

    def _create_slot(self, assignment, day_of_week, start_time, end_time, room=""):
        return TeacherScheduleSlot.objects.create(
            assignment=assignment,
            day_of_week=day_of_week,
            start_time=start_time,
            end_time=end_time,
            room=room,
        )

    def test_create_slot_rejects_teacher_overlap_conflict(self):
        self._create_slot(self.assignment_a_math, "MON", time(8, 0), time(10, 0), room="A1")

        response = self.client.post(
            "/api/teacher-schedule-slots/",
            {
                "assignment": self.assignment_b_math.id,
                "day_of_week": "MON",
                "start_time": "09:00",
                "end_time": "11:00",
                "room": "B2",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        errors = " ".join(response.data.get("non_field_errors", []))
        self.assertIn("Conflit enseignant", errors)

    def test_locked_classroom_blocks_create_and_delete(self):
        TimetablePublication.objects.create(
            classroom=self.class_a,
            is_published=True,
            is_locked=True,
            published_by=self.admin_user,
            published_at=timezone.now(),
        )

        create_response = self.client.post(
            "/api/teacher-schedule-slots/",
            {
                "assignment": self.assignment_a_math.id,
                "day_of_week": "MON",
                "start_time": "08:00",
                "end_time": "10:00",
                "room": "A1",
            },
            format="json",
        )

        self.assertEqual(create_response.status_code, status.HTTP_400_BAD_REQUEST)
        create_errors = " ".join(create_response.data.get("non_field_errors", []))
        self.assertIn("verrouill", create_errors.lower())

        existing_slot = self._create_slot(
            self.assignment_a_math,
            "TUE",
            time(10, 0),
            time(12, 0),
            room="A2",
        )

        delete_response = self.client.delete(f"/api/teacher-schedule-slots/{existing_slot.id}/")
        self.assertEqual(delete_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("verrouill", str(delete_response.data.get("detail", "")).lower())

    def test_teacher_workload_returns_aggregated_metrics(self):
        self._create_slot(self.assignment_a_math, "MON", time(8, 0), time(10, 0), room="A1")
        self._create_slot(self.assignment_a_phy, "TUE", time(10, 0), time(12, 0), room="A2")
        self._create_slot(self.assignment_b_math, "WED", time(8, 0), time(10, 0), room="B1")

        response = self.client.get(
            "/api/teacher-schedule-slots/teacher_workload/",
            {"classroom": self.class_a.id},
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["teacher_count"], 2)
        self.assertEqual(response.data["total_minutes"], 240)

        items_by_code = {item["teacher_code"]: item for item in response.data["items"]}
        self.assertEqual(items_by_code["ENS-001"]["total_minutes"], 120)
        self.assertEqual(items_by_code["ENS-001"]["per_day_minutes"]["MON"], 120)
        self.assertEqual(items_by_code["ENS-002"]["total_minutes"], 120)

    def test_duplicate_schedule_handles_conflict_and_subject_fallback(self):
        self._create_slot(self.assignment_a_math, "MON", time(8, 0), time(10, 0), room="A1")
        self._create_slot(self.assignment_a_phy, "TUE", time(10, 0), time(12, 0), room="A2")

        self._create_slot(self.assignment_b_math, "MON", time(8, 30), time(9, 30), room="B1")

        response = self.client.post(
            "/api/teacher-schedule-slots/duplicate_schedule/",
            {
                "source_classroom": self.class_a.id,
                "target_classroom": self.class_b.id,
                "days": ["MON", "TUE"],
                "overwrite": False,
                "keep_room": False,
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["skipped_conflicts"], 1)
        self.assertEqual(response.data["created"], 1)

        modes = {entry["mode"] for entry in response.data["mapping_examples"]}
        self.assertIn("subject-fallback", modes)

        copied_exists = TeacherScheduleSlot.objects.filter(
            assignment=self.assignment_b_phy,
            day_of_week="TUE",
            start_time=time(10, 0),
            end_time=time(12, 0),
            room="",
        ).exists()
        self.assertTrue(copied_exists)

    def test_export_excel_and_pdf_return_binary_files(self):
        self._create_slot(self.assignment_a_math, "MON", time(8, 0), time(10, 0), room="A1")

        excel_response = self.client.get(
            "/api/teacher-schedule-slots/export_excel/",
            {"classroom": self.class_a.id},
        )
        self.assertEqual(excel_response.status_code, status.HTTP_200_OK)
        self.assertIn(
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            excel_response["Content-Type"],
        )
        self.assertIn(".xlsx", excel_response["Content-Disposition"])
        self.assertGreater(len(excel_response.content), 100)

        pdf_response = self.client.get(
            "/api/teacher-schedule-slots/export_pdf/",
            {"classroom": self.class_a.id},
        )
        self.assertEqual(pdf_response.status_code, status.HTTP_200_OK)
        self.assertEqual(pdf_response["Content-Type"], "application/pdf")
        self.assertIn(".pdf", pdf_response["Content-Disposition"])
        self.assertTrue(pdf_response.content.startswith(b"%PDF"))
