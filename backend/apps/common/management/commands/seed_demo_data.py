from datetime import date, time, timedelta
from decimal import Decimal
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Announcement,
    Attendance,
    Book,
    Borrow,
    CanteenMenu,
    CanteenService,
    CanteenSubscription,
    ClassRoom,
    DisciplineIncident,
    ExamPlanning,
    ExamInvigilation,
    ExamResult,
    ExamSession,
    Expense,
    FeeType,
    Grade,
    Notification,
    NotificationChannel,
    ParentProfile,
    Payment,
    SmsProviderConfig,
    StockItem,
    StockMovement,
    StockMovementType,
    Student,
    StudentFee,
    Subject,
    Supplier,
    Teacher,
    TeacherAttendance,
    TeacherAssignment,
    TeacherPayroll,
    recalculate_term_ranking,
)


class Command(BaseCommand):
    help = "Seed demo data for GESTION SCHOOL"

    @staticmethod
    def _get_or_create_subject_for_classroom(classroom, code, name, coefficient):
        subject = (
            Subject.objects.filter(classroom=classroom, code=code)
            .order_by("id")
            .first()
        )
        if subject:
            return subject
        return Subject.objects.create(
            classroom=classroom,
            code=code,
            name=name,
            coefficient=coefficient,
        )

    @transaction.atomic
    def handle(self, *args, **options):
        today = timezone.now().date()

        admin_user, created = User.objects.get_or_create(
            username="superadmin",
            defaults={
                "first_name": "Super",
                "last_name": "Admin",
                "email": "admin@gestionschool.local",
                "role": UserRole.SUPER_ADMIN,
                "is_staff": True,
                "is_superuser": True,
            },
        )
        admin_user.set_password("Admin@12345")
        admin_user.is_active = True
        admin_user.is_staff = True
        admin_user.is_superuser = True
        admin_user.save(update_fields=["password", "is_active", "is_staff", "is_superuser"])

        director_user, _ = User.objects.get_or_create(
            username="directeur",
            defaults={
                "first_name": "Jean",
                "last_name": "Directeur",
                "email": "directeur@gestionschool.local",
                "role": UserRole.DIRECTOR,
            },
        )
        director_user.set_password("Password@123")
        director_user.is_active = True
        director_user.save(update_fields=["password", "is_active"])

        accountant_user, _ = User.objects.get_or_create(
            username="comptable",
            defaults={
                "first_name": "Marie",
                "last_name": "Comptable",
                "email": "comptable@gestionschool.local",
                "role": UserRole.ACCOUNTANT,
            },
        )
        accountant_user.set_password("Password@123")
        accountant_user.is_active = True
        accountant_user.save(update_fields=["password", "is_active"])

        teacher_user, _ = User.objects.get_or_create(
            username="enseignant1",
            defaults={
                "first_name": "Ali",
                "last_name": "Kouadio",
                "email": "enseignant1@gestionschool.local",
                "role": UserRole.TEACHER,
            },
        )
        teacher_user.set_password("Password@123")
        teacher_user.is_active = True
        teacher_user.save(update_fields=["password", "is_active"])

        parent_user, _ = User.objects.get_or_create(
            username="parent1",
            defaults={
                "first_name": "Awa",
                "last_name": "Traore",
                "email": "parent1@gestionschool.local",
                "role": UserRole.PARENT,
            },
        )
        parent_user.set_password("Password@123")
        parent_user.is_active = True
        parent_user.save(update_fields=["password", "is_active"])

        supervisor_user, _ = User.objects.get_or_create(
            username="surveillant1",
            defaults={
                "first_name": "Idrissa",
                "last_name": "Keita",
                "email": "surveillant1@gestionschool.local",
                "role": UserRole.SUPERVISOR,
            },
        )
        supervisor_user.set_password("Password@123")
        supervisor_user.is_active = True
        supervisor_user.save(update_fields=["password", "is_active"])

        student_user_1, _ = User.objects.get_or_create(
            username="eleve1",
            defaults={
                "first_name": "Koffi",
                "last_name": "Nguessan",
                "email": "eleve1@gestionschool.local",
                "role": UserRole.STUDENT,
            },
        )
        student_user_1.set_password("Password@123")
        student_user_1.is_active = True
        student_user_1.save(update_fields=["password", "is_active"])

        student_user_2, _ = User.objects.get_or_create(
            username="eleve2",
            defaults={
                "first_name": "Fatou",
                "last_name": "Diallo",
                "email": "eleve2@gestionschool.local",
                "role": UserRole.STUDENT,
            },
        )
        student_user_2.set_password("Password@123")
        student_user_2.is_active = True
        student_user_2.save(update_fields=["password", "is_active"])

        academic_year, _ = AcademicYear.objects.get_or_create(
            name="2025-2026",
            defaults={
                "start_date": date(2025, 9, 1),
                "end_date": date(2026, 7, 31),
                "is_active": True,
            },
        )

        class_6a, _ = ClassRoom.objects.get_or_create(
            name="6A",
            academic_year=academic_year,
        )

        math = self._get_or_create_subject_for_classroom(
            class_6a,
            "MATH",
            "Mathématiques",
            Decimal("4"),
        )
        french = self._get_or_create_subject_for_classroom(
            class_6a,
            "FR",
            "Français",
            Decimal("3"),
        )
        english = self._get_or_create_subject_for_classroom(
            class_6a,
            "EN",
            "Anglais",
            Decimal("2"),
        )

        teacher, _ = Teacher.objects.get_or_create(
            user=teacher_user,
            defaults={
                "employee_code": "TCH-0001",
                "hire_date": today - timedelta(days=365),
                "salary_base": Decimal("350000"),
            },
        )

        for subject in [math, french, english]:
            TeacherAssignment.objects.get_or_create(
                teacher=teacher,
                subject=subject,
                classroom=class_6a,
            )

        parent_profile, _ = ParentProfile.objects.get_or_create(
            user=parent_user,
            defaults={"profession": "Commerçante"},
        )

        student_1, _ = Student.objects.get_or_create(
            user=student_user_1,
            defaults={
                "birth_date": date(2012, 4, 8),
                "classroom": class_6a,
                "parent": parent_profile,
            },
        )
        student_2, _ = Student.objects.get_or_create(
            user=student_user_2,
            defaults={
                "birth_date": date(2011, 12, 18),
                "classroom": class_6a,
                "parent": parent_profile,
            },
        )

        for student in [student_1, student_2]:
            for subject, value in [(math, Decimal("14.5")), (french, Decimal("13.0")), (english, Decimal("15.0"))]:
                Grade.objects.get_or_create(
                    student=student,
                    subject=subject,
                    classroom=class_6a,
                    academic_year=academic_year,
                    term="T1",
                    defaults={"value": value if student == student_1 else value - Decimal("1.5")},
                )

        recalculate_term_ranking(class_6a, academic_year, "T1")

        for student in [student_1, student_2]:
            Attendance.objects.get_or_create(
                student=student,
                date=today - timedelta(days=3),
                    defaults={"is_absent": False, "is_late": True, "reason": "Retard"},
            )
            Attendance.objects.get_or_create(
                student=student,
                date=today - timedelta(days=1),
                defaults={"is_absent": True, "is_late": False, "reason": "Maladie"},
            )

        TeacherAttendance.objects.get_or_create(
            teacher=teacher,
            date=today - timedelta(days=5),
            defaults={"is_absent": True, "is_late": False, "reason": "Formation académique"},
        )
        TeacherAttendance.objects.get_or_create(
            teacher=teacher,
            date=today - timedelta(days=2),
            defaults={"is_absent": False, "is_late": True, "reason": "Retard exceptionnel"},
        )

        DisciplineIncident.objects.get_or_create(
            student=student_2,
            incident_date=today - timedelta(days=4),
            category="Indiscipline",
            defaults={
                "description": "Bavardage répété en classe malgré plusieurs rappels.",
                "severity": "medium",
                "sanction": "Avertissement écrit",
                "status": "open",
                "parent_notified": False,
                "reported_by": teacher_user,
            },
        )

        fee_1, _ = StudentFee.objects.get_or_create(
            student=student_1,
            academic_year=academic_year,
            fee_type=FeeType.MONTHLY,
            defaults={"amount_due": Decimal("85000"), "due_date": today + timedelta(days=15)},
        )
        fee_2, _ = StudentFee.objects.get_or_create(
            student=student_2,
            academic_year=academic_year,
            fee_type=FeeType.MONTHLY,
            defaults={"amount_due": Decimal("85000"), "due_date": today + timedelta(days=15)},
        )

        Payment.objects.get_or_create(
            fee=fee_1,
            reference="PAY-0001",
            defaults={"amount": Decimal("85000"), "method": "Mobile Money", "received_by": accountant_user},
        )
        Payment.objects.get_or_create(
            fee=fee_2,
            reference="PAY-0002",
            defaults={"amount": Decimal("50000"), "method": "Espèces", "received_by": accountant_user},
        )

        Expense.objects.get_or_create(
            label="Achat fournitures",
            amount=Decimal("120000"),
            date=today,
            category="Fournitures",
            defaults={"notes": "Cahiers et stylos"},
        )

        TeacherPayroll.objects.get_or_create(
            teacher=teacher,
            month=date(today.year, today.month, 1),
            defaults={
                "amount": Decimal("350000"),
                "paid_on": today,
                "paid_by": accountant_user,
            },
        )

        Announcement.objects.get_or_create(
            title="Réunion parents-professeurs",
            defaults={
                "message": "La réunion aura lieu vendredi à 15h.",
                "audience": "all",
                "author": director_user,
            },
        )

        Notification.objects.get_or_create(
            recipient=parent_user,
            channel=NotificationChannel.PUSH,
            title="Paiement reçu",
            defaults={"message": "Votre paiement a été enregistré.", "is_sent": False},
        )
        Notification.objects.get_or_create(
            recipient=parent_user,
            channel=NotificationChannel.EMAIL,
            title="Absence élève",
            defaults={"message": "Votre enfant était absent hier.", "is_sent": False},
        )

        SmsProviderConfig.objects.get_or_create(
            provider_name="Demo SMS",
            defaults={
                "api_url": "https://api.sms-provider.demo/send",
                "api_token": "replace-me",
                "sender_id": "GSCHOOL",
                "is_active": False,
            },
        )

        book, _ = Book.objects.get_or_create(
            isbn="978-2-1234-5678-9",
            defaults={
                "title": "Introduction aux Mathématiques",
                "author": "Auteur Démo",
                "quantity_total": 20,
                "quantity_available": 18,
            },
        )
        Borrow.objects.get_or_create(
            student=student_1,
            book=book,
            borrowed_at=today - timedelta(days=2),
            due_date=today + timedelta(days=10),
        )

        menu_1, _ = CanteenMenu.objects.get_or_create(
            menu_date=today,
            name="Riz sauce graine",
            defaults={
                "description": "Riz, sauce graine, poisson",
                "unit_price": Decimal("1200"),
                "is_active": True,
            },
        )
        menu_2, _ = CanteenMenu.objects.get_or_create(
            menu_date=today + timedelta(days=1),
            name="Spaghetti bolognaise",
            defaults={
                "description": "Spaghetti, viande hachée, jus",
                "unit_price": Decimal("1500"),
                "is_active": True,
            },
        )

        subscription_1, _ = CanteenSubscription.objects.get_or_create(
            student=student_1,
            academic_year=academic_year,
            defaults={
                "start_date": today - timedelta(days=30),
                "end_date": None,
                "daily_limit": 1,
                "status": "active",
            },
        )
        CanteenSubscription.objects.get_or_create(
            student=student_2,
            academic_year=academic_year,
            defaults={
                "start_date": today - timedelta(days=15),
                "end_date": None,
                "daily_limit": 1,
                "status": "active",
            },
        )

        CanteenService.objects.get_or_create(
            student=subscription_1.student,
            menu=menu_1,
            served_on=today,
            defaults={
                "quantity": 1,
                "is_paid": True,
                "notes": "Service midi",
            },
        )
        CanteenService.objects.get_or_create(
            student=student_2,
            menu=menu_2,
            served_on=today + timedelta(days=1),
            defaults={
                "quantity": 1,
                "is_paid": False,
                "notes": "À régler",
            },
        )

        exam_session, _ = ExamSession.objects.get_or_create(
            title="Examen Blanc T1",
            academic_year=academic_year,
            defaults={
                "start_date": today + timedelta(days=20),
                "end_date": today + timedelta(days=23),
            },
        )
        exam_planning, _ = ExamPlanning.objects.get_or_create(
            session=exam_session,
            classroom=class_6a,
            subject=math,
            exam_date=today + timedelta(days=20),
            defaults={"start_time": time(8, 0), "end_time": time(10, 0)},
        )
        ExamInvigilation.objects.get_or_create(
            planning=exam_planning,
            supervisor=supervisor_user,
        )
        ExamResult.objects.get_or_create(
            session=exam_session,
            student=student_1,
            subject=math,
            defaults={"score": Decimal("14.0")},
        )

        supplier, _ = Supplier.objects.get_or_create(
            name="Fournisseur Central",
            defaults={"phone": "+22501020304", "email": "contact@fournisseur.demo"},
        )
        stock_item, _ = StockItem.objects.get_or_create(
            name="Riz cantine",
            defaults={
                "quantity": 50,
                "minimum_threshold": 20,
                "unit": "kg",
                "supplier": supplier,
            },
        )

        StockMovement.objects.get_or_create(
            item=stock_item,
            movement_type=StockMovementType.IN,
            quantity=10,
            defaults={"reason": "Réapprovisionnement"},
        )

        self.stdout.write(self.style.SUCCESS("Seed terminé avec succès."))
        self.stdout.write(self.style.SUCCESS("Super admin -> username: superadmin / password: Admin@12345"))
