from datetime import date, timedelta
from unittest.mock import patch

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.views import _build_bulletin_payload, _build_bulletin_rows
from apps.school.models import (
    AcademicYear,
    Attendance,
    ClassRoom,
    DisciplineIncident,
    Etablissement,
    ExamResult,
    ExamSession,
    Grade,
    GradeValidation,
    ParentProfile,
    Student,
    StudentAcademicHistory,
    Subject,
    Teacher,
    TeacherAssignment,
    recalculate_term_ranking,
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
        self.client.force_authenticate(self.supervisor_user)

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

    def test_validate_term_closes_period_and_recalculates_ranking(self):
        self.client.force_authenticate(self.admin_user)

        self.grade_1.value = 10
        self.grade_1.save(update_fields=["value", "updated_at"])
        self.grade_2.value = 12
        self.grade_2.save(update_fields=["value", "updated_at"])

        session = ExamSession.objects.create(
            title="Examen T1 closure",
            term="T1",
            academic_year=self.year,
            start_date=date(2026, 1, 12),
            end_date=date(2026, 1, 13),
        )
        ExamResult.objects.create(
            session=session,
            student=self.student_1,
            subject=self.subject_math,
            score=20,
        )
        ExamResult.objects.create(
            session=session,
            student=self.student_2,
            subject=self.subject_math,
            score=0,
        )

        response = self.client.post(
            "/api/grades/validate_term/",
            {
                "classroom": self.class_a.id,
                "academic_year": self.year.id,
                "term": "T1",
                "notes": "Fin du trimestre",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data.get("is_validated"))
        self.assertIn("clôturée", str(response.data.get("detail", "")))
        self.assertEqual(response.data.get("history_rows"), 2)

        history_1 = StudentAcademicHistory.objects.get(
            student=self.student_1,
            academic_year=self.year,
            classroom=self.class_a,
        )
        history_2 = StudentAcademicHistory.objects.get(
            student=self.student_2,
            academic_year=self.year,
            classroom=self.class_a,
        )
        self.assertEqual(float(history_1.average), 15.0)
        self.assertEqual(float(history_2.average), 6.0)
        self.assertEqual(history_1.rank, 1)
        self.assertEqual(history_2.rank, 2)

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

    def test_recalculate_term_ranking_includes_exam_results(self):
        session = ExamSession.objects.create(
            title="Examen T1",
            term="T1",
            academic_year=self.year,
            start_date=date(2026, 1, 10),
            end_date=date(2026, 1, 11),
        )
        ExamResult.objects.create(
            session=session,
            student=self.student_1,
            subject=self.subject_math,
            score=20,
        )
        ExamResult.objects.create(
            session=session,
            student=self.student_2,
            subject=self.subject_math,
            score=0,
        )

        self.grade_1.value = 10
        self.grade_1.save(update_fields=["value", "updated_at"])
        self.grade_2.value = 12
        self.grade_2.save(update_fields=["value", "updated_at"])

        recalculate_term_ranking(self.class_a, self.year, "T1")

        history_1 = StudentAcademicHistory.objects.get(
            student=self.student_1,
            academic_year=self.year,
            classroom=self.class_a,
        )
        history_2 = StudentAcademicHistory.objects.get(
            student=self.student_2,
            academic_year=self.year,
            classroom=self.class_a,
        )

        self.assertEqual(float(history_1.average), 15.0)
        self.assertEqual(float(history_2.average), 6.0)
        self.assertEqual(history_1.rank, 1)
        self.assertEqual(history_2.rank, 2)

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

        self.assertEqual(rows[1]["note_finale"], 13.0)
        self.assertEqual(rows[1]["points"], 26.0)
        self.assertEqual(coef_sum, 4.0)
        self.assertEqual(average, 15.5)

    def test_bulletin_payload_uses_establishment_signature_and_stamp_settings(self):
        self.etablissement_main.principal_signature_label = "Proviseur"
        self.etablissement_main.principal_signature_position = "center"
        self.etablissement_main.principal_signature_scale = 140
        self.etablissement_main.stamp_position = "left"
        self.etablissement_main.stamp_scale = 130
        self.etablissement_main.save(
            update_fields=[
                "principal_signature_label",
                "principal_signature_position",
                "principal_signature_scale",
                "stamp_position",
                "stamp_scale",
            ]
        )

        payload = _build_bulletin_payload(
            student=self.student_1,
            academic_year_id=self.year.id,
            normalized_term="T1",
        )

        self.assertEqual(payload["signature_label"], "Proviseur")
        self.assertEqual(payload["signature_position"], "center")
        self.assertEqual(payload["stamp_position"], "left")
        self.assertEqual(payload["signature_scale"], 1.4)
        self.assertEqual(payload["stamp_scale"], 1.3)

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

    @patch("apps.reports.views._render_bulletin_page")
    @patch("apps.reports.views._build_bulletin_payload")
    def test_class_bulletins_print_order_follows_rank(self, mock_build_payload, mock_render_page):
        StudentAcademicHistory.objects.update_or_create(
            student=self.student_1,
            academic_year=self.year,
            classroom=self.class_a,
            defaults={"average": 12.0, "rank": 2},
        )
        StudentAcademicHistory.objects.update_or_create(
            student=self.student_2,
            academic_year=self.year,
            classroom=self.class_a,
            defaults={"average": 14.0, "rank": 1},
        )

        mock_build_payload.side_effect = lambda **kwargs: {
            "period_label": "T1",
            "student_matricule": kwargs["student"].matricule,
        }

        self.client.force_authenticate(self.admin_user)
        response = self.client.get(
                f"/api/reports/bulletins/class/{self.class_a.id}/{self.year.id}/T1/",
                HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)

        ordered_student_ids = [
            call.kwargs["student"].id
            for call in mock_build_payload.call_args_list
        ]
        self.assertEqual(ordered_student_ids, [self.student_2.id, self.student_1.id])

    def test_student_fee_rejects_due_date_outside_academic_year(self):
        self.client.force_authenticate(self.admin_user)

        response = self.client.post(
            "/api/fees/",
            {
                "student": self.student_1.id,
                "academic_year": self.year.id,
                "fee_type": "registration",
                "amount_due": "150000",
                "due_date": str(self.year.end_date + timedelta(days=7)),
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("due_date", response.data)

    def test_payment_rejects_duplicate_non_cash_reference(self):
        self.client.force_authenticate(self.admin_user)
        fee_response = self.client.post(
            "/api/fees/",
            {
                "student": self.student_1.id,
                "academic_year": self.year.id,
                "fee_type": "registration",
                "amount_due": "100000",
                "due_date": str(self.year.start_date),
            },
            format="json",
        )
        self.assertEqual(fee_response.status_code, status.HTTP_201_CREATED)
        fee_id = fee_response.data["id"]

        create_first = self.client.post(
            "/api/payments/",
            {
                "fee": fee_id,
                "amount": "50000",
                "method": "mobile money",
                "reference": "TXN-ABC-001",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )
        self.assertEqual(create_first.status_code, status.HTTP_201_CREATED)

        create_second = self.client.post(
            "/api/payments/",
            {
                "fee": fee_id,
                "amount": "10000",
                "method": "momo",
                "reference": "TXN-ABC-001",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )
        self.assertEqual(create_second.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("reference", create_second.data)

    def test_payment_rejects_short_reference_for_non_cash_method(self):
        self.client.force_authenticate(self.admin_user)
        fee_response = self.client.post(
            "/api/fees/",
            {
                "student": self.student_1.id,
                "academic_year": self.year.id,
                "fee_type": "registration",
                "amount_due": "100000",
                "due_date": str(self.year.start_date),
            },
            format="json",
        )
        self.assertEqual(fee_response.status_code, status.HTTP_201_CREATED)
        fee_id = fee_response.data["id"]

        response = self.client.post(
            "/api/payments/",
            {
                "fee": fee_id,
                "amount": "50000",
                "method": "virement",
                "reference": "A1",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("reference", response.data)

    def test_payment_update_cannot_override_received_by(self):
        self.client.force_authenticate(self.admin_user)
        fee_response = self.client.post(
            "/api/fees/",
            {
                "student": self.student_1.id,
                "academic_year": self.year.id,
                "fee_type": "registration",
                "amount_due": "100000",
                "due_date": str(self.year.start_date),
            },
            format="json",
        )
        self.assertEqual(fee_response.status_code, status.HTTP_201_CREATED)
        fee_id = fee_response.data["id"]

        create_response = self.client.post(
            "/api/payments/",
            {
                "fee": fee_id,
                "amount": "15000",
                "method": "cash",
                "reference": "",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )
        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        payment_id = create_response.data["id"]

        patch_response = self.client.patch(
            f"/api/payments/{payment_id}/",
            {
                "received_by": self.supervisor_user.id,
                "amount": "14000",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )
        self.assertEqual(patch_response.status_code, status.HTTP_200_OK)

        details = self.client.get(
            f"/api/payments/{payment_id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )
        self.assertEqual(details.status_code, status.HTTP_200_OK)
        self.assertEqual(details.data.get("received_by"), self.admin_user.id)
        self.assertEqual(str(details.data.get("amount")), "14000.00")

    def test_expense_rejects_future_date(self):
        self.client.force_authenticate(self.admin_user)

        response = self.client.post(
            "/api/expenses/",
            {
                "label": "Achat fournitures",
                "amount": "25000",
                "date": str(date.today() + timedelta(days=1)),
                "category": "fourniture",
                "notes": "Commande en cours",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement_main.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("date", response.data)
