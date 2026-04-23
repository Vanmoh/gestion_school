from __future__ import annotations

from datetime import date

from django.core.management import call_command
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamResult,
    ExamSession,
    Grade,
    GradeValidation,
    ParentProfile,
    Student,
    StudentAcademicHistory,
    Subject,
)


class SeedTermScoresCommandTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="CSOB Runtime Test")
        self.year = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 6, 30),
            is_active=True,
        )
        self.classroom = ClassRoom.objects.create(
            name="6e A",
            academic_year=self.year,
            etablissement=self.etablissement,
        )
        self.subject_1 = Subject.objects.create(
            name="Mathematiques",
            code="MATH-TEST-01",
            coefficient=2,
            classroom=self.classroom,
        )
        self.subject_2 = Subject.objects.create(
            name="Francais",
            code="FR-TEST-01",
            coefficient=1,
            classroom=self.classroom,
        )

        parent_user = User.objects.create_user(
            username="parent_seed_term_scores",
            password="parent12345",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        parent = ParentProfile.objects.create(user=parent_user, etablissement=self.etablissement)

        for index in range(2):
            user = User.objects.create_user(
                username=f"student_seed_term_scores_{index}",
                password="student12345",
                role=UserRole.STUDENT,
                first_name=f"Student{index}",
                last_name="Seed",
                etablissement=self.etablissement,
            )
            Student.objects.create(
                user=user,
                classroom=self.classroom,
                parent=parent,
                etablissement=self.etablissement,
            )

    def test_seed_term_scores_creates_runtime_like_scores(self):
        call_command(
            "seed_term_scores",
            etab_id=self.etablissement.id,
            term="T1",
            seed=123,
        )

        self.assertEqual(Grade.objects.filter(classroom=self.classroom, term="T1").count(), 4)
        self.assertEqual(
            ExamResult.objects.filter(student__etablissement=self.etablissement, session__term="T1").count(),
            4,
        )
        self.assertEqual(
            StudentAcademicHistory.objects.filter(classroom=self.classroom, academic_year=self.year).count(),
            2,
        )

        sample_grade = Grade.objects.filter(classroom=self.classroom, term="T1").order_by("id").first()
        self.assertIsNotNone(sample_grade)
        self.assertEqual(len(sample_grade.homework_scores), 3)
        self.assertTrue(all(0 <= float(score) <= 20 for score in sample_grade.homework_scores))

        session = ExamSession.objects.filter(academic_year=self.year, term="T1").first()
        self.assertIsNotNone(session)

    def test_seed_term_scores_dry_run_keeps_database_unchanged(self):
        call_command(
            "seed_term_scores",
            etab_id=self.etablissement.id,
            term="T2",
            seed=456,
            dry_run=True,
        )

        self.assertEqual(Grade.objects.filter(classroom=self.classroom, term="T2").count(), 0)
        self.assertEqual(
            ExamResult.objects.filter(student__etablissement=self.etablissement, session__term="T2").count(),
            0,
        )

    def test_seed_term_scores_can_close_term(self):
        call_command(
            "seed_term_scores",
            etab_id=self.etablissement.id,
            term="T3",
            seed=789,
            close_term=True,
            close_notes="Cloture test T3",
        )

        validation = GradeValidation.objects.filter(
            classroom=self.classroom,
            academic_year=self.year,
            term="T3",
            is_validated=True,
        ).first()
        self.assertIsNotNone(validation)
        self.assertEqual(validation.notes, "Cloture test T3")