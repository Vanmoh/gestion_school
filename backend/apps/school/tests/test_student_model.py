from django.test import TestCase
from django.core.exceptions import ValidationError
from datetime import date, timedelta
from decimal import Decimal
from apps.school.models import Student, Etablissement, AcademicYear, ClassRoom
from apps.accounts.models import User


class StudentModelTest(TestCase):
    """Tests for Student model and validation"""

    def setUp(self):
        """Create required fixtures"""
        self.user = User.objects.create_user(
            username='test_student',
            email='student@test.com',
            first_name='Test',
            last_name='Student'
        )

        self.etablissement = Etablissement.objects.create(
            name='Test School',
            address='Test Address',
            phone='+223 12 34 56 78'
        )

        self.academic_year = AcademicYear.objects.create(
            name='2024-2025',
            start_date=date(2024, 9, 1),
            end_date=date(2025, 6, 30)
        )

        self.classroom = ClassRoom.objects.create(
            name='10ème CT',
            academic_year=self.academic_year,
            etablissement=self.etablissement
        )

    def test_student_creation(self):
        """Test basic student creation"""
        student = Student.objects.create(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement
        )
        self.assertIsNotNone(student.id)
        self.assertEqual(student.gender, 'M')

    def test_matricule_auto_generation(self):
        """Test that matricule is auto-generated on save"""
        student = Student.objects.create(
            user=self.user,
            gender='F',
            classroom=self.classroom,
            etablissement=self.etablissement
        )
        self.assertIsNotNone(student.matricule)
        self.assertTrue(len(student.matricule) > 0)

    def test_matricule_uniqueness(self):
        """Test that matricule is unique"""
        student1 = Student.objects.create(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement
        )

        user2 = User.objects.create_user(
            username='test_student2',
            email='student2@test.com'
        )

        student2 = Student.objects.create(
            user=user2,
            gender='F',
            classroom=self.classroom,
            etablissement=self.etablissement
        )

        self.assertNotEqual(student1.matricule, student2.matricule)

    def test_birthdate_validation_future_date(self):
        """Test that future birthdate is rejected"""
        future_date = date.today() + timedelta(days=1)

        student = Student(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement,
            birth_date=future_date
        )

        with self.assertRaises(ValidationError):
            student.full_clean()

    def test_birthdate_validation_valid_date(self):
        """Test that past birthdate is accepted"""
        past_date = date(2005, 1, 15)

        student = Student(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement,
            birth_date=past_date
        )

        try:
            student.full_clean()
        except ValidationError:
            self.fail("Valid past birthdate should not raise ValidationError")

    def test_conduite_validation_valid_range(self):
        """Test that conduite within 0-20 is valid"""
        student = Student(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement,
            conduite=Decimal('18.50')
        )

        try:
            student.full_clean()
        except ValidationError:
            self.fail("Valid conduite should not raise ValidationError")

    def test_conduite_validation_below_range(self):
        """Test that conduite below 0 is rejected"""
        student = Student(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement,
            conduite=Decimal('-1')
        )

        with self.assertRaises(ValidationError):
            student.full_clean()

    def test_conduite_validation_above_range(self):
        """Test that conduite above 20 is rejected"""
        student = Student(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement,
            conduite=Decimal('21')
        )

        with self.assertRaises(ValidationError):
            student.full_clean()

    def test_gender_choices(self):
        """Test that only M and F are valid gender choices"""
        valid_genders = ['M', 'F']

        for gender in valid_genders:
            student = Student.objects.create(
                user=User.objects.create_user(f'user_{gender}'),
                gender=gender,
                classroom=self.classroom,
                etablissement=self.etablissement
            )
            self.assertEqual(student.gender, gender)

    def test_matricule_normalization(self):
        """Test that establishment and class codes are normalized correctly"""
        student = Student.objects.create(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement
        )

        # Matricule should contain normalized codes
        self.assertTrue(len(student.matricule) > 0)
        # Should have gender indicator at end
        self.assertIn(student.matricule[-1], ['M', 'F'])

    def test_default_conduite_value(self):
        """Test that default conduite value is 18"""
        student = Student.objects.create(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement
        )

        self.assertEqual(student.conduite, Decimal('18'))

    def test_student_string_representation(self):
        """Test __str__ method"""
        student = Student.objects.create(
            user=self.user,
            gender='M',
            classroom=self.classroom,
            etablissement=self.etablissement
        )

        str_repr = str(student)
        self.assertIn(student.matricule, str_repr)
        self.assertIn(self.user.get_full_name(), str_repr)
