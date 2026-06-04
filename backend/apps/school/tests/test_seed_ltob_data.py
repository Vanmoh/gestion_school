from django.test import TestCase
from django.core.management import call_command
from io import StringIO
from apps.school.models import Etablissement, AcademicYear, ClassRoom, Subject, Student
from apps.accounts.models import User


class SeedLTOBDataCommandTest(TestCase):
    """Tests for seed_ltob_data management command"""

    def setUp(self):
        """Create required fixtures"""
        self.academic_year = AcademicYear.objects.create(
            name='2024-2025',
            start_date='2024-09-01',
            end_date='2025-06-30',
            is_active=True
        )

    def test_command_creates_etablissement(self):
        """Test that command creates LTOB establishment"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')

        etab = Etablissement.objects.get(name='LTOB')
        self.assertIsNotNone(etab)
        self.assertEqual(etab.phone, '+223 12 34 56 78')

    def test_command_creates_classrooms(self):
        """Test that command creates all 5 classrooms"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')

        classrooms = ClassRoom.objects.filter(academic_year=self.academic_year)
        self.assertEqual(classrooms.count(), 5)

        class_names = [c.name for c in classrooms]
        self.assertIn('10ème CT', class_names)
        self.assertIn('11ème CG', class_names)

    def test_command_creates_subjects(self):
        """Test that command creates subjects for each classroom"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')

        subjects = Subject.objects.all()
        self.assertGreater(subjects.count(), 0)

        french = Subject.objects.filter(code='FR').first()
        self.assertIsNotNone(french)

    def test_command_creates_students(self):
        """Test that command creates 50 students (10 per class x 5 classes)"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')

        students = Student.objects.all()
        self.assertEqual(students.count(), 50)

    def test_student_has_valid_matricule(self):
        """Test that students have valid matricule format"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')

        student = Student.objects.first()
        self.assertIsNotNone(student.matricule)
        self.assertTrue(len(student.matricule) > 0)
        # Format: LXNNXXEYYYYM/F where X=letters, N=numbers
        self.assertTrue(any(c.isalpha() for c in student.matricule))

    def test_student_has_gender(self):
        """Test that students have gender assigned"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')

        student = Student.objects.first()
        self.assertIn(student.gender, ['M', 'F'])

    def test_student_has_valid_conduite(self):
        """Test that students have conduite between 15-20"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')

        for student in Student.objects.all():
            self.assertGreaterEqual(student.conduite, 15)
            self.assertLessEqual(student.conduite, 20)

    def test_command_with_custom_etablissement(self):
        """Test command with custom establishment name"""
        call_command('seed_ltob_data', '--etablissement=TestSchool', '--academic-year=2024-2025')

        etab = Etablissement.objects.get(name='TestSchool')
        self.assertIsNotNone(etab)

    def test_command_idempotent(self):
        """Test that running command twice doesn't duplicate data"""
        call_command('seed_ltob_data', '--academic-year=2024-2025')
        count_first = Student.objects.count()

        call_command('seed_ltob_data', '--academic-year=2024-2025')
        count_second = Student.objects.count()

        self.assertEqual(count_first, count_second)

    def test_command_output(self):
        """Test that command produces expected output"""
        out = StringIO()
        call_command('seed_ltob_data', '--academic-year=2024-2025', stdout=out)

        output = out.getvalue()
        self.assertIn('SEEDING COMPLETED SUCCESSFULLY', output)
        self.assertIn('Établissement: LTOB', output)
