import json

from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.common.views import BackupArchiveViewSet
from apps.school.models import AcademicYear, Book, Etablissement, Payment, Student, StudentFee, Teacher


class BackupRestoreUniqueConflictTests(TestCase):
    def setUp(self):
        self.viewset = BackupArchiveViewSet()
        self.etablissement = Etablissement.objects.create(
            name="IFP-OBK Existing",
            address="Adresse",
            phone="600000000",
            email="existing@ifp-obk.com",
        )
        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date="2025-09-01",
            end_date="2026-07-31",
            is_active=True,
        )

    def test_rewrites_global_unique_text_fields_like_book_isbn(self):
        Book.objects.create(
            title="Livre deja present",
            author="Auteur",
            isbn="ISBN-001",
            total_copies=1,
            available_copies=1,
            etablissement=self.etablissement,
        )
        payload = [
            {
                "model": "school.book",
                "pk": 99,
                "fields": {
                    "title": "Livre restaure",
                    "author": "Auteur restaure",
                    "isbn": "ISBN-001",
                    "total_copies": 1,
                    "available_copies": 1,
                    "etablissement": self.etablissement.id,
                },
            }
        ]

        rewritten_payload, stats = self.viewset._resolve_unique_field_conflicts(payload)

        self.assertIn("school.book.isbn", stats)
        self.assertNotEqual(rewritten_payload[0]["fields"]["isbn"], "ISBN-001")

    def test_rewrites_existing_user_student_and_teacher_identifiers(self):
        user = User.objects.create_user(
            username="existing_user",
            password="pass1234",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        student_user = User.objects.create_user(
            username="student_existing",
            password="pass1234",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        teacher_user = User.objects.create_user(
            username="teacher_existing",
            password="pass1234",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        Student.objects.create(
            user=student_user,
            matricule="MAT-001",
            etablissement=self.etablissement,
        )
        Teacher.objects.create(
            user=teacher_user,
            employee_code="EMP-001",
            hire_date="2025-09-01",
            etablissement=self.etablissement,
        )

        payload = [
            {
                "model": "accounts.user",
                "pk": 10,
                "fields": {
                    "username": user.username,
                    "password": "",
                    "last_login": None,
                    "is_superuser": False,
                    "first_name": "",
                    "last_name": "",
                    "email": "",
                    "is_staff": False,
                    "is_active": True,
                    "date_joined": "2026-04-14T00:00:00Z",
                    "role": UserRole.DIRECTOR,
                    "phone": "",
                    "profile_photo": "",
                    "etablissement": self.etablissement.id,
                    "groups": [],
                    "user_permissions": [],
                },
            },
            {
                "model": "school.student",
                "pk": 11,
                "fields": {
                    "user": student_user.id,
                    "matricule": "MAT-001",
                    "birth_date": None,
                    "classroom": None,
                    "parent": None,
                    "photo": "",
                    "enrollment_date": "2026-04-14",
                    "is_archived": False,
                    "conduite": "18.00",
                    "etablissement": self.etablissement.id,
                },
            },
            {
                "model": "school.teacher",
                "pk": 12,
                "fields": {
                    "user": teacher_user.id,
                    "employee_code": "EMP-001",
                    "hire_date": "2026-04-14",
                    "salary_base": "0.00",
                    "hourly_rate": "0.00",
                    "etablissement": self.etablissement.id,
                },
            },
        ]

        rewritten_payload, stats = self.viewset._resolve_unique_field_conflicts(payload)

        self.assertIn("accounts.user.username", stats)
        self.assertIn("school.student.matricule", stats)
        self.assertIn("school.teacher.employee_code", stats)
        self.assertNotEqual(rewritten_payload[0]["fields"]["username"], "existing_user")
        self.assertNotEqual(rewritten_payload[1]["fields"]["matricule"], "MAT-001")
        self.assertNotEqual(rewritten_payload[2]["fields"]["employee_code"], "EMP-001")

    def test_establishment_backup_includes_users_referenced_by_teacher(self):
        external_user = User.objects.create_user(
            username="teacher_external",
            password="pass1234",
            role=UserRole.TEACHER,
            etablissement=None,
        )
        Teacher.objects.create(
            user=external_user,
            employee_code="EMP-EXT-001",
            hire_date="2026-04-14",
            salary_base="0.00",
            hourly_rate="0.00",
            etablissement=self.etablissement,
        )

        payload_json = self.viewset._serialize_etablissement(self.etablissement)
        payload = json.loads(payload_json)

        user_entry_pks = {
            entry["pk"]
            for entry in payload
            if str(entry.get("model") or "").lower().endswith("accounts.user")
        }
        self.assertIn(external_user.id, user_entry_pks)

    def test_drop_orphan_foreign_keys_removes_orphan_teacher_rows(self):
        payload = [
            {
                "model": "school.teacher",
                "pk": 999,
                "fields": {
                    "user": 999999,
                    "employee_code": "EMP-MISSING",
                    "hire_date": "2026-04-14",
                    "salary_base": "0.00",
                    "hourly_rate": "0.00",
                    "etablissement": self.etablissement.id,
                },
            }
        ]

        cleaned_payload, dropped_stats = self.viewset._drop_orphan_foreign_key_relations(payload)

        self.assertEqual(cleaned_payload, [])
        self.assertEqual(dropped_stats.get("school.teacher"), 1)

    def test_drop_orphan_foreign_keys_removes_orphan_payment_rows(self):
        payload = [
            {
                "model": "school.payment",
                "pk": 200,
                "fields": {
                    "fee": 999999,
                    "amount": "120.00",
                    "method": "cash",
                    "reference": "",
                    "received_by": None,
                    "etablissement": self.etablissement.id,
                },
            }
        ]

        cleaned_payload, dropped_stats = self.viewset._drop_orphan_foreign_key_relations(payload)

        self.assertEqual(cleaned_payload, [])
        self.assertEqual(dropped_stats.get("school.payment"), 1)

    def test_drop_orphan_foreign_keys_keeps_payment_when_fee_exists_in_payload(self):
        student_user = User.objects.create_user(
            username="student_linked",
            password="pass1234",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        student = Student.objects.create(
            user=student_user,
            matricule="MAT-LINK-001",
            etablissement=self.etablissement,
        )
        fee = StudentFee.objects.create(
            student=student,
            academic_year=self.year,
            fee_type="monthly",
            amount_due="120.00",
            due_date="2026-04-14",
        )

        payload = [
            {
                "model": "school.studentfee",
                "pk": fee.id,
                "fields": {
                    "student": student.id,
                    "academic_year": self.year.id,
                    "fee_type": "monthly",
                    "amount_due": "120.00",
                    "due_date": "2026-04-14",
                },
            },
            {
                "model": "school.payment",
                "pk": 201,
                "fields": {
                    "fee": fee.id,
                    "amount": "120.00",
                    "method": "cash",
                    "reference": "",
                    "received_by": None,
                    "etablissement": self.etablissement.id,
                },
            },
        ]

        cleaned_payload, dropped_stats = self.viewset._drop_orphan_foreign_key_relations(payload)

        self.assertEqual(len(cleaned_payload), 2)
        self.assertEqual(dropped_stats, {})
