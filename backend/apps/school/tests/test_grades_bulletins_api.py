from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.views import _build_bulletin_rows
from apps.school.models import (
    AcademicYear,
    Attendance,
    ClassRoom,
    DisciplineIncident,
    Etablissement,
    Grade,
    GradeValidation,
    ParentProfile,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
)


class GradesAndBulletinsApiTests(APITestCase):
    def setUp(self):
        self.etablissement_main = Etablissement.objects.create(
            name="LTOB",
            address="Centre-ville",
            phone="770000001",
            email="ltob@example.com",
        )
        self.etablissement_other = Etablissement.objects.create(
            name="LOBK",
            address="Quartier Nord",
            phone="770000002",
            email="lobk@example.com",
        )

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
            etablissement=self.etablissement_main,
        )
        self.teacher = Teacher.objects.create(
            user=self.teacher_user,
            employee_code="ENS-GRADES-01",
            hire_date=date(2020, 9, 1),
            salary_base=1000,
            etablissement=self.etablissement_main,
        )

        self.teacher_user_2 = User.objects.create_user(
            username="teacher_grades_2",
            password="teacher12345",
            role=UserRole.TEACHER,
            first_name="Emma",
            last_name="Dup",
            etablissement=self.etablissement_main,
        )
        self.teacher_2 = Teacher.objects.create(
            user=self.teacher_user_2,
            employee_code="ENS-GRADES-02",
            hire_date=date(2021, 9, 1),
            salary_base=1200,
            etablissement=self.etablissement_main,
        )

        self.supervisor_user = User.objects.create_user(
            username="supervisor_grades",
            password="supervisor12345",
            role=UserRole.SUPERVISOR,
            first_name="Surveillant",
            last_name="Principal",
            etablissement=self.etablissement_main,
        )

        self.supervisor_other_user = User.objects.create_user(
            username="supervisor_other",
            password="supervisor12345",
            role=UserRole.SUPERVISOR,
            first_name="Surv",
            last_name="Other",
            etablissement=self.etablissement_other,
        )

        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.class_a = ClassRoom.objects.create(
            name="5A",
            academic_year=self.year,
            etablissement=self.etablissement_main,
        )
        self.class_b = ClassRoom.objects.create(
            name="5B",
            academic_year=self.year,
            etablissement=self.etablissement_main,
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
        TeacherAssignment.objects.create(
            teacher=self.teacher_2,
            subject=self.subject_math,
            classroom=self.class_b,
        )

        self.parent_user_1 = User.objects.create_user(
            username="parent_grade_1",
            password="parent12345",
            role=UserRole.PARENT,
            first_name="Parent",
            last_name="One",
            etablissement=self.etablissement_main,
        )
        self.parent_1 = ParentProfile.objects.create(
            user=self.parent_user_1,
            etablissement=self.etablissement_main,
        )

        self.parent_user_2 = User.objects.create_user(
            username="parent_grade_2",
            password="parent12345",
            role=UserRole.PARENT,
            first_name="Parent",
            last_name="Two",
            etablissement=self.etablissement_main,
        )
        self.parent_2 = ParentProfile.objects.create(
            user=self.parent_user_2,
            etablissement=self.etablissement_main,
        )

        self.student_user_1 = User.objects.create_user(
            username="student_grade_1",
            password="student12345",
            role=UserRole.STUDENT,
            first_name="Student",
            last_name="One",
            etablissement=self.etablissement_main,
        )
        self.student_1 = Student.objects.create(
            user=self.student_user_1,
            classroom=self.class_a,
            parent=self.parent_1,
            etablissement=self.etablissement_main,
        )

        self.student_user_2 = User.objects.create_user(
            username="student_grade_2",
            password="student12345",
            role=UserRole.STUDENT,
            first_name="Student",
            last_name="Two",
            etablissement=self.etablissement_main,
        )
        self.student_2 = Student.objects.create(
            user=self.student_user_2,
            classroom=self.class_a,
            parent=self.parent_2,
            etablissement=self.etablissement_main,
        )
        self.student_user_3 = User.objects.create_user(
            username="student_grade_3",
            password="student12345",
            role=UserRole.STUDENT,
            first_name="Student",
            last_name="Three",
            etablissement=self.etablissement_main,
        )
        self.student_3 = Student.objects.create(
            user=self.student_user_3,
            classroom=self.class_b,
            parent=self.parent_2,
            etablissement=self.etablissement_main,
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
        self.grade_3 = Grade.objects.create(
            student=self.student_3,
            subject=self.subject_math,
            classroom=self.class_b,
            academic_year=self.year,
            term="T1",
            value=11,
        )

    def test_student_conduite_defaults_to_18(self):
        self.assertEqual(float(self.student_1.conduite), 18.0)

    def test_teacher_cannot_modify_conduite_in_attendance(self):
        self.client.force_authenticate(self.teacher_user)

        response = self.client.post(
            "/api/attendances/",
            {
                "student": self.student_1.id,
                "date": "2026-01-10",
                "is_absent": True,
                "is_late": False,
                "reason": "Test conduite",
                "conduite": "16",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("conduite", response.data)

        self.student_1.refresh_from_db()
        self.assertEqual(str(self.student_1.conduite), "18.00")
        self.assertEqual(Attendance.objects.count(), 0)

    def test_supervisor_can_modify_conduite_in_attendance(self):
        self.client.force_authenticate(self.supervisor_user)

        response = self.client.post(
            "/api/attendances/",
            {
                "student": self.student_1.id,
                "date": "2026-01-11",
                "is_absent": False,
                "is_late": True,
                "reason": "Mise a jour conduite",
                "conduite": "15.5",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data.get("conduite"), "15.50")

        self.student_1.refresh_from_db()
        self.assertEqual(str(self.student_1.conduite), "15.50")

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

    def test_teacher_attendance_is_scoped_to_assigned_classes_only(self):
        Attendance.objects.create(
            student=self.student_1,
            date=date(2026, 1, 15),
            is_absent=True,
            is_late=False,
            reason="Classe A",
        )
        Attendance.objects.create(
            student=self.student_3,
            date=date(2026, 1, 15),
            is_absent=False,
            is_late=True,
            reason="Classe B",
        )

        self.client.force_authenticate(self.teacher_user)
        response = self.client.get("/api/attendances/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = self._results(response)
        student_ids = {_row["student"] for _row in results}
        self.assertEqual(student_ids, {self.student_1.id})

    def test_teacher_cannot_create_attendance_for_unassigned_class(self):
        self.client.force_authenticate(self.teacher_user)

        response = self.client.post(
            "/api/attendances/",
            {
                "student": self.student_3.id,
                "date": "2026-01-16",
                "is_absent": True,
                "is_late": False,
                "reason": "Hors périmètre",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("student", response.data)

    def test_teacher_grades_are_scoped_to_assigned_pairs_only(self):
        self.client.force_authenticate(self.teacher_user)

        response = self.client.get("/api/grades/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        results = self._results(response)
        grade_ids = {_row["id"] for _row in results}
        self.assertEqual(grade_ids, {self.grade_1.id, self.grade_2.id})

    def test_teacher_cannot_create_grade_for_unassigned_classroom_subject_pair(self):
        self.client.force_authenticate(self.teacher_user)

        response = self.client.post(
            "/api/grades/",
            {
                "student": self.student_3.id,
                "subject": self.subject_math.id,
                "classroom": self.class_b.id,
                "academic_year": self.year.id,
                "term": "T1",
                "value": 13,
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("subject", response.data)

    def test_teacher_discipline_is_scoped_and_reporting_only(self):
        incident_a = DisciplineIncident.objects.create(
            student=self.student_1,
            incident_date=date(2026, 1, 17),
            category="Indiscipline",
            description="Incident A",
            reported_by=self.supervisor_user,
        )
        DisciplineIncident.objects.create(
            student=self.student_3,
            incident_date=date(2026, 1, 17),
            category="Indiscipline",
            description="Incident B",
            reported_by=self.supervisor_user,
            sanction="Mesure",
            status="resolved",
        )

        self.client.force_authenticate(self.teacher_user)
        list_response = self.client.get("/api/discipline-incidents/")
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        results = self._results(list_response)
        incident_ids = {_row["id"] for _row in results}
        self.assertEqual(incident_ids, {incident_a.id})

        create_response = self.client.post(
            "/api/discipline-incidents/",
            {
                "student": self.student_1.id,
                "incident_date": "2026-01-18",
                "category": "Indiscipline",
                "description": "Signalement enseignant",
                "severity": "high",
                "sanction": "Ne doit pas être gardée",
                "status": "resolved",
                "parent_notified": True,
            },
            format="json",
        )
        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        created = DisciplineIncident.objects.get(id=create_response.data["id"])
        self.assertEqual(created.status, "open")
        self.assertEqual(created.sanction, "")
        self.assertFalse(created.parent_notified)

        patch_response = self.client.patch(
            f"/api/discipline-incidents/{created.id}/",
            {"status": "resolved"},
            format="json",
        )
        self.assertEqual(patch_response.status_code, status.HTTP_403_FORBIDDEN)

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

    def test_bulletin_rows_put_conduite_first_with_coef_2(self):
        rows, average, coef_sum = _build_bulletin_rows(
            subjects=[self.subject_math],
            student_note_by_subject={self.subject_math.id: 12.0},
            exam_note_by_subject={},
            class_average_by_subject={self.subject_math.id: 13.0},
            conduite_note=18.0,
            conduite_coef=2.0,
            conduite_moyenne_classe=17.0,
        )

        self.assertGreaterEqual(len(rows), 2)
        self.assertEqual(rows[0]["subject"], "Conduite")
        self.assertEqual(rows[0]["coef"], 2.0)
        self.assertEqual(rows[0]["note_finale"], 18.0)

        # moyenne attendue = (18*2 + 12*2) / (2+2) = 15
        self.assertEqual(coef_sum, 4.0)
        self.assertEqual(average, 15.0)

    def test_bulletin_rows_compute_weighted_final_sum_per_subject(self):
        rows, average, coef_sum = _build_bulletin_rows(
            subjects=[self.subject_math],
            student_note_by_subject={self.subject_math.id: 12.0},
            exam_note_by_subject={self.subject_math.id: 14.0},
            class_average_by_subject={self.subject_math.id: 13.0},
            conduite_note=18.0,
            conduite_coef=2.0,
            conduite_moyenne_classe=17.0,
        )

        self.assertEqual(rows[1]["note_finale"], 52.0)
        self.assertEqual(coef_sum, 6.0)
        self.assertEqual(average, 14.67)

    def test_teacher_assignment_rejects_duplicate_subject_for_same_class(self):
        self.client.force_authenticate(self.admin_user)

        response = self.client.post(
            "/api/teacher-assignments/",
            {
                "teacher": self.teacher_2.id,
                "subject": self.subject_math.id,
                "classroom": self.class_a.id,
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("subject", response.data)

    def test_bulletin_forbidden_for_user_from_other_establishment(self):
        self.client.force_authenticate(self.supervisor_other_user)

        response = self.client.get(
            f"/api/reports/bulletin/{self.student_1.id}/{self.year.id}/T1/"
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
