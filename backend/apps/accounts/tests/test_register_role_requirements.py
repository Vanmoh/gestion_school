from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, ParentProfile, Student


class RegisterRoleRequirementsTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etablissement Test",
            address="Quartier Test",
            phone="620000100",
            email="etab@test.com",
        )
        self.academic_year = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 7, 31),
            is_active=True,
        )
        self.classroom_a = ClassRoom.objects.create(
            name="6e A",
            academic_year=self.academic_year,
            etablissement=self.etablissement,
        )
        self.classroom_b = ClassRoom.objects.create(
            name="6e B",
            academic_year=self.academic_year,
            etablissement=self.etablissement,
        )

        self.admin = User.objects.create_user(
            username="director_register",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(self.admin)

        self.student_user_1 = User.objects.create_user(
            username="student_role_1",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.student_user_2 = User.objects.create_user(
            username="student_role_2",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )

        self.student_profile_1 = Student.objects.create(
            user=self.student_user_1,
            classroom=self.classroom_a,
            etablissement=self.etablissement,
        )
        self.student_profile_2 = Student.objects.create(
            user=self.student_user_2,
            classroom=self.classroom_b,
            etablissement=self.etablissement,
        )

    def test_register_student_requires_classroom(self):
        payload = {
            "username": "new_student_no_class",
            "first_name": "New",
            "last_name": "Student",
            "email": "new-student@test.com",
            "password": "Pass1234!",
            "role": UserRole.STUDENT,
            "phone": "620001111",
            "etablissement": self.etablissement.id,
        }

        response = self.client.post("/api/auth/register/", payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("classroom", response.data)

    def test_register_parent_requires_students_selection(self):
        payload = {
            "username": "new_parent_no_students",
            "first_name": "New",
            "last_name": "Parent",
            "email": "new-parent@test.com",
            "password": "Pass1234!",
            "role": UserRole.PARENT,
            "phone": "620002222",
            "etablissement": self.etablissement.id,
            "classroom": self.classroom_a.id,
        }

        response = self.client.post("/api/auth/register/", payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("students", response.data)

    def test_register_parent_accepts_students_from_different_classrooms(self):
        payload = {
            "username": "new_parent_multi_class",
            "first_name": "Multi",
            "last_name": "Parent",
            "email": "new-parent-multi@test.com",
            "password": "Pass1234!",
            "role": UserRole.PARENT,
            "phone": "620003333",
            "etablissement": self.etablissement.id,
            "classroom": self.classroom_a.id,
            "students": [self.student_profile_1.id, self.student_profile_2.id],
        }

        response = self.client.post("/api/auth/register/", payload, format="json")

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        parent_user = User.objects.get(username="new_parent_multi_class")
        parent_profile = ParentProfile.objects.get(user=parent_user)

        self.student_profile_1.refresh_from_db()
        self.student_profile_2.refresh_from_db()

        self.assertEqual(self.student_profile_1.parent_id, parent_profile.id)
        self.assertEqual(self.student_profile_2.parent_id, parent_profile.id)
