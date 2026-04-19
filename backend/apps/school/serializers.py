import re
from decimal import Decimal
from rest_framework import serializers
from .term_utils import normalize_term
from apps.accounts.models import UserRole
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
    Etablissement,
    ExamPlanning,
    ExamInvigilation,
    ExamResult,
    ExamSession,
    Expense,
    Grade,
    GradeValidation,
    Notification,
    ParentProfile,
    Payment,
    PromotionDecision,
    PromotionRun,
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
    TeacherAvailabilitySlot,
    TeacherScheduleSlot,
    TeacherTimeEntry,
    TimetablePublication,
    TeacherPayroll,
)


class AcademicYearSerializer(serializers.ModelSerializer):
    class Meta:
        model = AcademicYear
        fields = "__all__"


class EtablissementSerializer(serializers.ModelSerializer):
    logo = serializers.ImageField(required=False, allow_null=True)
    stamp_image = serializers.ImageField(required=False, allow_null=True)
    principal_signature_image = serializers.ImageField(required=False, allow_null=True)
    cashier_signature_image = serializers.ImageField(required=False, allow_null=True)

    class Meta:
        model = Etablissement
        fields = [
            'id',
            'name',
            'address',
            'phone',
            'email',
            'logo',
            'stamp_image',
            'principal_signature_image',
            'cashier_signature_image',
            'principal_signature_label',
            'cashier_signature_label',
            'parent_signature_label',
            'principal_signature_position',
            'stamp_position',
            'principal_signature_scale',
            'stamp_scale',
        ]

    def validate(self, attrs):
        attrs = super().validate(attrs)
        for key in ('principal_signature_scale', 'stamp_scale'):
            value = attrs.get(key)
            if value is None:
                continue
            if value < 40 or value > 200:
                raise serializers.ValidationError({key: 'La valeur doit etre comprise entre 40 et 200.'})
        return attrs

    def to_representation(self, instance):
        data = super().to_representation(instance)
        request = self.context.get("request")
        for field_name in ("logo", "stamp_image", "principal_signature_image", "cashier_signature_image"):
            field = getattr(instance, field_name, None)
            if not field:
                data[field_name] = None
                continue
            if request is None:
                data[field_name] = field.url
            else:
                data[field_name] = request.build_absolute_uri(field.url)
        return data


class ClassRoomSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = ClassRoom
        fields = "__all__"


class SubjectSerializer(serializers.ModelSerializer):
    classroom_name = serializers.SerializerMethodField(read_only=True)
    code = serializers.CharField(required=False, allow_blank=True)

    @staticmethod
    def _base_subject_code(name):
        compact = re.sub(r"[^A-Za-z0-9]+", "", (name or "").upper())
        if not compact:
            return "MAT"
        return compact[:8]

    def _next_available_subject_code(self, classroom, base_code):
        candidate = base_code[:20]
        suffix = 2
        while True:
            existing = Subject.objects.filter(classroom=classroom, code__iexact=candidate)
            if self.instance is not None:
                existing = existing.exclude(pk=self.instance.pk)
            if not existing.exists():
                return candidate

            suffix_text = str(suffix)
            stem = base_code[: max(1, 20 - len(suffix_text))]
            candidate = f"{stem}{suffix_text}"
            suffix += 1

    def get_classroom_name(self, obj):
        classroom = obj.classroom
        return classroom.name if classroom else ""

    def validate(self, attrs):
        attrs = super().validate(attrs)
        classroom = attrs.get("classroom") or getattr(self.instance, "classroom", None)
        provided_code = (attrs.get("code") or "").strip()
        current_code = (getattr(self.instance, "code", "") or "").strip()
        code = provided_code or current_code
        name = (attrs.get("name") or getattr(self.instance, "name", "") or "").strip()

        if not classroom:
            raise serializers.ValidationError({"classroom": "La classe est obligatoire pour une matiere."})

        if not code:
            base_code = self._base_subject_code(name)
            code = self._next_available_subject_code(classroom, base_code)
            attrs["code"] = code

        existing = Subject.objects.filter(classroom=classroom, code__iexact=code)
        if self.instance is not None:
            existing = existing.exclude(pk=self.instance.pk)
        if existing.exists():
            if provided_code:
                raise serializers.ValidationError(
                    {"code": "Ce code matiere existe deja pour cette classe."}
                )

            base_code = self._base_subject_code(name)
            attrs["code"] = self._next_available_subject_code(classroom, base_code)

        return attrs

    class Meta:
        model = Subject
        fields = "__all__"
        validators = []



class TeacherSerializer(serializers.ModelSerializer):
    user_full_name = serializers.SerializerMethodField(read_only=True)
    user_first_name = serializers.SerializerMethodField(read_only=True)
    user_last_name = serializers.SerializerMethodField(read_only=True)
    user_username = serializers.SerializerMethodField(read_only=True)
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)
    etablissement_name = serializers.SerializerMethodField(read_only=True)

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

    def get_etablissement_name(self, obj):
        etablissement = obj.etablissement
        return etablissement.name if etablissement else ""

    class Meta:
        model = Teacher
        fields = "__all__"


class TeacherAssignmentSerializer(serializers.ModelSerializer):
    teacher_name = serializers.SerializerMethodField(read_only=True)
    subject_name = serializers.SerializerMethodField(read_only=True)
    subject_code = serializers.SerializerMethodField(read_only=True)
    classroom_name = serializers.SerializerMethodField(read_only=True)
    etablissement = serializers.SerializerMethodField(read_only=True)
    etablissement_name = serializers.SerializerMethodField(read_only=True)

    def get_teacher_name(self, obj):
        teacher = obj.teacher
        if not teacher or not teacher.user:
            return ""
        full_name = teacher.user.get_full_name().strip()
        return full_name or teacher.user.username

    def get_subject_name(self, obj):
        subject = obj.subject
        return subject.name if subject else ""

    def get_subject_code(self, obj):
        subject = obj.subject
        return subject.code if subject else ""

    def get_classroom_name(self, obj):
        classroom = obj.classroom
        return classroom.name if classroom else ""

    def get_etablissement(self, obj):
        classroom = obj.classroom
        return classroom.etablissement_id if classroom else None

    def get_etablissement_name(self, obj):
        classroom = obj.classroom
        etablissement = classroom.etablissement if classroom else None
        return etablissement.name if etablissement else ""

    def validate(self, attrs):
        teacher = attrs.get("teacher") or getattr(self.instance, "teacher", None)
        subject = attrs.get("subject") or getattr(self.instance, "subject", None)
        classroom = attrs.get("classroom") or getattr(self.instance, "classroom", None)

        if not teacher or not subject or not classroom:
            return attrs

        if teacher.etablissement_id and classroom.etablissement_id:
            if teacher.etablissement_id != classroom.etablissement_id:
                raise serializers.ValidationError(
                    {"teacher": "Cet enseignant n'appartient pas au même établissement que la classe."}
                )

        conflict_qs = TeacherAssignment.objects.filter(subject=subject, classroom=classroom)
        if self.instance:
            conflict_qs = conflict_qs.exclude(pk=self.instance.pk)

        if conflict_qs.exists():
            existing = conflict_qs.select_related("teacher", "teacher__user").first()
            existing_label = "un autre enseignant"
            if existing and existing.teacher and existing.teacher.user:
                full_name = existing.teacher.user.get_full_name().strip()
                existing_label = full_name or existing.teacher.user.username

            raise serializers.ValidationError(
                {
                    "subject": (
                        f"La matière '{subject.name}' est déjà affectée à la classe '{classroom.name}' "
                        f"par {existing_label}."
                    )
                }
            )

        return attrs

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


class TeacherAvailabilitySlotSerializer(serializers.ModelSerializer):
    teacher_name = serializers.SerializerMethodField(read_only=True)
    etablissement_name = serializers.SerializerMethodField(read_only=True)

    def get_teacher_name(self, obj):
        teacher = obj.teacher
        if not teacher or not teacher.user:
            return ""
        full_name = teacher.user.get_full_name().strip()
        return full_name or teacher.user.username

    def get_etablissement_name(self, obj):
        etablissement = obj.etablissement
        return etablissement.name if etablissement else ""

    def validate(self, attrs):
        teacher = attrs.get("teacher") or getattr(self.instance, "teacher", None)
        etablissement = attrs.get("etablissement") or getattr(self.instance, "etablissement", None)
        day_of_week = attrs.get("day_of_week") or getattr(self.instance, "day_of_week", None)
        start_time = attrs.get("start_time") or getattr(self.instance, "start_time", None)
        end_time = attrs.get("end_time") or getattr(self.instance, "end_time", None)

        if not teacher or not day_of_week or not start_time or not end_time:
            return attrs

        if end_time <= start_time:
            raise serializers.ValidationError(
                {"end_time": "L'heure de fin doit être après l'heure de début."}
            )

        teacher_etablissement = teacher.etablissement
        if etablissement is None and teacher_etablissement is not None:
            attrs["etablissement"] = teacher_etablissement
            etablissement = teacher_etablissement

        if teacher_etablissement and etablissement and teacher_etablissement.id != etablissement.id:
            raise serializers.ValidationError(
                {"teacher": "Cet enseignant n'appartient pas à l'établissement sélectionné."}
            )

        overlap_qs = TeacherAvailabilitySlot.objects.filter(
            etablissement=etablissement,
            day_of_week=day_of_week,
            start_time__lt=end_time,
            end_time__gt=start_time,
        )
        if self.instance:
            overlap_qs = overlap_qs.exclude(pk=self.instance.pk)

        if overlap_qs.exists():
            taken_slot = overlap_qs.select_related("teacher", "teacher__user").first()
            taken_label = "un autre enseignant"
            if taken_slot and taken_slot.teacher and taken_slot.teacher.user:
                full_name = taken_slot.teacher.user.get_full_name().strip()
                taken_label = full_name or taken_slot.teacher.user.username

            raise serializers.ValidationError(
                {
                    "non_field_errors": [
                        "Ce créneau est déjà réservé et n'est plus disponible.",
                        f"Réservé par: {taken_label}.",
                    ]
                }
            )

        return attrs

    class Meta:
        model = TeacherAvailabilitySlot
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
    user_full_name = serializers.SerializerMethodField(read_only=True)
    user_username = serializers.SerializerMethodField(read_only=True)
    user_first_name = serializers.SerializerMethodField(read_only=True)
    user_last_name = serializers.SerializerMethodField(read_only=True)

    def get_user_full_name(self, obj):
        user = obj.user
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def get_user_username(self, obj):
        return obj.user.username if obj.user else ""

    def get_user_first_name(self, obj):
        return obj.user.first_name if obj.user else ""

    def get_user_last_name(self, obj):
        return obj.user.last_name if obj.user else ""

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

    def validate(self, attrs):
        if "conduite" in attrs:
            request = self.context.get("request")
            role = getattr(getattr(request, "user", None), "role", "")
            if role not in {UserRole.SUPERVISOR, UserRole.SUPER_ADMIN}:
                raise serializers.ValidationError(
                    {"conduite": "Seuls le surveillant et le super admin peuvent modifier la conduite."}
                )
        return attrs

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
    value = serializers.DecimalField(max_digits=5, decimal_places=2, required=False)
    homework_scores = serializers.ListField(
        child=serializers.DecimalField(max_digits=5, decimal_places=2),
        required=False,
        allow_empty=True,
    )

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

    def validate_homework_scores(self, value):
        if value is None:
            return []

        normalized = []
        for raw in value:
            numeric = Decimal(str(raw))
            if numeric < Decimal("0") or numeric > Decimal("20"):
                raise serializers.ValidationError(
                    "Chaque note de devoir doit être comprise entre 0 et 20."
                )
            normalized.append(numeric.quantize(Decimal("0.01")))
        return normalized

    def validate(self, attrs):
        attrs = super().validate(attrs)

        provided_homework_scores = attrs.get("homework_scores", None)
        provided_value = attrs.get("value", None)

        if self.instance is None and provided_homework_scores is None and provided_value is None:
            raise serializers.ValidationError(
                {"homework_scores": "Saisissez au moins une note de devoir ou une note de classe."}
            )

        if provided_homework_scores is not None:
            if len(provided_homework_scores) == 0:
                raise serializers.ValidationError(
                    {"homework_scores": "Ajoutez au moins une note de devoir."}
                )
            average = sum(provided_homework_scores) / Decimal(len(provided_homework_scores))
            attrs["value"] = average.quantize(Decimal("0.01"))
            attrs["homework_scores"] = [str(score) for score in provided_homework_scores]

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
    conduite = serializers.DecimalField(
        max_digits=4,
        decimal_places=2,
        required=False,
        min_value=Decimal("0"),
        max_value=Decimal("20"),
    )

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
        request = self.context.get("request")

        if "conduite" in attrs:
            role = getattr(getattr(request, "user", None), "role", "")
            if role not in {UserRole.SUPERVISOR, UserRole.SUPER_ADMIN}:
                raise serializers.ValidationError(
                    {"conduite": "Seuls le surveillant et le super admin peuvent modifier la conduite."}
                )

        if student and attendance_date:
            queryset = Attendance.objects.filter(student=student, date=attendance_date)
            if self.instance:
                queryset = queryset.exclude(pk=self.instance.pk)
            if queryset.exists():
                raise serializers.ValidationError(
                    "Une présence existe déjà pour cet élève à cette date."
                )

        return attrs

    def create(self, validated_data):
        conduite = validated_data.pop("conduite", None)
        attendance = super().create(validated_data)
        self._save_conduite(attendance.student, conduite)
        return attendance

    def update(self, instance, validated_data):
        conduite = validated_data.pop("conduite", None)
        attendance = super().update(instance, validated_data)
        self._save_conduite(attendance.student, conduite)
        return attendance

    def to_representation(self, instance):
        data = super().to_representation(instance)
        student = getattr(instance, "student", None)
        conduite_value = getattr(student, "conduite", Decimal("18")) if student else Decimal("18")
        data["conduite"] = str(conduite_value)
        return data

    def _save_conduite(self, student, conduite):
        if student is None or conduite is None:
            return
        student.conduite = conduite
        student.save(update_fields=["conduite"])

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


class TeacherTimeEntrySerializer(serializers.ModelSerializer):
    teacher_full_name = serializers.SerializerMethodField(read_only=True)
    teacher_employee_code = serializers.SerializerMethodField(read_only=True)
    check_out_time = serializers.TimeField(required=False, allow_null=True)

    def get_teacher_full_name(self, obj):
        teacher = obj.teacher
        user = teacher.user if teacher else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_teacher_employee_code(self, obj):
        teacher = obj.teacher
        return teacher.employee_code if teacher else ""

    def validate(self, attrs):
        attrs = super().validate(attrs)
        teacher = attrs.get("teacher") or getattr(self.instance, "teacher", None)
        entry_date = attrs.get("entry_date") or getattr(self.instance, "entry_date", None)
        check_in_time = attrs.get("check_in_time") or getattr(self.instance, "check_in_time", None)
        check_out_time = attrs.get("check_out_time") or getattr(self.instance, "check_out_time", None)

        if teacher and entry_date:
            day_code = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"][entry_date.weekday()]
            if day_code == "SUN":
                raise serializers.ValidationError(
                    {"entry_date": "Le pointage enseignant est interdit le dimanche."}
                )

            has_slot = TeacherScheduleSlot.objects.filter(
                assignment__teacher=teacher,
                day_of_week=day_code,
            ).exists()
            if not has_slot:
                raise serializers.ValidationError(
                    {
                        "entry_date": (
                            "Aucun creneau d'emploi du temps pour cet enseignant ce jour. "
                            "Le pointage est bloque."
                        )
                    }
                )

        if check_in_time and check_out_time and check_out_time <= check_in_time:
            raise serializers.ValidationError(
                {"check_out_time": "L'heure de sortie doit être après l'heure d'entrée."}
            )

        return attrs

    class Meta:
        model = TeacherTimeEntry
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
    amount_paid = serializers.SerializerMethodField(read_only=True)
    balance = serializers.SerializerMethodField(read_only=True)
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)

    def get_amount_paid(self, obj):
        annotated = getattr(obj, "amount_paid_annotated", None)
        if annotated is not None:
            return annotated
        return obj.amount_paid

    def get_balance(self, obj):
        annotated = getattr(obj, "balance_annotated", None)
        if annotated is not None:
            return annotated
        return obj.balance

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
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = Expense
        fields = "__all__"


class TeacherPayrollSerializer(serializers.ModelSerializer):
    teacher_full_name = serializers.SerializerMethodField(read_only=True)
    teacher_employee_code = serializers.SerializerMethodField(read_only=True)
    validation_stage = serializers.CharField(read_only=True)
    is_fully_validated = serializers.BooleanField(read_only=True)
    level_one_validated_by_name = serializers.SerializerMethodField(read_only=True)
    level_two_validated_by_name = serializers.SerializerMethodField(read_only=True)

    def get_teacher_full_name(self, obj):
        teacher = obj.teacher
        user = teacher.user if teacher else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_teacher_employee_code(self, obj):
        teacher = obj.teacher
        return teacher.employee_code if teacher else ""

    def get_level_one_validated_by_name(self, obj):
        user = obj.level_one_validated_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def get_level_two_validated_by_name(self, obj):
        user = obj.level_two_validated_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    class Meta:
        model = TeacherPayroll
        fields = "__all__"


class AnnouncementSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = Announcement
        fields = "__all__"


class NotificationSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = Notification
        fields = "__all__"


class SmsProviderConfigSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

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
    def validate_score(self, value):
        numeric_value = Decimal(str(value))
        if numeric_value < Decimal("0") or numeric_value > Decimal("20"):
            raise serializers.ValidationError("La note d'examen doit être comprise entre 0 et 20.")
        return value

    def validate(self, attrs):
        attrs = super().validate(attrs)

        session = attrs.get("session") or getattr(self.instance, "session", None)
        student = attrs.get("student") or getattr(self.instance, "student", None)
        subject = attrs.get("subject") or getattr(self.instance, "subject", None)

        if not session or not student or not subject:
            return attrs

        conflict_qs = ExamResult.objects.filter(
            student=student,
            subject=subject,
            session__academic_year=session.academic_year,
            session__term=session.term,
        )
        if self.instance:
            conflict_qs = conflict_qs.exclude(pk=self.instance.pk)

        if conflict_qs.exists():
            raise serializers.ValidationError(
                {
                    "student": (
                        "Une note d'examen existe déjà pour cet élève, cette matière, "
                        "cette année et cette période."
                    )
                }
            )

        return attrs

    class Meta:
        model = ExamResult
        fields = "__all__"


class SupplierSerializer(serializers.ModelSerializer):
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = Supplier
        fields = "__all__"


class StockItemSerializer(serializers.ModelSerializer):
    is_low_stock = serializers.BooleanField(read_only=True)
    etablissement = serializers.PrimaryKeyRelatedField(read_only=True)

    class Meta:
        model = StockItem
        fields = "__all__"


class StockMovementSerializer(serializers.ModelSerializer):
    class Meta:
        model = StockMovement
        fields = "__all__"


class PromotionDecisionSerializer(serializers.ModelSerializer):
    student_full_name = serializers.SerializerMethodField(read_only=True)
    student_matricule = serializers.SerializerMethodField(read_only=True)
    source_classroom_name = serializers.SerializerMethodField(read_only=True)
    target_classroom_name = serializers.SerializerMethodField(read_only=True)

    def get_student_full_name(self, obj):
        student = obj.student
        user = student.user if student else None
        full_name = user.get_full_name().strip() if user else ""
        if full_name:
            return full_name
        return user.username if user else ""

    def get_student_matricule(self, obj):
        return obj.student.matricule if obj.student else ""

    def get_source_classroom_name(self, obj):
        return obj.source_classroom.name if obj.source_classroom else ""

    def get_target_classroom_name(self, obj):
        return obj.target_classroom.name if obj.target_classroom else ""

    class Meta:
        model = PromotionDecision
        fields = "__all__"


class PromotionRunSerializer(serializers.ModelSerializer):
    decisions = PromotionDecisionSerializer(many=True, read_only=True)

    class Meta:
        model = PromotionRun
        fields = "__all__"
