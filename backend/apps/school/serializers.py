from decimal import Decimal
from rest_framework import serializers
from .term_utils import normalize_term
from .models import (
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
    Grade,
    GradeValidation,
    Level,
    Notification,
    ParentProfile,
    Payment,
    Section,
    StockItem,
    StockMovement,
    Student,
    StudentAcademicHistory,
    StudentFee,
    Subject,
    Supplier,
    SmsProviderConfig,
    Teacher,
    TeacherAttendance,
    TeacherAssignment,
    TeacherScheduleSlot,
    TimetablePublication,
    TeacherPayroll,
)


class AcademicYearSerializer(serializers.ModelSerializer):
    class Meta:
        model = AcademicYear
        fields = "__all__"


class LevelSerializer(serializers.ModelSerializer):
    class Meta:
        model = Level
        fields = "__all__"


class SectionSerializer(serializers.ModelSerializer):
    class Meta:
        model = Section
        fields = "__all__"


class ClassRoomSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = ClassRoom
        fields = "__all__"


class SubjectSerializer(serializers.ModelSerializer):
    class Meta:
        model = Subject
        fields = "__all__"



class TeacherSerializer(serializers.ModelSerializer):
    user_full_name = serializers.SerializerMethodField(read_only=True)
    user_first_name = serializers.SerializerMethodField(read_only=True)
    user_last_name = serializers.SerializerMethodField(read_only=True)
    user_username = serializers.SerializerMethodField(read_only=True)
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    def get_user_full_name(self, obj):
        if not obj.user:
            return ""
        full_name = obj.user.get_full_name().strip()
        return full_name or obj.user.username

    def get_user_first_name(self, obj):
        return obj.user.first_name if obj.user else ""

    def get_user_last_name(self, obj):
        return obj.user.last_name if obj.user else ""

    def get_user_username(self, obj):
        return obj.user.username if obj.user else ""

    class Meta:
        model = Teacher
        fields = "__all__"


class TeacherAssignmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = TeacherAssignment
        fields = "__all__"


class TeacherScheduleSlotSerializer(serializers.ModelSerializer):
    classroom = serializers.SerializerMethodField(read_only=True)
    classroom_name = serializers.SerializerMethodField(read_only=True)
    subject_code = serializers.SerializerMethodField(read_only=True)
    teacher_code = serializers.SerializerMethodField(read_only=True)

    def get_classroom(self, obj):
        assignment = obj.assignment
        return assignment.classroom_id if assignment else None

    def get_classroom_name(self, obj):
        assignment = obj.assignment
        classroom = assignment.classroom if assignment else None
        return classroom.name if classroom else ""

    def get_subject_code(self, obj):
        assignment = obj.assignment
        subject = assignment.subject if assignment else None
        return subject.code if subject else ""

    def get_teacher_code(self, obj):
        assignment = obj.assignment
        teacher = assignment.teacher if assignment else None
        return teacher.employee_code if teacher else ""

    @staticmethod
    def _slot_label(slot):
        assignment = slot.assignment
        subject_code = assignment.subject.code if assignment and assignment.subject else "MAT"
        teacher_code = assignment.teacher.employee_code if assignment and assignment.teacher else "ENS"
        class_name = assignment.classroom.name if assignment and assignment.classroom else "Classe"
        room = slot.room.strip() if (slot.room or "").strip() else "-"
        return (
            f"{slot.get_day_of_week_display()} "
            f"{slot.start_time.strftime('%H:%M')}-{slot.end_time.strftime('%H:%M')} "
            f"| Classe {class_name} | {subject_code}/{teacher_code} | Salle {room}"
        )

    @staticmethod
    def _overlap_queryset(day_of_week, start_time, end_time):
        return TeacherScheduleSlot.objects.select_related(
            "assignment",
            "assignment__teacher",
            "assignment__subject",
            "assignment__classroom",
        ).filter(
            day_of_week=day_of_week,
            start_time__lt=end_time,
            end_time__gt=start_time,
        )

    @staticmethod
    def _check_locked_classroom(assignment):
        if not assignment:
            return
        publication = TimetablePublication.objects.filter(
            classroom=assignment.classroom,
            is_locked=True,
        ).first()
        if publication:
            raise serializers.ValidationError(
                {
                    "non_field_errors": [
                        "Emploi du temps verrouillé pour cette classe. "
                        "Déverrouillez avant toute modification.",
                    ]
                }
            )

    def validate(self, attrs):
        assignment = attrs.get("assignment") or getattr(self.instance, "assignment", None)
        day_of_week = attrs.get("day_of_week") or getattr(self.instance, "day_of_week", None)
        start_time = attrs.get("start_time") or getattr(self.instance, "start_time", None)
        end_time = attrs.get("end_time") or getattr(self.instance, "end_time", None)
        room = attrs.get("room")
        if room is None and self.instance is not None:
            room = self.instance.room

        if not assignment or not day_of_week or not start_time or not end_time:
            return attrs

        if end_time <= start_time:
            raise serializers.ValidationError(
                {"end_time": "L'heure de fin doit être après l'heure de début."}
            )

        self._check_locked_classroom(assignment)

        overlaps = self._overlap_queryset(day_of_week, start_time, end_time)
        if self.instance:
            overlaps = overlaps.exclude(pk=self.instance.pk)

        class_conflicts = overlaps.filter(assignment__classroom=assignment.classroom)
        teacher_conflicts = overlaps.filter(assignment__teacher=assignment.teacher)

        room_conflicts = TeacherScheduleSlot.objects.none()
        room_value = (room or "").strip()
        if room_value:
            room_conflicts = overlaps.exclude(room__exact="").filter(room__iexact=room_value)

        errors = []

        if class_conflicts.exists():
            errors.append("Conflit de classe: un autre cours est déjà planifié sur ce créneau.")
            for slot in class_conflicts[:3]:
                errors.append(f"Classe: {self._slot_label(slot)}")

        if teacher_conflicts.exists():
            errors.append("Conflit enseignant: cet enseignant est déjà occupé sur ce créneau.")
            for slot in teacher_conflicts[:3]:
                errors.append(f"Enseignant: {self._slot_label(slot)}")

        if room_conflicts.exists():
            errors.append("Conflit de salle: la salle est déjà utilisée sur ce créneau.")
            for slot in room_conflicts[:3]:
                errors.append(f"Salle: {self._slot_label(slot)}")

        if errors:
            raise serializers.ValidationError({"non_field_errors": errors})

        return attrs

    class Meta:
        model = TeacherScheduleSlot
        fields = "__all__"


class TimetablePublicationSerializer(serializers.ModelSerializer):
    classroom_name = serializers.SerializerMethodField(read_only=True)
    published_by_name = serializers.SerializerMethodField(read_only=True)

    def get_classroom_name(self, obj):
        classroom = obj.classroom
        return classroom.name if classroom else ""

    def get_published_by_name(self, obj):
        user = obj.published_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    class Meta:
        model = TimetablePublication
        fields = "__all__"


class ParentProfileSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = ParentProfile
        fields = "__all__"


class StudentSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)
    user_full_name = serializers.SerializerMethodField(read_only=True)
    user_username = serializers.SerializerMethodField(read_only=True)
    user_first_name = serializers.SerializerMethodField(read_only=True)
    user_last_name = serializers.SerializerMethodField(read_only=True)
    user_email = serializers.SerializerMethodField(read_only=True)
    user_phone = serializers.SerializerMethodField(read_only=True)
    classroom_name = serializers.SerializerMethodField(read_only=True)
    parent_name = serializers.SerializerMethodField(read_only=True)
    parent_phone = serializers.SerializerMethodField(read_only=True)

    def get_user_full_name(self, obj):
        full_name = obj.user.get_full_name().strip() if obj.user else ""
        return full_name or obj.user.username

    def get_user_username(self, obj):
        return obj.user.username if obj.user else ""

    def get_user_first_name(self, obj):
        return obj.user.first_name if obj.user else ""

    def get_user_last_name(self, obj):
        return obj.user.last_name if obj.user else ""

    def get_user_email(self, obj):
        return obj.user.email if obj.user else ""

    def get_user_phone(self, obj):
        return obj.user.phone if obj.user else ""

    def get_classroom_name(self, obj):
        return obj.classroom.name if obj.classroom else ""

    def get_parent_name(self, obj):
        parent = obj.parent
        user = parent.user if parent else None
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def get_parent_phone(self, obj):
        parent = obj.parent
        user = parent.user if parent else None
        return user.phone if user else ""

    class Meta:
        model = Student
        fields = "__all__"


class StudentAcademicHistorySerializer(serializers.ModelSerializer):
    def validate(self, attrs):
        student = attrs.get("student") or getattr(self.instance, "student", None)
        academic_year = attrs.get("academic_year") or getattr(self.instance, "academic_year", None)
        classroom = attrs.get("classroom") or getattr(self.instance, "classroom", None)

        if student and academic_year and classroom:
            queryset = StudentAcademicHistory.objects.filter(
                student=student,
                academic_year=academic_year,
                classroom=classroom,
            )
            if self.instance:
                queryset = queryset.exclude(pk=self.instance.pk)
            if queryset.exists():
                raise serializers.ValidationError(
                    "Un historique existe déjà pour cet élève, cette année et cette classe."
                )
        return attrs

    class Meta:
        model = StudentAcademicHistory
        fields = "__all__"


class GradeSerializer(serializers.ModelSerializer):
    TERM_ERROR_MESSAGE = "Période invalide. Utilisez uniquement T1, T2 ou T3."

    def validate_term(self, value):
        normalized = normalize_term(value)
        if not normalized:
            raise serializers.ValidationError(self.TERM_ERROR_MESSAGE)
        return normalized

    def validate_value(self, value):
        numeric_value = Decimal(str(value))
        if numeric_value < Decimal("0") or numeric_value > Decimal("20"):
            raise serializers.ValidationError("La note doit être comprise entre 0 et 20.")
        return value

    def validate(self, attrs):
        attrs = super().validate(attrs)

        student = attrs.get("student") or getattr(self.instance, "student", None)
        classroom = attrs.get("classroom") or getattr(self.instance, "classroom", None)
        subject = attrs.get("subject") or getattr(self.instance, "subject", None)
        academic_year = attrs.get("academic_year") or getattr(self.instance, "academic_year", None)

        if student and classroom and student.classroom_id != classroom.id:
            raise serializers.ValidationError(
                {"student": "L'élève sélectionné n'appartient pas à la classe choisie."}
            )

        if classroom and academic_year and classroom.academic_year_id != academic_year.id:
            raise serializers.ValidationError(
                {
                    "academic_year": (
                        "L'année scolaire doit correspondre à l'année de la classe sélectionnée."
                    )
                }
            )

        if classroom and subject and not TeacherAssignment.objects.filter(
            classroom=classroom,
            subject=subject,
        ).exists():
            raise serializers.ValidationError(
                {"subject": "Cette matière n'est pas attribuée à la classe sélectionnée."}
            )

        return attrs

    class Meta:
        model = Grade
        fields = "__all__"


class GradeValidationSerializer(serializers.ModelSerializer):
    validated_by_name = serializers.SerializerMethodField(read_only=True)

    def get_validated_by_name(self, obj):
        user = obj.validated_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def validate_term(self, value):
        normalized = normalize_term(value)
        if not normalized:
            raise serializers.ValidationError("Période invalide. Utilisez uniquement T1, T2 ou T3.")
        return normalized

    class Meta:
        model = GradeValidation
        fields = "__all__"


class AttendanceSerializer(serializers.ModelSerializer):
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)

    def get_student_full_name(self, obj):
        student = obj.student
        user = student.user if student else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_student_matricule(self, obj):
        return obj.student.matricule if obj.student else ""

    def validate(self, attrs):
        student = attrs.get("student") or getattr(self.instance, "student", None)
        attendance_date = attrs.get("date") or getattr(self.instance, "date", None)

        if student and attendance_date:
            queryset = Attendance.objects.filter(student=student, date=attendance_date)
            if self.instance:
                queryset = queryset.exclude(pk=self.instance.pk)
            if queryset.exists():
                raise serializers.ValidationError(
                    "Une présence existe déjà pour cet élève à cette date."
                )

        return attrs

    class Meta:
        model = Attendance
        fields = "__all__"


class TeacherAttendanceSerializer(serializers.ModelSerializer):
    teacher_full_name = serializers.SerializerMethodField(read_only=True)
    teacher_employee_code = serializers.SerializerMethodField(read_only=True)

    def get_teacher_full_name(self, obj):
        teacher = obj.teacher
        user = teacher.user if teacher else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_teacher_employee_code(self, obj):
        return obj.teacher.employee_code if obj.teacher else ""

    class Meta:
        model = TeacherAttendance
        fields = "__all__"


class DisciplineIncidentSerializer(serializers.ModelSerializer):
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)

    def get_student_full_name(self, obj):
        student = obj.student
        user = student.user if student else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_student_matricule(self, obj):
        return obj.student.matricule if obj.student else ""

    class Meta:
        model = DisciplineIncident
        fields = "__all__"


class StudentFeeSerializer(serializers.ModelSerializer):
    amount_paid = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    balance = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)

    def get_student_full_name(self, obj):
        full_name = obj.student.user.get_full_name().strip() if obj.student and obj.student.user else ""
        if full_name:
            return full_name
        return obj.student.user.username if obj.student and obj.student.user else ""

    def get_student_matricule(self, obj):
        return obj.student.matricule if obj.student else ""

    def validate_amount_due(self, value):
        if value <= 0:
            raise serializers.ValidationError("Le montant dû doit être supérieur à 0.")
        return value

    class Meta:
        model = StudentFee
        fields = "__all__"


class PaymentSerializer(serializers.ModelSerializer):
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)
    fee_type = serializers.SerializerMethodField(read_only=True)

    def get_student_full_name(self, obj):
        student = obj.fee.student if obj.fee else None
        user = student.user if student else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_student_matricule(self, obj):
        student = obj.fee.student if obj.fee else None
        return student.matricule if student else ""

    def get_fee_type(self, obj):
        return obj.fee.get_fee_type_display() if obj.fee else ""

    def validate(self, attrs):
        fee = attrs.get("fee") or getattr(self.instance, "fee", None)
        amount = attrs.get("amount")

        if amount is None and self.instance is not None:
            amount = self.instance.amount

        if fee is None or amount is None:
            return attrs

        if amount <= 0:
            raise serializers.ValidationError("Le montant du paiement doit être supérieur à 0.")

        existing_amount = Decimal("0")
        if self.instance is not None and self.instance.fee_id == fee.id:
            existing_amount = self.instance.amount or Decimal("0")

        if amount > (fee.balance + existing_amount):
            raise serializers.ValidationError("Le montant dépasse le solde restant du frais.")

        return attrs

    class Meta:
        model = Payment
        fields = "__all__"


class ExpenseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Expense
        fields = "__all__"


class TeacherPayrollSerializer(serializers.ModelSerializer):
    class Meta:
        model = TeacherPayroll
        fields = "__all__"


class AnnouncementSerializer(serializers.ModelSerializer):
    class Meta:
        model = Announcement
        fields = "__all__"


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = "__all__"


class SmsProviderConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = SmsProviderConfig
        fields = "__all__"


class BookSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)
    class Meta:
        model = Book
        fields = "__all__"


class BorrowSerializer(serializers.ModelSerializer):
    class Meta:
        model = Borrow
        fields = "__all__"


class CanteenMenuSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)
    class Meta:
        model = CanteenMenu
        fields = "__all__"


class CanteenSubscriptionSerializer(serializers.ModelSerializer):
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)

    def get_student_full_name(self, obj):
        student = obj.student
        user = student.user if student else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_student_matricule(self, obj):
        return obj.student.matricule if obj.student else ""

    class Meta:
        model = CanteenSubscription
        fields = "__all__"


class CanteenServiceSerializer(serializers.ModelSerializer):
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)

    def get_student_full_name(self, obj):
        student = obj.student
        user = student.user if student else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_student_matricule(self, obj):
        return obj.student.matricule if obj.student else ""

    class Meta:
        model = CanteenService
        fields = "__all__"


class ExamSessionSerializer(serializers.ModelSerializer):
    def validate_term(self, value):
        normalized = normalize_term(value)
        if not normalized:
            raise serializers.ValidationError("Période invalide. Utilisez uniquement T1, T2 ou T3.")
        return normalized

    class Meta:
        model = ExamSession
        fields = "__all__"


class ExamPlanningSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExamPlanning
        fields = "__all__"


class ExamInvigilationSerializer(serializers.ModelSerializer):
    supervisor_full_name = serializers.SerializerMethodField(read_only=True)
    supervisor_username = serializers.SerializerMethodField(read_only=True)

    def get_supervisor_full_name(self, obj):
        user = obj.supervisor
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_supervisor_username(self, obj):
        return obj.supervisor.username if obj.supervisor else ""

    class Meta:
        model = ExamInvigilation
        fields = "__all__"


class ExamResultSerializer(serializers.ModelSerializer):
    class Meta:
        model = ExamResult
        fields = "__all__"


class SupplierSerializer(serializers.ModelSerializer):
    class Meta:
        model = Supplier
        fields = "__all__"


class StockItemSerializer(serializers.ModelSerializer):
    is_low_stock = serializers.BooleanField(read_only=True)

    class Meta:
        model = StockItem
        fields = "__all__"


class StockMovementSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockMovement
        fields = "__all__"
