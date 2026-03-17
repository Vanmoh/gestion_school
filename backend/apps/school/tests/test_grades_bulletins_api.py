from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Grade,
    GradeValidation,
    Level,
    ParentProfile,
    Section,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
)


class GradesAndBulletinsApiTests(APITestCase):
    def setUp(self):
        self.admin_user = User.objects.create_user(
            username="admin_grades",
            password="admin12345",
            role=UserRole.SUPER_ADMIN,
            first_name="Admin",
            last_name="Grades",
        )

        self.teacher_user = User.objects.create_user(
            username="teacher_grades",
            password="teacher12345",
            role=UserRole.TEACHER,
            first_name="Nina",
            last_name="Prof",
        )
        self.teacher = Teacher.objects.create(
            user=self.teacher_user,
            employee_code="ENS-GRADES-01",
            hire_date=date(2020, 9, 1),
            salary_base=1000,
        )

        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.level = Level.objects.create(name="5eme")
        self.section = Section.objects.create(name="A")

        self.class_a = ClassRoom.objects.create(
            name="5A",
            level=self.level,
            section=self.section,
            academic_year=self.year,
        )
        self.class_b = ClassRoom.objects.create(
            name="5B",
            level=self.level,
            section=self.section,
            academic_year=self.year,
        )

        self.subject_math = Subject.objects.create(
            name="Mathematiques",
            code="MAT-GRADES-01",
            coefficient=2,
        )
        self.subject_phy = Subject.objects.create(
            name="Physique",
            code="PHY-GRADES-01",
            coefficient=1,
        )
        TeacherAssignment.objects.create(
            teacher=self.teacher,
            subject=self.subject_math,
            classroom=self.class_a,
        )
        TeacherAssignment.objects.create(
            teacher=self.teacher,
            subject=self.subject_phy,
            classroom=self.class_a,
        )

        self.parent_user_1 = User.objects.create_user(
            username="parent_grade_1",
            password="parent12345",
            role=UserRole.PARENT,
            first_name="Parent",
            last_name="One",
        )
        self.parent_1 = ParentProfile.objects.create(user=self.parent_user_1)

        self.parent_user_2 = User.objects.create_user(
            username="parent_grade_2",
            password="parent12345",
            role=UserRole.PARENT,
            first_name="Parent",
            last_name="Two",
        )
        self.parent_2 = ParentProfile.objects.create(user=self.parent_user_2)

        self.student_user_1 = User.objects.create_user(
            username="student_grade_1",
            password="student12345",
            role=UserRole.STUDENT,
            first_name="Student",
            last_name="One",
        )
        self.student_1 = Student.objects.create(
            user=self.student_user_1,
            classroom=self.class_a,
            parent=self.parent_1,
        )

        self.student_user_2 = User.objects.create_user(
            username="student_grade_2",
            password="student12345",
            role=UserRole.STUDENT,
            first_name="Student",
            last_name="Two",
        )
        self.student_2 = Student.objects.create(
            user=self.student_user_2,
            classroom=self.class_a,
            parent=self.parent_2,
        )

        self.grade_1 = Grade.objects.create(
            student=self.student_1,
            subject=self.subject_math,
            classroom=self.class_a,
            academic_year=self.year,
            term="T1",
            value=12,
        )
        self.grade_2 = Grade.objects.create(
            student=self.student_2,
            subject=self.subject_math,
            classroom=self.class_a,
            academic_year=self.year,
            term="T1",
            value=14,
        )

    def _results(self, response):
        data = response.data
        if isinstance(data, dict) and "results" in data:
            return data["results"]
        return data

    def test_parent_list_is_scoped_to_children_only(self):
        self.client.force_authenticate(self.parent_user_1)

        response = self.client.get("/api/grades/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = self._results(response)
        student_ids = {_row["student"] for _row in results}
        self.assertEqual(student_ids, {self.student_1.id})

    def test_student_list_is_scoped_to_self_only(self):
        self.client.force_authenticate(self.student_user_1)

        response = self.client.get("/api/grades/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = self._results(response)
        student_ids = {_row["student"] for _row in results}
        self.assertEqual(student_ids, {self.student_1.id})

    def test_create_grade_normalizes_term_and_rejects_out_of_range_value(self):
        self.client.force_authenticate(self.admin_user)

        valid_response = self.client.post(
            "/api/grades/",
            {
                "student": self.student_1.id,
                "subject": self.subject_phy.id,
                "classroom": self.class_a.id,
                "academic_year": self.year.id,
                "term": "1",
                "value": 15,
            },
            format="json",
        )
        self.assertEqual(valid_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(valid_response.data["term"], "T1")

        invalid_response = self.client.post(
            "/api/grades/",
            {
                "student": self.student_1.id,
                "subject": self.subject_phy.id,
                "classroom": self.class_a.id,
                "academic_year": self.year.id,
                "term": "T2",
                "value": 25,
            },
            format="json",
        )
        self.assertEqual(invalid_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("value", invalid_response.data)

    def test_create_grade_rejects_student_classroom_mismatch(self):
        self.client.force_authenticate(self.admin_user)

        response = self.client.post(
            "/api/grades/",
            {
                "student": self.student_1.id,
                "subject": self.subject_phy.id,
                "classroom": self.class_b.id,
                "academic_year": self.year.id,
                "term": "T2",
                "value": 13,
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("student", response.data)

    def test_update_grade_blocks_immutable_field_changes(self):
        self.client.force_authenticate(self.admin_user)

        response = self.client.patch(
            f"/api/grades/{self.grade_1.id}/",
            {"subject": self.subject_phy.id, "value": 16},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("fields", response.data)
        self.assertIn("subject", response.data["fields"])

    def test_locked_term_blocks_update_even_with_term_switch_attempt(self):
        self.client.force_authenticate(self.admin_user)
        GradeValidation.objects.create(
            classroom=self.class_a,
            academic_year=self.year,
            term="T1",
            is_validated=True,
            validated_by=self.admin_user,
        )

        response = self.client.patch(
            f"/api/grades/{self.grade_1.id}/",
            {"term": "T2", "value": 19},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("validée", str(response.data.get("detail", "")))

    def test_validation_status_and_recalculate_reject_invalid_inputs(self):
        self.client.force_authenticate(self.admin_user)

        status_response = self.client.get(
            "/api/grades/validation_status/",
            {"classroom": "abc", "academic_year": self.year.id, "term": "T1"},
        )
        self.assertEqual(status_response.status_code, status.HTTP_400_BAD_REQUEST)

        recalc_response = self.client.post(
            "/api/grades/recalculate_ranking/",
            {"classroom": "x", "academic_year": self.year.id, "term": "T1"},
            format="json",
        )
        self.assertEqual(recalc_response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_exam_session_requires_and_normalizes_term(self):
        self.client.force_authenticate(self.admin_user)

        response = self.client.post(
            "/api/exam-sessions/",
            {
                "title": "Examen trim 1",
                "term": "1",
                "academic_year": self.year.id,
                "start_date": "2026-01-10",
                "end_date": "2026-01-20",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["term"], "T1")

    def test_bulletin_rejects_invalid_term(self):
        self.client.force_authenticate(self.admin_user)

        response = self.client.get(
            f"/api/reports/bulletin/{self.student_1.id}/{self.year.id}/SEM1/"
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Période invalide", str(response.data.get("detail", "")))
