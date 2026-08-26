
from datetime import date, datetime, time, timedelta
from decimal import Decimal, ROUND_HALF_UP
import re

from django.conf import settings
from django.db import models
from django.core.validators import MinValueValidator, MaxValueValidator
from django.utils import timezone
from apps.common.models import TimeStampedModel


# Nouveau modèle pour la gestion multi-établissements
class Etablissement(TimeStampedModel):
    POSITION_LEFT = "left"
    POSITION_CENTER = "center"
    POSITION_RIGHT = "right"
    POSITION_CHOICES = [
        (POSITION_LEFT, "Gauche"),
        (POSITION_CENTER, "Centre"),
        (POSITION_RIGHT, "Droite"),
    ]

    name = models.CharField(max_length=255, unique=True)
    address = models.CharField(max_length=255, blank=True)
    phone = models.CharField(max_length=30, blank=True)
    email = models.EmailField(blank=True)
    logo = models.ImageField(upload_to="etablissements/logos/", blank=True, null=True)
    stamp_image = models.ImageField(upload_to="etablissements/stamps/", blank=True, null=True)
    principal_signature_image = models.ImageField(upload_to="etablissements/signatures/", blank=True, null=True)
    cashier_signature_image = models.ImageField(upload_to="etablissements/signatures/", blank=True, null=True)
    principal_signature_label = models.CharField(max_length=120, blank=True, default="Le Principal")
    cashier_signature_label = models.CharField(max_length=120, blank=True, default="Signature caissier")
    parent_signature_label = models.CharField(max_length=120, blank=True, default="Signature parent / eleve")
    principal_signature_position = models.CharField(
        max_length=10,
        choices=POSITION_CHOICES,
        default=POSITION_RIGHT,
    )
    stamp_position = models.CharField(
        max_length=10,
        choices=POSITION_CHOICES,
        default=POSITION_RIGHT,
    )
    principal_signature_scale = models.PositiveSmallIntegerField(
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(200)],
    )
    stamp_scale = models.PositiveSmallIntegerField(
        default=100,
        validators=[MinValueValidator(40), MaxValueValidator(200)],
    )
    # Penalite de retard appliquee a un emprunt rendu hors delai, par jour
    # entame. Zero par defaut: c'est le comportement d'avant, ou la penalite
    # etait saisie a la main -- une ecole qui n'en applique pas ne doit pas
    # en voir apparaitre le jour de la mise a jour.
    library_penalty_per_day = models.DecimalField(
        max_digits=10, decimal_places=2, default=0
    )

    def __str__(self):
        return self.name


class AcademicYear(TimeStampedModel):
    name = models.CharField(max_length=20, unique=True)
    start_date = models.DateField()
    end_date = models.DateField()
    is_active = models.BooleanField(default=False)

    def __str__(self):
        return self.name


class ClassRoom(TimeStampedModel):
    name = models.CharField(max_length=50)
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="classes")
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="classes", null=True, blank=True)

    class Meta:
        unique_together = ("name", "academic_year", "etablissement")

    def __str__(self):
        return f"{self.name} - {self.academic_year}"


class Subject(TimeStampedModel):
    name = models.CharField(max_length=100)
    code = models.CharField(max_length=20)
    coefficient = models.DecimalField(max_digits=4, decimal_places=2, default=1)
    classroom = models.ForeignKey(
        ClassRoom,
        on_delete=models.PROTECT,
        related_name="subjects",
        null=True,
        blank=True,
    )

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["classroom", "code"],
                name="uniq_subject_code_per_classroom",
            )
        ]

    def __str__(self):
        class_name = self.classroom.name if self.classroom else "Classe non definie"
        return f"{self.code} - {self.name} ({class_name})"


class Teacher(TimeStampedModel):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="teacher_profile")
    employee_code = models.CharField(max_length=30, unique=True)
    hire_date = models.DateField()
    salary_base = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    hourly_rate = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="teachers", null=True, blank=True)

    def __str__(self):
        return self.user.get_full_name() or self.user.username


class TeacherAssignment(TimeStampedModel):
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="assignments")
    subject = models.ForeignKey(Subject, on_delete=models.PROTECT, related_name="teacher_assignments")
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT, related_name="teacher_assignments")

    class Meta:
        unique_together = ("teacher", "subject", "classroom")


class WeekDay(models.TextChoices):
    MONDAY = "MON", "Lundi"
    TUESDAY = "TUE", "Mardi"
    WEDNESDAY = "WED", "Mercredi"
    THURSDAY = "THU", "Jeudi"
    FRIDAY = "FRI", "Vendredi"
    SATURDAY = "SAT", "Samedi"


class TeacherScheduleSlot(TimeStampedModel):
    assignment = models.ForeignKey(TeacherAssignment, on_delete=models.CASCADE, related_name="schedule_slots")
    day_of_week = models.CharField(max_length=3, choices=WeekDay.choices)
    start_time = models.TimeField()
    end_time = models.TimeField()
    room = models.CharField(max_length=60, blank=True)

    class Meta:
        unique_together = ("assignment", "day_of_week", "start_time", "end_time")
        ordering = ("day_of_week", "start_time", "end_time", "id")

    def __str__(self):
        return (
            f"{self.assignment.classroom} | {self.get_day_of_week_display()} "
            f"{self.start_time.strftime('%H:%M')}-{self.end_time.strftime('%H:%M')}"
        )


class TeacherAvailabilitySlot(TimeStampedModel):
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="availability_slots")
    etablissement = models.ForeignKey(
        "Etablissement",
        on_delete=models.PROTECT,
        related_name="teacher_availability_slots",
        null=True,
        blank=True,
    )
    day_of_week = models.CharField(max_length=3, choices=WeekDay.choices)
    start_time = models.TimeField()
    end_time = models.TimeField()

    class Meta:
        unique_together = ("etablissement", "day_of_week", "start_time", "end_time")
        ordering = ("day_of_week", "start_time", "end_time", "id")
        indexes = [
            models.Index(
                fields=["etablissement", "day_of_week", "start_time", "end_time"],
                name="teacheravail_etab_day_time_idx",
            ),
            models.Index(fields=["teacher", "day_of_week"], name="teacheravail_teacher_day_idx"),
        ]

    def __str__(self):
        teacher_name = self.teacher.user.get_full_name().strip() if self.teacher and self.teacher.user else ""
        teacher_label = teacher_name or (self.teacher.employee_code if self.teacher else "Enseignant")
        return (
            f"{teacher_label} | {self.get_day_of_week_display()} "
            f"{self.start_time.strftime('%H:%M')}-{self.end_time.strftime('%H:%M')}"
        )


class TimetablePublication(TimeStampedModel):
    classroom = models.OneToOneField(ClassRoom, on_delete=models.CASCADE, related_name="timetable_publication")
    is_published = models.BooleanField(default=False)
    is_locked = models.BooleanField(default=False)
    published_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="published_timetables",
    )
    published_at = models.DateTimeField(null=True, blank=True)
    notes = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ("classroom__name",)

    def __str__(self):
        state = "Publié" if self.is_published else "Brouillon"
        lock_state = " - Verrouillé" if self.is_locked else ""
        return f"{self.classroom.name}: {state}{lock_state}"



class ParentProfile(TimeStampedModel):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="parent_profile")
    profession = models.CharField(max_length=120, blank=True)
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="parents", null=True, blank=True)

    def __str__(self):
        return self.user.get_full_name() or self.user.username



class Student(TimeStampedModel):
    class Gender(models.TextChoices):
        MALE = "M", "Masculin"
        FEMALE = "F", "Féminin"

    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="student_profile")
    matricule = models.CharField(max_length=30, unique=True, blank=True)
    gender = models.CharField(max_length=1, choices=Gender.choices, null=True, blank=True)
    birth_date = models.DateField(null=True, blank=True)
    # blank=True et pas seulement null=True: SET_NULL fait que l'application
    # produit elle-meme des eleves sans classe quand une classe disparait, et
    # save() appelle full_clean(). Sans blank=True, un tel eleve devenait
    # impossible a re-enregistrer, y compris lors d'une restauration de
    # sauvegarde. Le caractere obligatoire a l'inscription est porte par le
    # serializer, pas par le modele.
    classroom = models.ForeignKey(
        ClassRoom,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="students",
    )
    parent = models.ForeignKey(ParentProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name="children")
    photo = models.ImageField(upload_to="students/", null=True, blank=True)
    # `auto_now_add` imposait la date du jour et interdisait toute correction:
    # une ecole qui saisit en novembre les inscriptions de septembre, ou qui
    # importe l'existant, voyait toute sa base datee du jour de la saisie. Le
    # compteur "nouveaux cette annee" mesurait alors la creation des fiches, pas
    # les inscriptions. La date reste celle du jour par defaut, mais se corrige.
    enrollment_date = models.DateField(default=date.today)
    is_archived = models.BooleanField(default=False)
    conduite = models.DecimalField(max_digits=4, decimal_places=2, default=18)
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="students", null=True, blank=True)

    def save(self, *args, **kwargs):
        if not self.matricule:
            self.matricule = self._build_matricule()
        self.full_clean()
        super().save(*args, **kwargs)

    def clean(self):
        from django.core.exceptions import ValidationError
        if self.birth_date and self.birth_date > date.today():
            raise ValidationError({'birth_date': 'Date de naissance ne peut pas être dans le futur'})
        # Antidater est le cas d'usage; postdater fausserait les effectifs de
        # l'annee en cours sans qu'aucun ecran ne le signale.
        if self.enrollment_date and self.enrollment_date > date.today():
            raise ValidationError({'enrollment_date': "La date d'inscription ne peut pas être dans le futur"})
        if self.conduite and not (0 <= self.conduite <= 20):
            raise ValidationError({'conduite': 'Conduite doit être entre 0 et 20'})

    def _build_matricule(self):
        target_etablissement = self.etablissement or (self.classroom.etablissement if self.classroom else None)
        etablissement_name = getattr(target_etablissement, "name", "") or ""
        etablissement_code = self._normalize_etablissement_code(etablissement_name)

        class_name = self.classroom.name if self.classroom else ""
        class_code = self._normalize_class_code(class_name)

        if self.classroom and getattr(self.classroom, "academic_year", None):
            entry_year = self.classroom.academic_year.start_date.year
        else:
            entry_year = self.enrollment_date.year if self.enrollment_date else date.today().year

        entry_year_code = str(entry_year)[-2:]

        if self.gender in {self.Gender.MALE, self.Gender.FEMALE}:
            gender_code = self.gender
            prefix = f"{etablissement_code}{class_code}{entry_year_code}E"
        else:
            gender_code = None
            prefix = f"GS-{entry_year}"

        last_student = Student.objects.filter(matricule__startswith=prefix).order_by("-id").first()
        next_number = 1
        if last_student and last_student.matricule:
            digits = re.findall(r"(\d+)", last_student.matricule)
            if digits:
                try:
                    next_number = int(digits[-1]) + 1
                except (ValueError, IndexError):
                    next_number = last_student.id + 1 if last_student.id else 1
            else:
                next_number = last_student.id + 1 if last_student.id else 1

        if gender_code:
            return f"{prefix}{next_number:04d}{gender_code}"
        return f"{prefix}-{next_number:05d}"

    @staticmethod
    def _normalize_etablissement_code(name: str) -> str:
        if not name:
            return "GS"
        normalized = re.findall(r"[A-Z0-9]+", name.upper())
        if len(normalized) >= 2:
            return "".join(part[0] for part in normalized[:2])
        code = normalized[0] if normalized else "GS"
        return code[:2]

    @staticmethod
    def _normalize_class_code(name: str) -> str:
        if not name:
            return "CL"
        normalized = name.upper()
        normalized = normalized.replace("ÈME", "").replace("EME", "")
        normalized = normalized.replace("É", "E").replace("È", "E").replace("Ô", "O").replace("À", "A")
        normalized = re.sub(r"[^A-Z0-9]", "", normalized)
        return normalized[:4] if len(normalized) >= 2 else normalized.ljust(2, "X")

    def __str__(self):
        return f"{self.matricule} - {self.user.get_full_name()}"

    class Meta:
        indexes = [
            models.Index(fields=["etablissement", "-created_at"], name="student_etab_created_idx"),
            models.Index(fields=["classroom", "is_archived"], name="student_class_arch_idx"),
            models.Index(fields=["parent"], name="student_parent_idx"),
            models.Index(fields=["etablissement", "is_archived", "classroom"], name="student_etab_arch_class_idx"),
            models.Index(fields=["enrollment_date"], name="student_enroll_date_idx"),
        ]


class StudentAcademicHistory(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="history")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT)
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT)
    average = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    rank = models.PositiveIntegerField(default=0)


class PromotionRunStatus(models.TextChoices):
    SIMULATED = "simulated", "Simulation"
    EXECUTED = "executed", "Execute"


class PromotionDecisionType(models.TextChoices):
    PROMOTED = "promoted", "Promu"
    REPEATED = "repeated", "Redouble"
    ARCHIVED = "archived", "Archive"


class PromotionRun(TimeStampedModel):
    etablissement = models.ForeignKey(
        "Etablissement",
        on_delete=models.PROTECT,
        related_name="promotion_runs",
        null=True,
        blank=True,
    )
    source_academic_year = models.ForeignKey(
        AcademicYear,
        on_delete=models.PROTECT,
        related_name="promotion_runs_source",
    )
    target_academic_year = models.ForeignKey(
        AcademicYear,
        on_delete=models.PROTECT,
        related_name="promotion_runs_target",
        null=True,
        blank=True,
    )
    status = models.CharField(
        max_length=20,
        choices=PromotionRunStatus.choices,
        default=PromotionRunStatus.SIMULATED,
    )
    min_average = models.DecimalField(max_digits=5, decimal_places=2, default=10)
    min_conduite = models.DecimalField(max_digits=5, decimal_places=2, default=10)
    executed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="promotion_runs",
    )
    total_students = models.PositiveIntegerField(default=0)
    promoted_count = models.PositiveIntegerField(default=0)
    repeated_count = models.PositiveIntegerField(default=0)
    archived_count = models.PositiveIntegerField(default=0)
    payload = models.JSONField(default=dict, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["etablissement", "-created_at"], name="promrun_etab_created_idx"),
            models.Index(fields=["status", "-created_at"], name="promrun_status_created_idx"),
        ]


class PromotionDecision(TimeStampedModel):
    run = models.ForeignKey(PromotionRun, on_delete=models.CASCADE, related_name="decisions")
    student = models.ForeignKey(Student, on_delete=models.PROTECT, related_name="promotion_decisions")
    source_classroom = models.ForeignKey(
        ClassRoom,
        on_delete=models.PROTECT,
        related_name="promotion_decisions_source",
    )
    target_classroom = models.ForeignKey(
        ClassRoom,
        on_delete=models.PROTECT,
        related_name="promotion_decisions_target",
        null=True,
        blank=True,
    )
    decision = models.CharField(max_length=20, choices=PromotionDecisionType.choices)
    average = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    conduite = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    rank = models.PositiveIntegerField(default=0)
    reason = models.CharField(max_length=255, blank=True)

    class Meta:
        unique_together = ("run", "student")
        indexes = [
            models.Index(fields=["run", "decision"], name="promdec_run_decision_idx"),
            models.Index(fields=["source_classroom", "decision"], name="promdec_source_decision_idx"),
        ]


class Grade(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="grades")
    subject = models.ForeignKey(Subject, on_delete=models.PROTECT, related_name="grades")
    classroom = models.ForeignKey(ClassRoom, on_delete=models.PROTECT, related_name="grades")
    academic_year = models.ForeignKey(AcademicYear, on_delete=models.PROTECT, related_name="grades")
    term = models.CharField(max_length=20)
    homework_scores = models.JSONField(default=list, blank=True)
    value = models.DecimalField(max_digits=5, decimal_places=2)

    def _normalized_homework_scores(self):
        raw_scores = self.homework_scores if isinstance(self.homework_scores, list) else []
        normalized = []
        for item in raw_scores:
            try:
                numeric = Decimal(str(item))
            except Exception:
                continue
            if numeric < Decimal("0") or numeric > Decimal("20"):
                continue
            normalized.append(numeric)
        return normalized

    def save(self, *args, **kwargs):
        scores = self._normalized_homework_scores()
        if scores:
            average = sum(scores) / Decimal(len(scores))
            self.value = average.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        super().save(*args, **kwargs)

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

    class Meta:
        indexes = [
            models.Index(fields=["student", "date"], name="attendance_student_date_idx"),
            models.Index(fields=["date", "is_absent"], name="attendance_date_abs_idx"),
        ]


class AttendanceSheetValidation(TimeStampedModel):
    classroom = models.ForeignKey(
        ClassRoom,
        on_delete=models.CASCADE,
        related_name="attendance_sheet_validations",
    )
    date = models.DateField()
    is_locked = models.BooleanField(default=True)
    validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="validated_attendance_sheets",
    )
    validated_at = models.DateTimeField(null=True, blank=True)
    notes = models.CharField(max_length=255, blank=True)

    class Meta:
        unique_together = ("classroom", "date")
        indexes = [
            models.Index(fields=["classroom", "date"], name="attsheet_class_date_idx"),
        ]


class TeacherAttendance(TimeStampedModel):
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="attendances")
    date = models.DateField()
    is_absent = models.BooleanField(default=False)
    is_late = models.BooleanField(default=False)
    reason = models.CharField(max_length=255, blank=True)
    proof = models.FileField(upload_to="teacher_attendance_proofs/", null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["teacher", "date"], name="teachatt_teacher_date_idx"),
            models.Index(fields=["date", "is_absent"], name="teachatt_date_abs_idx"),
        ]


class DisciplineSeverity(models.TextChoices):
    LOW = "low", "Faible"
    MEDIUM = "medium", "Moyenne"
    HIGH = "high", "Élevée"


class DisciplineStatus(models.TextChoices):
    OPEN = "open", "Ouvert"
    RESOLVED = "resolved", "Traité"


class DisciplineCategory(models.TextChoices):
    """Motifs d'incident, en liste fermee.

    Le champ etait un texte libre pre-rempli « Indiscipline »: chaque
    etablissement inventait ses propres libelles, « Retard » cotoyait
    « retards » et « Arrivee tardive », et aucun comptage par motif n'etait
    exploitable. AUTRE reste ouvert pour ce que la liste ne prevoit pas, la
    description portant alors le detail.
    """

    INDISCIPLINE = "indiscipline", "Indiscipline"
    RETARD = "retard", "Retard"
    ABSENCE = "absence_injustifiee", "Absence injustifiee"
    VIOLENCE = "violence", "Violence"
    TRICHE = "triche", "Triche"
    DEGRADATION = "degradation", "Degradation de materiel"
    TENUE = "tenue", "Tenue non conforme"
    INSOLENCE = "insolence", "Insolence"
    AUTRE = "autre", "Autre"


class DisciplineIncident(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="discipline_incidents")
    incident_date = models.DateField()
    category = models.CharField(
        max_length=120,
        choices=DisciplineCategory.choices,
        default=DisciplineCategory.INDISCIPLINE,
    )
    description = models.TextField()
    severity = models.CharField(max_length=10, choices=DisciplineSeverity.choices, default=DisciplineSeverity.MEDIUM)
    sanction = models.TextField(blank=True)
    status = models.CharField(max_length=10, choices=DisciplineStatus.choices, default=DisciplineStatus.OPEN)
    parent_notified = models.BooleanField(default=False)
    # Date de cloture, posee par le modele et non par l'appelant: « traite »
    # ne disait pas quand, et le delai de traitement -- la seule mesure qui
    # dise si le suivi disciplinaire fonctionne -- etait incalculable.
    resolved_at = models.DateTimeField(null=True, blank=True)
    reported_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="discipline_reports",
    )

    class Meta:
        indexes = [
            models.Index(fields=["student", "-incident_date"], name="discipline_student_date_idx"),
            models.Index(fields=["status", "-incident_date"], name="discipline_status_date_idx"),
        ]

    def save(self, *args, **kwargs):
        # Rouvrir un incident efface sa date de cloture: la laisser en place
        # aurait fait etat d'un traitement qui n'a plus cours.
        if self.status == DisciplineStatus.RESOLVED:
            if self.resolved_at is None:
                self.resolved_at = timezone.now()
        else:
            self.resolved_at = None
        super().save(*args, **kwargs)


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
        total = self.payments.filter(is_cancelled=False).aggregate(total=models.Sum("amount"))["total"]
        return total or Decimal("0.00")

    @property
    def balance(self):
        return self.amount_due - self.amount_paid

    class Meta:
        indexes = [
            models.Index(fields=["student", "-due_date"], name="studentfee_student_due_idx"),
            models.Index(fields=["academic_year", "-due_date"], name="studentfee_year_due_idx"),
        ]


class Payment(TimeStampedModel):
    fee = models.ForeignKey(StudentFee, on_delete=models.CASCADE, related_name="payments")
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    method = models.CharField(max_length=50)
    reference = models.CharField(max_length=100, blank=True)
    received_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="received_payments")
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="payments", null=True, blank=True)
    is_cancelled = models.BooleanField(default=False, db_index=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancelled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="cancelled_payments",
    )
    cancel_reason = models.CharField(max_length=255, blank=True)

    def cancel(self, *, user=None, reason=""):
        if self.is_cancelled:
            return
        self.is_cancelled = True
        self.cancelled_at = timezone.now()
        self.cancelled_by = user
        self.cancel_reason = (reason or "").strip()
        self.save(update_fields=["is_cancelled", "cancelled_at", "cancelled_by", "cancel_reason", "updated_at"])

    class Meta:
        indexes = [
            models.Index(fields=["etablissement", "-created_at"], name="payment_etab_created_idx"),
            models.Index(fields=["fee", "-created_at"], name="payment_fee_created_idx"),
            models.Index(fields=["method"], name="payment_method_idx"),
        ]


class Expense(TimeStampedModel):
    label = models.CharField(max_length=120)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    date = models.DateField()
    category = models.CharField(max_length=100)
    notes = models.TextField(blank=True)
    paid_on = models.DateField(null=True, blank=True)
    paid_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="paid_expenses",
    )
    level_one_validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="expense_level_one_validations",
    )
    level_one_validated_at = models.DateTimeField(null=True, blank=True)
    level_two_validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="expense_level_two_validations",
    )
    level_two_validated_at = models.DateTimeField(null=True, blank=True)
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="expenses", null=True, blank=True)

    @property
    def validation_stage(self):
        if self.level_two_validated_at:
            return "level_two"
        if self.level_one_validated_at:
            return "level_one"
        return "draft"

    @property
    def is_fully_validated(self):
        return bool(self.level_two_validated_at)

    class Meta:
        indexes = [
            models.Index(fields=["etablissement", "-date"], name="expense_etab_date_idx"),
        ]


class TeacherPayroll(TimeStampedModel):
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="payrolls")
    month = models.DateField()
    hours_attributed = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    hours_worked = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    hourly_rate = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    paid_on = models.DateField(null=True, blank=True)
    paid_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)
    level_one_validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="teacher_payroll_level_one_validations",
    )
    level_one_validated_at = models.DateTimeField(null=True, blank=True)
    level_two_validated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="teacher_payroll_level_two_validations",
    )
    level_two_validated_at = models.DateTimeField(null=True, blank=True)
    notes = models.TextField(blank=True)

    @property
    def validation_stage(self):
        if self.level_two_validated_at:
            return "level_two"
        if self.level_one_validated_at:
            return "level_one"
        return "draft"

    @property
    def is_fully_validated(self):
        return bool(self.level_two_validated_at)


class TeacherTimeEntry(TimeStampedModel):
    LATE_TOLERANCE_MINUTES = 15

    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name="time_entries")
    etablissement = models.ForeignKey(
        'Etablissement',
        on_delete=models.PROTECT,
        related_name="teacher_time_entries",
        null=True,
        blank=True,
    )
    entry_date = models.DateField()
    check_in_time = models.TimeField()
    check_out_time = models.TimeField(null=True, blank=True)
    late_minutes = models.PositiveIntegerField(default=0)
    tolerated_late_minutes = models.PositiveIntegerField(default=0)
    is_auto_closed = models.BooleanField(default=False)
    auto_closed_reason = models.CharField(max_length=255, blank=True)
    worked_hours = models.DecimalField(max_digits=8, decimal_places=2, default=0)
    notes = models.CharField(max_length=255, blank=True)
    recorded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="recorded_teacher_time_entries",
    )

    class Meta:
        indexes = [
            models.Index(fields=["teacher", "entry_date"], name="ttentry_teacher_date_idx"),
            models.Index(fields=["etablissement", "entry_date"], name="ttentry_etab_date_idx"),
        ]

    @property
    def is_checkout_missing(self):
        return self.check_out_time is None

    def _weekday_code(self):
        day_map = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        return day_map[self.entry_date.weekday()]

    def _schedule_slots_for_day(self):
        day_code = self._weekday_code()
        if day_code == "SUN":
            return TeacherScheduleSlot.objects.none()

        return TeacherScheduleSlot.objects.select_related("assignment", "assignment__teacher").filter(
            assignment__teacher=self.teacher,
            day_of_week=day_code,
        )

    @staticmethod
    def _time_to_minutes(value):
        return value.hour * 60 + value.minute

    def _pick_schedule_slot(self):
        slots = list(self._schedule_slots_for_day())
        if not slots:
            return None

        check_in_minutes = self._time_to_minutes(self.check_in_time)
        check_out_minutes = self._time_to_minutes(self.check_out_time) if self.check_out_time else None

        def slot_score(slot):
            start_minutes = self._time_to_minutes(slot.start_time)
            end_minutes = self._time_to_minutes(slot.end_time)
            overlap = 0
            if check_out_minutes is not None:
                overlap = max(0, min(end_minutes, check_out_minutes) - max(start_minutes, check_in_minutes))
            distance = abs(start_minutes - check_in_minutes)
            return (overlap, -distance)

        return max(slots, key=slot_score)

    def _resolve_auto_checkout(self, schedule_slot):
        if schedule_slot and schedule_slot.end_time and schedule_slot.end_time > self.check_in_time:
            return schedule_slot.end_time, "auto_close_schedule_end"

        default_cutoff = time(18, 0)
        if default_cutoff > self.check_in_time:
            return default_cutoff, "auto_close_default_cutoff"

        start_dt = datetime.combine(self.entry_date, self.check_in_time)
        fallback_dt = start_dt + timedelta(hours=1)
        max_dt = datetime.combine(self.entry_date, time(23, 59))
        if fallback_dt > max_dt:
            fallback_dt = max_dt
        return fallback_dt.time(), "auto_close_plus_one_hour"

    def _compute_payable_minutes(self, schedule_slot):
        if self.check_out_time is None or self.check_out_time <= self.check_in_time:
            return 0, 0, 0

        start_minutes = self._time_to_minutes(self.check_in_time)
        end_minutes = self._time_to_minutes(self.check_out_time)
        actual_minutes = max(end_minutes - start_minutes, 0)

        if not schedule_slot:
            return actual_minutes, 0, 0

        planned_start = self._time_to_minutes(schedule_slot.start_time)
        planned_end = self._time_to_minutes(schedule_slot.end_time)
        planned_duration = max(planned_end - planned_start, 0)

        late_minutes = max(start_minutes - planned_start, 0)
        tolerated_late = min(late_minutes, self.LATE_TOLERANCE_MINUTES)

        payable_minutes = actual_minutes + tolerated_late
        if planned_duration > 0:
            payable_minutes = min(payable_minutes, planned_duration)

        return max(payable_minutes, 0), late_minutes, tolerated_late

    def save(self, *args, **kwargs):
        if self.teacher and self.etablissement_id is None:
            self.etablissement = self.teacher.etablissement

        schedule_slot = self._pick_schedule_slot() if self.teacher_id else None

        if self.check_out_time is None:
            auto_checkout, reason = self._resolve_auto_checkout(schedule_slot)
            self.check_out_time = auto_checkout
            self.is_auto_closed = True
            self.auto_closed_reason = reason
        else:
            self.is_auto_closed = False
            self.auto_closed_reason = ""

        payable_minutes, late_minutes, tolerated_late = self._compute_payable_minutes(schedule_slot)
        duration_hours = Decimal(str(max(payable_minutes, 0) / 60)).quantize(
            Decimal("0.01"),
            rounding=ROUND_HALF_UP,
        )
        self.late_minutes = late_minutes
        self.tolerated_late_minutes = tolerated_late
        self.worked_hours = duration_hours
        super().save(*args, **kwargs)


class Announcement(TimeStampedModel):
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="announcements", null=True, blank=True)
    title = models.CharField(max_length=150)
    message = models.TextField()
    audience = models.CharField(max_length=50, default="all")
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)


class NotificationChannel(models.TextChoices):
    PUSH = "push", "Push"
    EMAIL = "email", "Email"
    SMS = "sms", "SMS"


class Notification(TimeStampedModel):
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="notifications", null=True, blank=True)
    recipient = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    channel = models.CharField(max_length=10, choices=NotificationChannel.choices)
    title = models.CharField(max_length=150)
    message = models.TextField()
    is_sent = models.BooleanField(default=False)
    sent_at = models.DateTimeField(null=True, blank=True)


class SmsProviderConfig(TimeStampedModel):
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="sms_provider_configs", null=True, blank=True)
    provider_name = models.CharField(max_length=100)
    api_url = models.URLField()
    api_token = models.CharField(max_length=255)
    sender_id = models.CharField(max_length=50, blank=True)
    is_active = models.BooleanField(default=False)


class Book(TimeStampedModel):
    """Un ouvrage papier, compte en exemplaires.

    `quantity_available` est derive et non saisi: c'est le nombre
    d'exemplaires en rayon, soit le total moins les emprunts non rendus. Il
    etait auparavant tape a la main dans le formulaire et ne bougeait
    jamais -- un livre prete restait annonce disponible.
    """

    title = models.CharField(max_length=150)
    author = models.CharField(max_length=120)
    # Unique par etablissement et non plus globalement: deux ecoles
    # possedent le meme manuel de mathematiques, et la contrainte globale
    # empechait la seconde de l'enregistrer. Voir les contraintes du Meta.
    isbn = models.CharField(max_length=30)
    # Facultatifs, mais ce sont eux qui font la difference entre une liste de
    # titres et un catalogue: retrouver « l'edition de 2019 rangee etagere B »
    # demandait jusqu'ici de connaitre le fonds par coeur.
    publisher = models.CharField(max_length=120, blank=True)
    published_year = models.PositiveSmallIntegerField(null=True, blank=True)
    subject = models.CharField(max_length=120, blank=True)
    shelf_location = models.CharField(max_length=60, blank=True)
    quantity_total = models.PositiveIntegerField(default=0)
    quantity_available = models.PositiveIntegerField(default=0)
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="books", null=True, blank=True)

    class Meta:
        constraints = [
            # Deux contraintes et non une seule sur (etablissement, isbn):
            # deux NULL ne sont jamais egaux en base, la paire laisserait
            # donc passer autant de doublons que d'ouvrages orphelins.
            models.UniqueConstraint(
                fields=["isbn"],
                condition=models.Q(etablissement__isnull=True) & ~models.Q(isbn=""),
                name="book_isbn_unique_sans_etablissement",
            ),
            models.UniqueConstraint(
                fields=["etablissement", "isbn"],
                condition=models.Q(etablissement__isnull=False) & ~models.Q(isbn=""),
                name="book_isbn_unique_par_etablissement",
            ),
        ]

    def __str__(self):
        return self.title

    def exemplaires_sortis(self):
        """Le nombre d'exemplaires actuellement chez des eleves."""
        return self.borrows.filter(returned_at__isnull=True).count()

    def recalculer_disponibilite(self, sauvegarder=True):
        """Remet le compteur d'accord avec les emprunts en cours.

        Recalcul complet plutot qu'un increment a chaque pret: un increment
        derive au premier emprunt supprime en base ou au premier total
        corrige a la main, et rien ne le rattrape jamais.
        """
        disponible = max(0, self.quantity_total - self.exemplaires_sortis())
        if disponible == self.quantity_available:
            return disponible
        self.quantity_available = disponible
        if sauvegarder:
            self.save(update_fields=["quantity_available", "updated_at"])
        return disponible


class Borrow(TimeStampedModel):
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name="borrows")
    book = models.ForeignKey(Book, on_delete=models.PROTECT, related_name="borrows")
    borrowed_at = models.DateField()
    due_date = models.DateField()
    returned_at = models.DateField(null=True, blank=True)
    penalty_amount = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    @property
    def est_rendu(self):
        return self.returned_at is not None

    def jours_de_retard(self, a_la_date=None):
        """Jours entames au-dela de l'echeance, 0 si le delai est tenu.

        Compte a la date du retour pour un emprunt rendu, a aujourd'hui pour
        un emprunt en cours: c'est ce qui permet d'afficher un retard qui
        grandit tant que le livre n'est pas revenu.
        """
        reference = self.returned_at or a_la_date or timezone.localdate()
        if not self.due_date or reference <= self.due_date:
            return 0
        return (reference - self.due_date).days

    def penalite_theorique(self, a_la_date=None):
        """Ce que le retard coute au tarif de l'etablissement."""
        tarif = getattr(
            getattr(self.student, "etablissement", None),
            "library_penalty_per_day",
            0,
        ) or 0
        return Decimal(tarif) * self.jours_de_retard(a_la_date)


def library_document_path(instance, filename):
    """library_docs/<serie>/<matiere>/<fichier>, precede de l'etablissement.

    Le chemin recopie l'arborescence de la source: c'est ce qui permet de
    relancer l'import sans dupliquer, et de reconnaitre un fichier a l'oeil
    dans le stockage objet.

    Un document televerse par une ecole prend en tete `etab_<id>`: deux
    ecoles peuvent nommer leur serie « Documents » et y deposer chacune un
    « reglement.pdf ». Sans ce prefixe, le second ecraserait le premier sur
    un stockage qui autorise l'ecrasement -- et les deux se disputeraient la
    meme entree de cache sur celui qui ne l'autorise pas.
    """
    categorie = instance.category
    racine = "library_docs"
    etablissement_id = getattr(instance, "etablissement_id", None)
    if etablissement_id:
        racine = f"{racine}/etab_{etablissement_id}"
    return f"{racine}/{categorie.collection.code}/{categorie.name}/{filename}"


class LibraryCollection(TimeStampedModel):
    """Une serie du secondaire: TSExp, 11e Sciences, 10e CG...

    Premier niveau de l'etagere numerique, distinct des ouvrages physiques
    (Book) qui restent comptes en exemplaires et empruntes.

    `etablissement` vide designe le fonds commun -- celui de l'import, les
    memes annales pour tout le monde, que dupliquer par etablissement
    multiplierait en giga-octets identiques. Renseigne, il designe une
    etagere propre a une ecole: son reglement interieur n'interesse qu'elle.
    """

    etablissement = models.ForeignKey(
        'Etablissement',
        on_delete=models.CASCADE,
        related_name="library_collections",
        null=True,
        blank=True,
    )
    code = models.CharField(max_length=40)
    label = models.CharField(max_length=150)
    source_url = models.URLField(max_length=500, blank=True)
    position = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["position", "label"]
        constraints = [
            # Deux contraintes et non une seule sur (etablissement, code):
            # en base, deux NULL ne sont jamais egaux, la paire laisserait
            # donc le fonds commun accepter deux fois « TSExp » -- et
            # l'import, qui cherche par code seul, en trouverait deux.
            models.UniqueConstraint(
                fields=["code"],
                condition=models.Q(etablissement__isnull=True),
                name="library_collection_code_unique_commun",
            ),
            models.UniqueConstraint(
                fields=["etablissement", "code"],
                condition=models.Q(etablissement__isnull=False),
                name="library_collection_code_unique_par_etablissement",
            ),
        ]

    def __str__(self):
        return self.label


class LibraryCategory(TimeStampedModel):
    """La matiere, dans une serie donnee: Mathematiques, Philosophie...

    Le meme intitule existe dans plusieurs series avec des documents
    differents, d'ou l'unicite par couple et non sur le seul nom.
    """

    collection = models.ForeignKey(
        LibraryCollection, on_delete=models.CASCADE, related_name="categories"
    )
    name = models.CharField(max_length=120)
    position = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["position", "name"]
        unique_together = ("collection", "name")

    def __str__(self):
        return f"{self.collection.code} / {self.name}"


class LibraryDocumentOrigin(models.TextChoices):
    """D'ou vient le document: du fonds importe, ou d'un televersement."""

    IMPORT = "import", "Fonds importé"
    UPLOAD = "upload", "Ajouté par l'établissement"


class LibraryDocument(TimeStampedModel):
    """Un PDF du fonds.

    `file` reste vide tant que le fichier n'a pas ete rapatrie: le catalogue
    est complet des la premiere passe d'import et l'API sert alors l'URL
    d'origine. `source_url` porte l'unicite du fonds importe -- c'est elle
    qui rend l'import rejouable sans creer de doublon.

    Un document televerse n'a pas de source: il arrive avec son fichier et
    rien d'autre. L'unicite ne peut donc plus porter sur la colonne entiere,
    sinon le deuxieme televersement se heurterait au premier sur leur
    `source_url` vide commune -- d'ou la contrainte conditionnelle.
    """

    category = models.ForeignKey(
        LibraryCategory, on_delete=models.CASCADE, related_name="documents"
    )
    # Recopie de la serie plutot que lue a travers elle: le filtrage par
    # etablissement porte sur chaque document liste, et remonter la chaine
    # category -> collection a chaque ligne coute une jointure de plus sur
    # une table de plusieurs milliers d'entrees.
    etablissement = models.ForeignKey(
        'Etablissement',
        on_delete=models.CASCADE,
        related_name="library_documents",
        null=True,
        blank=True,
    )
    origin = models.CharField(
        max_length=10,
        choices=LibraryDocumentOrigin.choices,
        default=LibraryDocumentOrigin.UPLOAD,
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        related_name="library_documents",
        null=True,
        blank=True,
    )
    description = models.TextField(blank=True)
    title = models.CharField(max_length=255)
    # 400 et non les 100 par defaut: le chemin recopie l'arborescence de la
    # source, et trente-six documents du fonds la depassent deja -- le plus
    # long tient 127 caracteres. Le fichier partait bien sur le stockage,
    # puis la ligne mourait en base sur « value too long », laissant des
    # gigaoctets de PDF orphelins que la base ne connaissait plus.
    file = models.FileField(
        upload_to=library_document_path, max_length=400, null=True, blank=True
    )
    source_url = models.URLField(max_length=500, blank=True)
    size_bytes = models.PositiveBigIntegerField(default=0)
    is_downloaded = models.BooleanField(default=False)
    # Renseigne quand la source refuse le fichier: 43 des 1257 documents de
    # BKalan repondent 401 sur leur propre serveur, quel que soit l'encodage
    # essaye -- les cinq variantes (brute, NFC, NFD, crochets et parentheses
    # laisses tels quels) ont ete sondees une a une. Accent, espace ou
    # caractere invisible dans le chemin: le fichier est mort chez eux. Les
    # taire les ferait passer pour des telechargements en attente.
    import_error = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ["title", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["source_url"],
                condition=~models.Q(source_url=""),
                name="library_document_source_url_unique",
            ),
        ]

    def __str__(self):
        return self.title


class CanteenMenu(TimeStampedModel):
    menu_date = models.DateField()
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="canteen_menus", null=True, blank=True)
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
    term = models.CharField(max_length=2, default="T1")
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

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["session", "student", "subject"],
                name="uniq_exam_result_session_student_subject",
            )
        ]


class Supplier(TimeStampedModel):
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="suppliers", null=True, blank=True)
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=30, blank=True)
    email = models.EmailField(blank=True)


class StockItem(TimeStampedModel):
    etablissement = models.ForeignKey('Etablissement', on_delete=models.PROTECT, related_name="stock_items", null=True, blank=True)
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
        grades = Grade.objects.filter(
            student=student,
            classroom=classroom,
            academic_year=academic_year,
            term=term,
        ).select_related("subject")
        exam_results = ExamResult.objects.filter(
            student=student,
            session__academic_year=academic_year,
            session__term=term,
        ).select_related("subject", "session")

        class_note_by_subject = {}
        subject_by_id = {}
        for grade in grades.order_by("subject_id", "-created_at", "-id"):
            class_note_by_subject.setdefault(grade.subject_id, Decimal(str(grade.value)))
            subject_by_id.setdefault(grade.subject_id, grade.subject)

        exam_note_by_subject = {}
        for exam_result in exam_results.order_by(
            "subject_id",
            "-session__end_date",
            "-session__start_date",
            "-created_at",
            "-id",
        ):
            exam_note_by_subject.setdefault(exam_result.subject_id, Decimal(str(exam_result.score)))
            subject_by_id.setdefault(exam_result.subject_id, exam_result.subject)

        weighted_sum = Decimal("0")
        coef_sum = Decimal("0")

        for subject_id, subject in subject_by_id.items():
            coef = Decimal(str(subject.coefficient or 0))
            if coef <= 0:
                continue

            class_note = class_note_by_subject.get(subject_id)
            exam_note = exam_note_by_subject.get(subject_id)

            if class_note is not None:
                weighted_sum += class_note * coef
                coef_sum += coef
            if exam_note is not None:
                weighted_sum += exam_note * coef
                coef_sum += coef

        average = Decimal("0")
        if coef_sum > 0:
            average = (weighted_sum / coef_sum).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)

        student_averages.append((student, average))

    sorted_students = sorted(student_averages, key=lambda row: row[1], reverse=True)
    for index, (student, average) in enumerate(sorted_students, start=1):
        StudentAcademicHistory.objects.update_or_create(
            student=student,
            academic_year=academic_year,
            classroom=classroom,
            defaults={"average": average, "rank": index},
        )
