from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count, F

from apps.accounts.models import UserRole
from apps.school.models import (
    AcademicYear,
    Book,
    Borrow,
    CanteenMenu,
    CanteenService,
    ClassRoom,
    ExamInvigilation,
    ExamPlanning,
    Expense,
    Grade,
    GradeValidation,
    Level,
    ParentProfile,
    Payment,
    Section,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
    TimetablePublication,
)


class Command(BaseCommand):
    help = (
        "Delete records not linked to an etablissement and cleanup orphaned school data "
        "(classes, students, teachers, parents, grades, levels, sections, years, subjects)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show counts without persisting deletions.",
        )

    @transaction.atomic
    def handle(self, *args, **options):
        dry_run = bool(options.get("dry_run"))
        User = get_user_model()

        summary = {}

        # 1) Remove explicit records with null etablissement FKs.
        summary["payment_null_etab"] = Payment.objects.filter(etablissement__isnull=True).delete()[0]
        summary["expense_null_etab"] = Expense.objects.filter(etablissement__isnull=True).delete()[0]
        null_book_ids = list(Book.objects.filter(etablissement__isnull=True).values_list("id", flat=True))
        summary["borrow_null_book_etab"] = Borrow.objects.filter(book_id__in=null_book_ids).delete()[0]
        summary["book_null_etab"] = Book.objects.filter(etablissement__isnull=True).delete()[0]

        # Canteen menu is protected by services, remove services first.
        null_menu_ids = list(CanteenMenu.objects.filter(etablissement__isnull=True).values_list("id", flat=True))
        summary["canteen_service_null_menu_etab"] = CanteenService.objects.filter(
            menu_id__in=null_menu_ids
        ).delete()[0]
        summary["canteen_menu_null_etab"] = CanteenMenu.objects.filter(etablissement__isnull=True).delete()[0]

        # Profiles with no etablissement: delete profile + owning users.
        null_parent_user_ids = list(
            ParentProfile.objects.filter(etablissement__isnull=True).values_list("user_id", flat=True)
        )
        summary["parent_null_etab"] = ParentProfile.objects.filter(etablissement__isnull=True).delete()[0]
        summary["parent_users_deleted"] = User.objects.filter(id__in=null_parent_user_ids).delete()[0]

        null_teacher_user_ids = list(
            Teacher.objects.filter(etablissement__isnull=True).values_list("user_id", flat=True)
        )
        summary["teacher_null_etab"] = Teacher.objects.filter(etablissement__isnull=True).delete()[0]
        summary["teacher_users_deleted"] = User.objects.filter(id__in=null_teacher_user_ids).delete()[0]

        null_student_user_ids = list(
            Student.objects.filter(etablissement__isnull=True).values_list("user_id", flat=True)
        )
        summary["student_null_etab"] = Student.objects.filter(etablissement__isnull=True).delete()[0]
        summary["student_users_deleted"] = User.objects.filter(id__in=null_student_user_ids).delete()[0]

        # 2) Cleanup class-related data where class has no etablissement.
        class_ids_null_etab = list(
            ClassRoom.objects.filter(etablissement__isnull=True).values_list("id", flat=True)
        )

        if class_ids_null_etab:
            planning_ids = list(ExamPlanning.objects.filter(classroom_id__in=class_ids_null_etab).values_list("id", flat=True))
            summary["exam_invigilation_null_class_etab"] = ExamInvigilation.objects.filter(
                planning_id__in=planning_ids
            ).delete()[0]
            summary["exam_planning_null_class_etab"] = ExamPlanning.objects.filter(
                id__in=planning_ids
            ).delete()[0]

            summary["grade_null_class_etab"] = Grade.objects.filter(classroom_id__in=class_ids_null_etab).delete()[0]
            summary["grade_validation_null_class_etab"] = GradeValidation.objects.filter(
                classroom_id__in=class_ids_null_etab
            ).delete()[0]
            summary["teacher_schedule_null_class_etab"] = TeacherScheduleSlot.objects.filter(
                assignment__classroom_id__in=class_ids_null_etab
            ).delete()[0]
            summary["teacher_assignment_null_class_etab"] = TeacherAssignment.objects.filter(
                classroom_id__in=class_ids_null_etab
            ).delete()[0]
            summary["timetable_pub_null_class_etab"] = TimetablePublication.objects.filter(
                classroom_id__in=class_ids_null_etab
            ).delete()[0]

            student_user_ids_from_null_classes = list(
                Student.objects.filter(classroom_id__in=class_ids_null_etab).values_list("user_id", flat=True)
            )
            summary["student_null_class_etab"] = Student.objects.filter(
                classroom_id__in=class_ids_null_etab
            ).delete()[0]
            summary["student_users_null_class_deleted"] = User.objects.filter(
                id__in=student_user_ids_from_null_classes
            ).delete()[0]

            summary["class_null_etab"] = ClassRoom.objects.filter(id__in=class_ids_null_etab).delete()[0]
        else:
            summary["exam_invigilation_null_class_etab"] = 0
            summary["exam_planning_null_class_etab"] = 0
            summary["grade_null_class_etab"] = 0
            summary["grade_validation_null_class_etab"] = 0
            summary["teacher_schedule_null_class_etab"] = 0
            summary["teacher_assignment_null_class_etab"] = 0
            summary["timetable_pub_null_class_etab"] = 0
            summary["student_null_class_etab"] = 0
            summary["student_users_null_class_deleted"] = 0
            summary["class_null_etab"] = 0

        # 3) Remove users (except super_admin) still not linked to etablissement.
        summary["users_null_etab_non_super_admin"] = User.objects.exclude(
            role=UserRole.SUPER_ADMIN
        ).filter(etablissement__isnull=True).delete()[0]

        # 4) Remove school dictionaries that are no longer used by etablissement-linked classes/data.
        summary["subject_orphan"] = Subject.objects.annotate(
            assignments_count=Count("teacher_assignments"),
            grades_count=Count("grades"),
        ).filter(assignments_count=0, grades_count=0).delete()[0]

        summary["academic_year_orphan"] = AcademicYear.objects.annotate(
            class_count=Count("classes"),
            grade_count=Count("grades"),
            grade_validation_count=Count("grade_validations"),
        ).filter(class_count=0, grade_count=0, grade_validation_count=0).delete()[0]

        summary["level_orphan"] = Level.objects.annotate(class_count=Count("classes")).filter(
            class_count=0
        ).delete()[0]

        summary["section_orphan"] = Section.objects.annotate(class_count=Count("classes")).filter(
            class_count=0
        ).delete()[0]

        # 5) Defensive pass: students whose classroom has a different etablissement.
        mismatch_student_user_ids = list(
            Student.objects.filter(
                classroom__isnull=False
            ).exclude(
                classroom__etablissement_id=None
            ).exclude(
                etablissement_id=None
            ).exclude(
                classroom__etablissement_id=F("etablissement_id")
            ).values_list("user_id", flat=True)
        )

        summary["student_etab_mismatch"] = Student.objects.filter(
            classroom__isnull=False
        ).exclude(
            classroom__etablissement_id=None
        ).exclude(
            etablissement_id=None
        ).exclude(
            classroom__etablissement_id=F("etablissement_id")
        ).delete()[0]

        summary["student_users_etab_mismatch_deleted"] = User.objects.filter(
            id__in=mismatch_student_user_ids
        ).delete()[0]

        if dry_run:
            transaction.set_rollback(True)
            self.stdout.write(self.style.WARNING("Dry-run: rollback applied, no data deleted."))

        self.stdout.write(self.style.SUCCESS("Cleanup complete."))
        for key in sorted(summary.keys()):
            self.stdout.write(f"{key}: {summary[key]}")
