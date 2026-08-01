from datetime import date, time
from io import BytesIO

from django.core.files.uploadedfile import SimpleUploadedFile
from openpyxl import Workbook
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamResult,
    ExamSession,
    Grade,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
)


class AcademicImportsApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Import College",
            address="Centre",
            phone="770001100",
            email="imports@example.com",
        )
        self.admin_user = User.objects.create_user(
            username="admin_imports",
            password="admin12345",
            role=UserRole.SUPER_ADMIN,
            first_name="Admin",
            last_name="Imports",
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(self.admin_user)

        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.classroom = ClassRoom.objects.create(
            name="6A",
            academic_year=self.year,
            etablissement=self.etablissement,
        )

        self.subject_math = Subject.objects.create(
            name="Mathematiques",
            code="MAT",
            coefficient=2,
            classroom=self.classroom,
        )
        self.subject_phy = Subject.objects.create(
            name="Physique",
            code="PHY",
            coefficient=1,
            classroom=self.classroom,
        )

        teacher_user_1 = User.objects.create_user(
            username="teacher_imports_1",
            password="teacher12345",
            role=UserRole.TEACHER,
            first_name="Alice",
            last_name="Prof",
            etablissement=self.etablissement,
        )
        self.teacher_1 = Teacher.objects.create(
            user=teacher_user_1,
            employee_code="ENS-IMP-01",
            hire_date=date(2020, 9, 1),
            salary_base=1000,
            etablissement=self.etablissement,
        )

        teacher_user_2 = User.objects.create_user(
            username="teacher_imports_2",
            password="teacher12345",
            role=UserRole.TEACHER,
            first_name="Bob",
            last_name="Prof",
            etablissement=self.etablissement,
        )
        self.teacher_2 = Teacher.objects.create(
            user=teacher_user_2,
            employee_code="ENS-IMP-02",
            hire_date=date(2021, 9, 1),
            salary_base=1000,
            etablissement=self.etablissement,
        )

        self.assignment_math = TeacherAssignment.objects.create(
            teacher=self.teacher_1,
            subject=self.subject_math,
            classroom=self.classroom,
        )
        self.assignment_phy = TeacherAssignment.objects.create(
            teacher=self.teacher_2,
            subject=self.subject_phy,
            classroom=self.classroom,
        )

        student_user_1 = User.objects.create_user(
            username="student_imports_1",
            password="student12345",
            role=UserRole.STUDENT,
            first_name="Old",
            last_name="Name",
            etablissement=self.etablissement,
        )
        self.student_1 = Student.objects.create(
            user=student_user_1,
            matricule="MAT001",
            classroom=self.classroom,
            etablissement=self.etablissement,
        )

        student_user_2 = User.objects.create_user(
            username="student_imports_2",
            password="student12345",
            role=UserRole.STUDENT,
            first_name="Second",
            last_name="Student",
            etablissement=self.etablissement,
        )
        self.student_2 = Student.objects.create(
            user=student_user_2,
            matricule="MAT002",
            classroom=self.classroom,
            etablissement=self.etablissement,
        )

        self.exam_session = ExamSession.objects.create(
            title="Session T1",
            term="T1",
            academic_year=self.year,
            start_date=date(2025, 12, 10),
            end_date=date(2025, 12, 20),
        )

    def _csv_upload(self, filename, content):
        return SimpleUploadedFile(
            name=filename,
            content=content.encode("utf-8"),
            content_type="text/csv",
        )

    def _xlsx_upload(self, filename, headers, rows):
        workbook = Workbook()
        sheet = workbook.active
        sheet.append(headers)
        for row in rows:
            sheet.append(row)
        stream = BytesIO()
        workbook.save(stream)
        stream.seek(0)
        return SimpleUploadedFile(
            name=filename,
            content=stream.read(),
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )

    def test_students_import_by_class_preview_and_confirm(self):
        preview_file = self._csv_upload(
            "students.csv",
            "matricule,first_name,last_name,email,phone,birth_date\n"
            "MAT001,Updated,Student,updated@example.com,770111111,2012-05-01\n"
            "MAT003,New,Learner,new@example.com,770222222,2013-03-10\n",
        )
        preview_response = self.client.post(
            "/api/students/import-by-class/",
            {"classroom_id": str(self.classroom.id), "file": preview_file},
            format="multipart",
        )

        self.assertEqual(preview_response.status_code, status.HTTP_200_OK)
        self.assertEqual(preview_response.data["summary"]["to_create"], 1)
        self.assertEqual(preview_response.data["summary"]["to_update"], 1)
        self.assertTrue(preview_response.data["confirm_required"])

        confirm_file = self._csv_upload(
            "students.csv",
            "matricule,first_name,last_name,email,phone,birth_date\n"
            "MAT001,Updated,Student,updated@example.com,770111111,2012-05-01\n"
            "MAT003,New,Learner,new@example.com,770222222,2013-03-10\n",
        )
        confirm_response = self.client.post(
            "/api/students/import-by-class/",
            {
                "classroom_id": str(self.classroom.id),
                "confirm": "true",
                "file": confirm_file,
            },
            format="multipart",
        )

        self.assertEqual(confirm_response.status_code, status.HTTP_200_OK)
        self.assertEqual(confirm_response.data["result"]["created"], 1)
        self.assertEqual(confirm_response.data["result"]["updated"], 1)

        self.student_1.refresh_from_db()
        self.assertEqual(self.student_1.user.first_name, "Updated")
        self.assertTrue(Student.objects.filter(matricule="MAT003", classroom=self.classroom).exists())

    def test_controls_import_supports_xlsx_preview_and_confirm(self):
        Grade.objects.create(
            student=self.student_1,
            subject=self.subject_math,
            classroom=self.classroom,
            academic_year=self.year,
            term="T1",
            value=10,
        )

        preview_file = self._xlsx_upload(
            "controls.xlsx",
            ["student_matricule", "subject_code", "value"],
            [["MAT001", "MAT", "15.5"], ["MAT002", "PHY", "13"]],
        )
        preview_response = self.client.post(
            "/api/grades/import-controls/",
            {
                "classroom_id": str(self.classroom.id),
                "academic_year_id": str(self.year.id),
                "term": "T1",
                "file": preview_file,
            },
            format="multipart",
        )

        self.assertEqual(preview_response.status_code, status.HTTP_200_OK)
        self.assertEqual(preview_response.data["summary"]["to_create"], 1)
        self.assertEqual(preview_response.data["summary"]["to_update"], 1)

        confirm_file = self._xlsx_upload(
            "controls.xlsx",
            ["student_matricule", "subject_code", "value"],
            [["MAT001", "MAT", "15.5"], ["MAT002", "PHY", "13"]],
        )
        confirm_response = self.client.post(
            "/api/grades/import-controls/",
            {
                "classroom_id": str(self.classroom.id),
                "academic_year_id": str(self.year.id),
                "term": "T1",
                "confirm": "true",
                "file": confirm_file,
            },
            format="multipart",
        )

        self.assertEqual(confirm_response.status_code, status.HTTP_200_OK)
        self.assertEqual(confirm_response.data["result"]["created"], 1)
        self.assertEqual(confirm_response.data["result"]["updated"], 1)
        self.assertEqual(
            str(
                Grade.objects.get(
                    student=self.student_1,
                    subject=self.subject_math,
                    classroom=self.classroom,
                    academic_year=self.year,
                    term="T1",
                ).value
            ),
            "15.50",
        )

    def test_exam_import_preview_and_confirm(self):
        ExamResult.objects.create(
            session=self.exam_session,
            student=self.student_1,
            subject=self.subject_math,
            score=9,
        )

        preview_file = self._csv_upload(
            "exams.csv",
            "student_matricule,subject_code,score\n"
            "MAT001,MAT,14\n"
            "MAT002,PHY,12\n",
        )
        preview_response = self.client.post(
            "/api/exam-results/import-exams/",
            {
                "classroom_id": str(self.classroom.id),
                "session_id": str(self.exam_session.id),
                "file": preview_file,
            },
            format="multipart",
        )

        self.assertEqual(preview_response.status_code, status.HTTP_200_OK)
        self.assertEqual(preview_response.data["summary"]["to_create"], 1)
        self.assertEqual(preview_response.data["summary"]["to_update"], 1)

        confirm_file = self._csv_upload(
            "exams.csv",
            "student_matricule,subject_code,score\n"
            "MAT001,MAT,14\n"
            "MAT002,PHY,12\n",
        )
        confirm_response = self.client.post(
            "/api/exam-results/import-exams/",
            {
                "classroom_id": str(self.classroom.id),
                "session_id": str(self.exam_session.id),
                "confirm": "true",
                "file": confirm_file,
            },
            format="multipart",
        )

        self.assertEqual(confirm_response.status_code, status.HTTP_200_OK)
        self.assertEqual(confirm_response.data["result"]["created"], 1)
        self.assertEqual(confirm_response.data["result"]["updated"], 1)
        self.assertEqual(
            str(
                ExamResult.objects.get(
                    session=self.exam_session,
                    student=self.student_1,
                    subject=self.subject_math,
                ).score
            ),
            "14.00",
        )

    def test_timetable_import_requires_confirm_conflicts_for_class_overlaps(self):
        existing_slot = TeacherScheduleSlot.objects.create(
            assignment=self.assignment_phy,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
            room="A1",
        )

        preview_file = self._csv_upload(
            "timetable.csv",
            "day_of_week,start_time,end_time,subject_code,room\n"
            "MON,08:30,09:30,MAT,A2\n",
        )
        preview_response = self.client.post(
            "/api/teacher-schedule-slots/import-by-class/",
            {"classroom_id": str(self.classroom.id), "file": preview_file},
            format="multipart",
        )

        self.assertEqual(preview_response.status_code, status.HTTP_200_OK)
        self.assertEqual(preview_response.data["summary"]["conflicts"], 1)
        self.assertTrue(preview_response.data["confirm_conflicts_required"])

        confirm_file = self._csv_upload(
            "timetable.csv",
            "day_of_week,start_time,end_time,subject_code,room\n"
            "MON,08:30,09:30,MAT,A2\n",
        )
        blocked_response = self.client.post(
            "/api/teacher-schedule-slots/import-by-class/",
            {
                "classroom_id": str(self.classroom.id),
                "confirm": "true",
                "file": confirm_file,
            },
            format="multipart",
        )

        self.assertEqual(blocked_response.status_code, status.HTTP_409_CONFLICT)

        confirmed_file = self._csv_upload(
            "timetable.csv",
            "day_of_week,start_time,end_time,subject_code,room\n"
            "MON,08:30,09:30,MAT,A2\n",
        )
        confirmed_response = self.client.post(
            "/api/teacher-schedule-slots/import-by-class/",
            {
                "classroom_id": str(self.classroom.id),
                "confirm": "true",
                "confirm_conflicts": "true",
                "file": confirmed_file,
            },
            format="multipart",
        )

        self.assertEqual(confirmed_response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(confirmed_response.data["result"]["deleted_conflicts"], 1)
        self.assertFalse(TeacherScheduleSlot.objects.filter(id=existing_slot.id).exists())
        self.assertTrue(
            TeacherScheduleSlot.objects.filter(
                assignment=self.assignment_math,
                day_of_week="MON",
                start_time=time(8, 30),
                end_time=time(9, 30),
            ).exists()
        )
