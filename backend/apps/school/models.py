from datetime import date
from decimal import Decimal
from django.conf import settings
from django.db import models
from django.db.models import Avg
from apps.common.models import TimeStampedModel


class AcademicYear(TimeStampedModel):
    name = models.CharField(max_length=20, unique=True)
    start_date = models.DateField()
    end_date = models.DateField()
    is_active = models.BooleanField(default=False)

    def __str__(self):
        return self.name


class Level(TimeStampedModel):
    name = models.CharField(max_length=100, unique=True)

    def __str__(self):
        return self.name


class Section(TimeStampedModel):
    name = models.CharField(max_length=100, unique=True)

    def __str__(self):
        return self.name


class ClassRoom(TimeStampedModel):
    name = models.CharField(max_length=50)
    level = models.ForeignKey(Level, on_delete=models.PROTECT, related_name="classes")
    section = models.ForeignKey(Section, on_delete=models.PROTECT, related_name="classes")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="classes")

    class Meta:
        unique_together = ("name", "level", "section", "academic_year")

    def __str__(self):
        return f"{self.name} - {self.academic_year}"


class Subject(TimeStampedModel):
    name = models.CharField(max_length=100)
    code = models.CharField(max_length=20, unique=True)
    coefficient = models.DecimalField(max_digits=4, decimal_places=2, default=1)

    def __str__(self):
        return f"{self.code} - {self.name}"


class Teacher(TimeStampedModel):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="teacher_profile")
    employee_code = models.CharField(max_length=30, unique=True)
    hire_date = models.DateField()
    salary_base = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    def __str__(self):
        return self.user.get_full_name() or self.user.username


class TeacherAssignment(TimeStampedModel):
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="assignments")
    subject = models.ForeignKey(Subject, on_delete=models.PROTECT, related_name="teacher_assignments")
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT, related_name="teacher_assignments")

    class Meta:
        unique_together = ("teacher", "subject", "classroom")


class ParentProfile(TimeStampedModel):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="parent_profile")
    profession = models.CharField(max_length=120, blank=True)

    def __str__(self):
        return self.user.get_full_name() or self.user.username


class Student(TimeStampedModel):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="student_profile")
    matricule = models.CharField(max_length=30, unique=True, blank=True)
    birth_date = models.DateField(null=True, blank=True)
    classroom = models.ForeignKey(ClassRoom, on_delete=models.SET_NULL, null=True, related_name="students")
    parent = models.ForeignKey(ParentProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name="children")
    photo = models.ImageField(upload_to="students/", null=True, blank=True)
    enrollment_date = models.DateField(auto_now_add=True)
    is_archived = models.BooleanField(default=False)

    def save(self, *args, **kwargs):
        if not self.matricule:
            year = self.enrollment_date.year if self.enrollment_date else date.today().year
            prefix = f"GS-{year}"
            last_student = Student.objects.filter(matricule__startswith=prefix).order_by("-id").first()
            next_number = 1
            if last_student and last_student.matricule:
                try:
                    next_number = int(last_student.matricule.split("-")[-1]) + 1
                except (ValueError, IndexError):
                    next_number = last_student.id + 1
            self.matricule = f"{prefix}-{next_number:05d}"
        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.matricule} - {self.user.get_full_name()}"


class StudentAcademicHistory(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="history")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT)
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT)
    average = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    rank = models.PositiveIntegerField(default=0)


class Grade(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="grades")
    subject = models.ForeignKey(Subject, on_delete=models.PROTECT, related_name="grades")
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT, related_name="grades")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="grades")
    term = models.CharField(max_length=20)
    value = models.DecimalField(max_digits=5, decimal_places=2)

    class Meta:
        unique_together = ("student", "subject", "classroom", "academic_year", "term")


class GradeValidation(TimeStampedModel):
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT, related_name="grade_validations")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="grade_validations")
    term = models.CharField(max_length=20)
    is_validated = models.BooleanField(default=False)
    validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="validated_grade_terms",
    )
    validated_at = models.DateTimeField(null=True, blank=True)
    notes = models.CharField(max_length=255, blank=True)

    class Meta:
        unique_together = ("classroom", "academic_year", "term")


class Attendance(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="attendances")
    date = models.DateField()
    is_absent = models.BooleanField(default=False)
    is_late = models.BooleanField(default=False)
    reason = models.CharField(max_length=255, blank=True)
    proof = models.FileField(upload_to="attendance_proofs/", null=True, blank=True)


class TeacherAttendance(TimeStampedModel):
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="attendances")
    date = models.DateField()
    is_absent = models.BooleanField(default=False)
    is_late = models.BooleanField(default=False)
    reason = models.CharField(max_length=255, blank=True)
    proof = models.FileField(upload_to="teacher_attendance_proofs/", null=True, blank=True)


class DisciplineSeverity(models.TextChoices):
    LOW = "low", "Faible"
    MEDIUM = "medium", "Moyenne"
    HIGH = "high", "Élevée"


class DisciplineStatus(models.TextChoices):
    OPEN = "open", "Ouvert"
    RESOLVED = "resolved", "Traité"


class DisciplineIncident(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="discipline_incidents")
    incident_date = models.DateField()
    category = models.CharField(max_length=120)
    description = models.TextField()
    severity = models.CharField(max_length=10, choices=DisciplineSeverity.choices, default=DisciplineSeverity.MEDIUM)
    sanction = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=DisciplineStatus.choices, default=DisciplineStatus.OPEN)
    parent_notified = models.BooleanField(default=False)
    reported_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="discipline_reports",
    )


class FeeType(models.TextChoices):
    REGISTRATION = "registration", "Frais inscription"
    MONTHLY = "monthly", "Frais mensuels"
    EXAM = "exam", "Frais examen"


class StudentFee(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="fees")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="fees")
    fee_type = models.CharField(max_length=20, choices=FeeType.choices)
    amount_due = models.DecimalField(max_digits=12, decimal_places=2)
    due_date = models.DateField()

    @property
    def amount_paid(self):
        total = self.payments.aggregate(total=models.Sum("amount"))["total"]
        return total or Decimal("0.00")

    @property
    def balance(self):
        return self.amount_due - self.amount_paid


class Payment(TimeStampedModel):
    fee = models.ForeignKey(StudentFee, on_delete=models.CASCADE, related_name="payments")
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    method = models.CharField(max_length=50)
    reference = models.CharField(max_length=100, blank=True)
    received_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="received_payments")


class Expense(TimeStampedModel):
    label = models.CharField(max_length=120)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    date = models.DateField()
    category = models.CharField(max_length=100)
    notes = models.TextField(blank=True)


class TeacherPayroll(TimeStampedModel):
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="payrolls")
    month = models.DateField()
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    paid_on = models.DateField()
    paid_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)


class Announcement(TimeStampedModel):
    title = models.CharField(max_length=150)
    message = models.TextField()
    audience = models.CharField(max_length=50, default="all")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)


class NotificationChannel(models.TextChoices):
    PUSH = "push", "Push"
    EMAIL = "email", "Email"
    SMS = "sms", "SMS"


class Notification(TimeStampedModel):
    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    channel = models.CharField(max_length=10, choices=NotificationChannel.choices)
    title = models.CharField(max_length=150)
    message = models.TextField()
    is_sent = models.BooleanField(default=False)
    sent_at = models.DateTimeField(null=True, blank=True)


class SmsProviderConfig(TimeStampedModel):
    provider_name = models.CharField(max_length=100)
    api_url = models.URLField()
    api_token = models.CharField(max_length=255)
    sender_id = models.CharField(max_length=50, blank=True)
    is_active = models.BooleanField(default=False)


class Book(TimeStampedModel):
    title = models.CharField(max_length=150)
    author = models.CharField(max_length=120)
    isbn = models.CharField(max_length=30, unique=True)
    quantity_total = models.PositiveIntegerField(default=0)
    quantity_available = models.PositiveIntegerField(default=0)


class Borrow(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="borrows")
    book = models.ForeignKey(Book, on_delete=models.PROTECT, related_name="borrows")
    borrowed_at = models.DateField()
    due_date = models.DateField()
    returned_at = models.DateField(null=True, blank=True)
    penalty_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)


class CanteenMenu(TimeStampedModel):
    menu_date = models.DateField()
    name = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    unit_price = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    is_active = models.BooleanField(default=True)


class CanteenSubscriptionStatus(models.TextChoices):
    ACTIVE = "active", "Actif"
    SUSPENDED = "suspended", "Suspendu"
    ENDED = "ended", "Terminé"


class CanteenSubscription(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="canteen_subscriptions")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="canteen_subscriptions")
    start_date = models.DateField()
    end_date = models.DateField(null=True, blank=True)
    daily_limit = models.PositiveIntegerField(default=1)
    status = models.CharField(max_length=15, choices=CanteenSubscriptionStatus.choices, default=CanteenSubscriptionStatus.ACTIVE)


class CanteenService(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="canteen_services")
    menu = models.ForeignKey(CanteenMenu, on_delete=models.PROTECT, related_name="services")
    served_on = models.DateField()
    quantity = models.PositiveIntegerField(default=1)
    is_paid = models.BooleanField(default=False)
    notes = models.CharField(max_length=255, blank=True)

class ExamSession(TimeStampedModel):
    title = models.CharField(max_length=100)
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="exam_sessions")
    start_date = models.DateField()
    end_date = models.DateField()


class ExamPlanning(TimeStampedModel):
    session = models.ForeignKey(ExamSession, on_delete=models.CASCADE, related_name="plannings")
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT)
    subject = models.ForeignKey(Subject, on_delete=models.PROTECT)
    exam_date = models.DateField()
    start_time = models.TimeField()
    end_time = models.TimeField()


class ExamInvigilation(TimeStampedModel):
    planning = models.ForeignKey(ExamPlanning, on_delete=models.CASCADE, related_name="invigilations")
    supervisor = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="exam_invigilations")

    class Meta:
        unique_together = ("planning", "supervisor")


class ExamResult(TimeStampedModel):
    session = models.ForeignKey(ExamSession, on_delete=models.CASCADE, related_name="results")
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="exam_results")
    subject = models.ForeignKey(Subject, on_delete=models.PROTECT)
    score = models.DecimalField(max_digits=5, decimal_places=2)


class Supplier(TimeStampedModel):
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=30, blank=True)
    email = models.EmailField(blank=True)


class StockItem(TimeStampedModel):
    name = models.CharField(max_length=120)
    quantity = models.IntegerField(default=0)
    minimum_threshold = models.IntegerField(default=5)
    unit = models.CharField(max_length=20, default="pcs")
    supplier = models.ForeignKey(Supplier, on_delete=models.SET_NULL, null=True, blank=True)

    @property
    def is_low_stock(self):
        return self.quantity <= self.minimum_threshold


class StockMovementType(models.TextChoices):
    IN = "in", "Entrée"
    OUT = "out", "Sortie"


class StockMovement(TimeStampedModel):
    item = models.ForeignKey(StockItem, on_delete=models.CASCADE, related_name="movements")
    movement_type = models.CharField(max_length=3, choices=StockMovementType.choices)
    quantity = models.PositiveIntegerField()
    reason = models.CharField(max_length=150, blank=True)

    def save(self, *args, **kwargs):
        if self._state.adding:
            if self.movement_type == StockMovementType.IN:
                self.item.quantity += self.quantity
            else:
                self.item.quantity -= self.quantity
            self.item.save(update_fields=["quantity", "updated_at"])
        super().save(*args, **kwargs)


def recalculate_term_ranking(classroom: ClassRoom, academic_year: AcademicYear, term: str):
    students = Student.objects.filter(classroom=classroom, is_archived=False)
    student_averages = []
    for student in students:
        avg = Grade.objects.filter(
            student=student,
            classroom=classroom,
            academic_year=academic_year,
            term=term,
        ).aggregate(value=Avg("value"))["value"] or Decimal("0")
        student_averages.append((student, Decimal(str(avg))))

    sorted_students = sorted(student_averages, key=lambda row: row[1], reverse=True)
    for index, (student, average) in enumerate(sorted_students, start=1):
        StudentAcademicHistory.objects.update_or_create(
            student=student,
            academic_year=academic_year,
            classroom=classroom,
            defaults={"average": average, "rank": index},
        )
