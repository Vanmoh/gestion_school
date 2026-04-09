from datetime import datetime
from io import BytesIO
import os

from django.conf import settings
from django.db import transaction
from django.db.models import Count, DecimalField, ExpressionWrapper, F, Q, Sum, Value
from django.db.models.functions import Coalesce
from django.http import HttpResponse
from django.utils import timezone
from django.shortcuts import get_object_or_404
from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.pagination import PageNumberPagination
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from fpdf import FPDF
from openpyxl import Workbook
try:
    from openpyxl.drawing.image import Image as XLImage
except Exception:  # pragma: no cover - optional dependency in some environments
    XLImage = None
from openpyxl.styles import Alignment, Font, PatternFill
from apps.accounts.models import UserRole
from apps.accounts.permissions import IsAdminOrDirector, IsReadOnlyForParentStudent, IsSuperAdmin
from apps.common.pagination import StandardResultsSetPagination
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
    Etablissement,
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
    TeacherAvailabilitySlot,
    TeacherScheduleSlot,
    TimetablePublication,
    TeacherPayroll,
    recalculate_term_ranking,
)
from .serializers import (
    AcademicYearSerializer,
    AnnouncementSerializer,
    AttendanceSerializer,
    BookSerializer,
    BorrowSerializer,
    CanteenMenuSerializer,
    CanteenServiceSerializer,
    CanteenSubscriptionSerializer,
    ClassRoomSerializer,
    DisciplineIncidentSerializer,
    EtablissementSerializer,
    ExamPlanningSerializer,
    ExamInvigilationSerializer,
    ExamResultSerializer,
    ExamSessionSerializer,
    ExpenseSerializer,
    GradeSerializer,
    GradeValidationSerializer,
    LevelSerializer,
    NotificationSerializer,
    ParentProfileSerializer,
    PaymentSerializer,
    SectionSerializer,
    StockItemSerializer,
    StockMovementSerializer,
    StudentAcademicHistorySerializer,
    StudentFeeSerializer,
    StudentSerializer,
    SubjectSerializer,
    SupplierSerializer,
    SmsProviderConfigSerializer,
    TeacherAttendanceSerializer,
    TeacherAssignmentSerializer,
    TeacherAvailabilitySlotSerializer,
    TeacherScheduleSlotSerializer,
    TimetablePublicationSerializer,
    TeacherPayrollSerializer,
    TeacherSerializer,
)


class BaseModelViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated, IsReadOnlyForParentStudent]

    def initial(self, request, *args, **kwargs):
        super().initial(request, *args, **kwargs)

        user = request.user
        if not user or not user.is_authenticated:
            return

        if getattr(user, "role", None) == UserRole.SUPER_ADMIN:
            return

        user_etablissement_id = getattr(user, "etablissement_id", None)
        requested_param = request.query_params.get("etablissement")
        if requested_param not in (None, ""):
            try:
                requested_id = int(requested_param)
            except (TypeError, ValueError):
                requested_id = None
            if requested_id and user_etablissement_id and requested_id != user_etablissement_id:
                raise ValidationError({"etablissement": "Acces refuse a un autre etablissement."})

        # Ensure all subsequent per-view scope helpers receive the user-bound
        # establishment for non-superadmin roles.
        if user_etablissement_id:
            request.META["HTTP_X_ETABLISSEMENT_ID"] = str(user_etablissement_id)
            etab = getattr(user, "etablissement", None)
            if etab and getattr(etab, "name", ""):
                request.META["HTTP_X_ETABLISSEMENT_NAME"] = etab.name


class EtablissementScopedModelViewSet(BaseModelViewSet):
    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == UserRole.SUPER_ADMIN and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def _filter_by_scope(self, queryset, field_name="etablissement"):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            return queryset.filter(**{field_name: requested_etablissement})

        if self._has_requested_scope():
            return queryset.none()

        if getattr(user, "role", None) == UserRole.SUPER_ADMIN:
            return queryset

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is None:
            return queryset.none()

        return queryset.filter(**{field_name: user_etablissement})


class GradePagination(PageNumberPagination):
    page_size = 100
    page_size_query_param = "page_size"
    max_page_size = 500


class AcademicYearViewSet(BaseModelViewSet):
    queryset = AcademicYear.objects.all().order_by("-id")
    serializer_class = AcademicYearSerializer


class EtablissementViewSet(viewsets.ModelViewSet):
    queryset = Etablissement.objects.all().order_by('name')
    serializer_class = EtablissementSerializer
    parser_classes = (MultiPartParser, FormParser, JSONParser)

    def get_permissions(self):
        if self.action in ["list", "retrieve"]:
            return [permissions.AllowAny()]
        return [permissions.IsAuthenticated(), IsSuperAdmin()]


class LevelViewSet(BaseModelViewSet):
    queryset = Level.objects.all().order_by("name")
    serializer_class = LevelSerializer


class SectionViewSet(BaseModelViewSet):
    queryset = Section.objects.all().order_by("name")
    serializer_class = SectionSerializer


class ClassRoomViewSet(BaseModelViewSet):
    queryset = ClassRoom.objects.all()
    serializer_class = ClassRoomSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is not None:
            return user_etablissement

        if getattr(user, "role", None) == UserRole.TEACHER:
            teacher_profile = Teacher.objects.select_related("etablissement").filter(user=user).first()
            if teacher_profile:
                return teacher_profile.etablissement

        return None

    def get_queryset(self):
        user = self.request.user
        qs = ClassRoom.objects.select_related("level", "section", "academic_year")
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            qs = qs.filter(etablissement=requested_etablissement)
        elif self._has_requested_scope():
            return qs.none()

        if hasattr(user, "role") and user.role == "super_admin":
            return qs.all()
        return qs.filter(etablissement=user.etablissement)

    def perform_create(self, serializer):
        serializer.save(etablissement=self._resolve_target_etablissement())

    def perform_update(self, serializer):
        serializer.save(etablissement=self._resolve_target_etablissement())


class SubjectViewSet(BaseModelViewSet):
    queryset = Subject.objects.all().order_by("name")
    serializer_class = SubjectSerializer


class TeacherViewSet(BaseModelViewSet):
    queryset = Teacher.objects.all()
    serializer_class = TeacherSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is not None:
            return user_etablissement

        if getattr(user, "role", None) == UserRole.TEACHER:
            teacher_profile = Teacher.objects.select_related("etablissement").filter(user=user).first()
            if teacher_profile:
                return teacher_profile.etablissement

        return None

    def get_queryset(self):
        user = self.request.user
        qs = Teacher.objects.select_related("user", "etablissement")
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            qs = qs.filter(etablissement=requested_etablissement)
        elif self._has_requested_scope():
            return qs.none()

        if hasattr(user, "role") and user.role == "super_admin":
            return qs.all()
        return qs.filter(etablissement=user.etablissement)

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        target_user = serializer.validated_data.get("user")

        if target_user and target_etablissement and target_user.etablissement_id != target_etablissement.id:
            target_user.etablissement = target_etablissement
            target_user.save(update_fields=["etablissement"])

        serializer.save(etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        serializer.save(etablissement=target_etablissement)


class TeacherAssignmentViewSet(BaseModelViewSet):
    queryset = TeacherAssignment.objects.select_related("teacher", "subject", "classroom").all()
    serializer_class = TeacherAssignmentSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = TeacherAssignment.objects.select_related(
            "teacher", "subject", "classroom", "teacher__etablissement", "classroom__etablissement"
        )
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            qs = qs.filter(classroom__etablissement=requested_etablissement)
        elif self._has_requested_scope():
            return qs.none()

        if getattr(user, "role", None) == "super_admin":
            return qs

        return qs.filter(classroom__etablissement=getattr(user, "etablissement", None))

    def _validate_payload_etablissement(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        teacher = serializer.validated_data.get("teacher")
        classroom = serializer.validated_data.get("classroom")

        if target_etablissement is None:
            return

        if teacher and teacher.etablissement_id != target_etablissement.id:
            raise ValidationError({"teacher": "L'enseignant n'appartient pas a l'etablissement actif."})

        if classroom and classroom.etablissement_id != target_etablissement.id:
            raise ValidationError({"classroom": "La classe n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_payload_etablissement(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_payload_etablissement(serializer)
        serializer.save()


class TeacherAvailabilitySlotViewSet(BaseModelViewSet):
    DAY_ORDER = ["MON", "TUE", "WED", "THU", "FRI", "SAT"]
    DAY_LABELS = {
        "MON": "Lundi",
        "TUE": "Mardi",
        "WED": "Mercredi",
        "THU": "Jeudi",
        "FRI": "Vendredi",
        "SAT": "Samedi",
    }

    queryset = TeacherAvailabilitySlot.objects.select_related(
        "teacher",
        "teacher__user",
        "etablissement",
    ).all()
    serializer_class = TeacherAvailabilitySlotSerializer
    filterset_fields = ["teacher", "day_of_week"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            qs = qs.filter(etablissement=requested_etablissement)
        elif self._has_requested_scope():
            return qs.none()
        elif getattr(user, "role", None) != "super_admin":
            target_etablissement = getattr(user, "etablissement", None)
            if target_etablissement is None and getattr(user, "role", None) == UserRole.TEACHER:
                teacher_profile = Teacher.objects.select_related("etablissement").filter(user=user).first()
                if teacher_profile:
                    target_etablissement = teacher_profile.etablissement

            qs = qs.filter(etablissement=target_etablissement)

        teacher_id = self.request.query_params.get("teacher")
        if teacher_id:
            qs = qs.filter(teacher_id=teacher_id)
        return qs

    def _resolve_teacher_for_request(self, serializer):
        user = self.request.user
        payload_teacher = serializer.validated_data.get("teacher")

        if getattr(user, "role", None) == UserRole.TEACHER:
            teacher_profile = Teacher.objects.filter(user=user).first()
            if not teacher_profile:
                raise ValidationError({"teacher": "Profil enseignant introuvable pour l'utilisateur connecté."})
            return teacher_profile

        if payload_teacher:
            return payload_teacher

        raise ValidationError({"teacher": "teacher est requis."})

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        teacher = self._resolve_teacher_for_request(serializer)

        if target_etablissement and teacher.etablissement_id != target_etablissement.id:
            raise ValidationError({"teacher": "Cet enseignant n'appartient pas à l'établissement actif."})

        serializer.save(teacher=teacher, etablissement=target_etablissement or teacher.etablissement)

    def perform_update(self, serializer):
        if getattr(self.request.user, "role", None) == UserRole.TEACHER:
            teacher_profile = Teacher.objects.filter(user=self.request.user).first()
            if not teacher_profile:
                raise ValidationError({"teacher": "Profil enseignant introuvable."})
            serializer.save(teacher=teacher_profile, etablissement=teacher_profile.etablissement)
            return

        target_etablissement = self._resolve_target_etablissement()
        teacher = serializer.validated_data.get("teacher") or getattr(serializer.instance, "teacher", None)
        if target_etablissement and teacher and teacher.etablissement_id != target_etablissement.id:
            raise ValidationError({"teacher": "Cet enseignant n'appartient pas à l'établissement actif."})
        serializer.save(etablissement=target_etablissement or getattr(serializer.instance, "etablissement", None))

    @action(detail=False, methods=["get"], permission_classes=[permissions.IsAuthenticated])
    def grid(self, request):
        try:
            start_hour = int(request.query_params.get("start_hour", 7))
            end_hour = int(request.query_params.get("end_hour", 18))
            slot_minutes = int(request.query_params.get("slot_minutes", 60))
        except (TypeError, ValueError):
            return Response({"detail": "Paramètres horaires invalides."}, status=400)

        if start_hour < 0 or end_hour > 24 or start_hour >= end_hour:
            return Response({"detail": "Plage horaire invalide."}, status=400)
        if slot_minutes <= 0 or slot_minutes > 180:
            return Response({"detail": "slot_minutes invalide."}, status=400)

        from datetime import time

        slots = []
        minute_cursor = start_hour * 60
        end_minutes = end_hour * 60
        while minute_cursor + slot_minutes <= end_minutes:
            slot_start = time(hour=minute_cursor // 60, minute=minute_cursor % 60)
            slot_end_minutes = minute_cursor + slot_minutes
            slot_end = time(hour=slot_end_minutes // 60, minute=slot_end_minutes % 60)
            slots.append((slot_start, slot_end))
            minute_cursor += slot_minutes

        declarations = list(self.get_queryset())
        response_rows = []
        for day_code in self.DAY_ORDER:
            day_cells = []
            day_declarations = [row for row in declarations if row.day_of_week == day_code]
            for slot_start, slot_end in slots:
                taken = None
                for declaration in day_declarations:
                    overlaps = declaration.start_time < slot_end and declaration.end_time > slot_start
                    if overlaps:
                        taken = declaration
                        break

                day_cells.append(
                    {
                        "day_of_week": day_code,
                        "day_label": self.DAY_LABELS.get(day_code, day_code),
                        "start_time": slot_start.strftime("%H:%M:%S"),
                        "end_time": slot_end.strftime("%H:%M:%S"),
                        "status": "indisponible" if taken else "disponible",
                        "availability_id": taken.id if taken else None,
                        "teacher": taken.teacher_id if taken else None,
                        "teacher_name": self._teacher_name(taken.teacher) if taken else "",
                    }
                )

            response_rows.append(
                {
                    "day_of_week": day_code,
                    "day_label": self.DAY_LABELS.get(day_code, day_code),
                    "cells": day_cells,
                }
            )

        return Response(
            {
                "start_hour": start_hour,
                "end_hour": end_hour,
                "slot_minutes": slot_minutes,
                "days": response_rows,
            }
        )

    @staticmethod
    def _teacher_name(teacher):
        user = teacher.user if teacher else None
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username


class TeacherScheduleSlotViewSet(BaseModelViewSet):
    DAY_ORDER = ["MON", "TUE", "WED", "THU", "FRI", "SAT"]
    DAY_LABELS = {
        "MON": "Lundi",
        "TUE": "Mardi",
        "WED": "Mercredi",
        "THU": "Jeudi",
        "FRI": "Vendredi",
        "SAT": "Samedi",
    }

    queryset = TeacherScheduleSlot.objects.select_related(
        "assignment",
        "assignment__teacher",
        "assignment__subject",
        "assignment__classroom",
    ).all()
    serializer_class = TeacherScheduleSlotSerializer
    filterset_fields = ["assignment", "day_of_week"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def _scoped_classroom_queryset(self):
        user = self.request.user
        requested = self._requested_etablissement()
        qs = ClassRoom.objects.select_related("etablissement")

        if requested is not None:
            return qs.filter(etablissement=requested)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(etablissement=getattr(user, "etablissement", None))

    def _get_scoped_classroom_or_404(self, classroom_id):
        return get_object_or_404(self._scoped_classroom_queryset(), id=classroom_id)

    @staticmethod
    def _to_bool(raw_value, default=False):
        if raw_value is None:
            return default
        if isinstance(raw_value, bool):
            return raw_value
        return str(raw_value).strip().lower() in {"1", "true", "yes", "on"}

    @staticmethod
    def _minutes(time_value):
        return time_value.hour * 60 + time_value.minute

    @classmethod
    def _overlap(cls, start_a, end_a, start_b, end_b):
        return cls._minutes(start_a) < cls._minutes(end_b) and cls._minutes(end_a) > cls._minutes(start_b)

    @staticmethod
    def _slot_range_label(slot):
        return f"{slot.start_time.strftime('%H:%M')}-{slot.end_time.strftime('%H:%M')}"

    @staticmethod
    def _pdf_text(value):
        return str(value or "").encode("latin-1", "replace").decode("latin-1")

    @classmethod
    def _slot_short_label(cls, slot):
        assignment = slot.assignment
        subject_code = assignment.subject.code if assignment and assignment.subject else "MAT"
        teacher = assignment.teacher if assignment else None
        teacher_label = cls._teacher_name(teacher) or (teacher.employee_code if teacher else "ENS")
        room = (slot.room or "").strip()
        room_label = f" [{room}]" if room else ""
        return f"{subject_code} ({teacher_label}){room_label}"

    @classmethod
    def _sorted_ranges(cls, matrix):
        def key_func(range_label):
            start_raw = range_label.split("-")[0]
            start = datetime.strptime(start_raw, "%H:%M")
            return start.hour * 60 + start.minute

        return sorted(matrix.keys(), key=key_func)

    @classmethod
    def _build_class_matrix(cls, slots):
        matrix = {}
        for slot in slots:
            range_label = cls._slot_range_label(slot)
            day_map = matrix.setdefault(
                range_label,
                {day: [] for day in cls.DAY_ORDER},
            )
            day_map[slot.day_of_week].append(cls._slot_short_label(slot))

        for day_map in matrix.values():
            for entries in day_map.values():
                entries.sort()

        return matrix

    @classmethod
    def _sheet_title(cls, class_name):
        cleaned = class_name.strip() or "Classe"
        return cleaned[:31]

    @staticmethod
    def _etablissement_logo_path(etablissement):
        if not etablissement:
            return None

        logo_field = getattr(etablissement, "logo", None)
        if not logo_field:
            return None

        direct_path = str(getattr(logo_field, "path", "") or "").strip()
        if direct_path and os.path.exists(direct_path):
            return direct_path

        logo_name = str(getattr(logo_field, "name", "") or "").strip()
        media_root = str(getattr(settings, "MEDIA_ROOT", "") or "").strip()
        if logo_name and media_root:
            candidate = os.path.join(media_root, logo_name)
            if os.path.exists(candidate):
                return candidate

        return None

    def _etablissement_meta_lines(self, classroom):
        etablissement = getattr(classroom, "etablissement", None)
        if not etablissement:
            etablissement = self._requested_etablissement() or self._resolve_target_etablissement()

        # Some legacy classes may not yet be linked to an etablissement;
        # in that case, keep the active scope name visible in exports.
        if not etablissement:
            requested_name = self._requested_etablissement_name()
            if requested_name:
                return {
                    "name": requested_name,
                    "details": "",
                }

        if not etablissement:
            return {
                "name": "Etablissement non defini",
                "details": "",
            }

        details = []
        if etablissement.address:
            details.append(etablissement.address)
        if etablissement.phone:
            details.append(f"Tel: {etablissement.phone}")
        if etablissement.email:
            details.append(etablissement.email)

        return {
            "name": etablissement.name,
            "details": " | ".join(details),
            "logo_path": self._etablissement_logo_path(etablissement),
        }

    @staticmethod
    def _teacher_name(teacher):
        user = teacher.user if teacher else None
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def _parse_classroom_id(self, request):
        raw = request.data.get("classroom")
        if raw is None:
            raw = request.query_params.get("classroom")
        if raw is None:
            return None
        try:
            return int(raw)
        except (TypeError, ValueError):
            return None

    def _publication_response(self, classroom):
        publication = TimetablePublication.objects.filter(classroom=classroom).first()
        if publication:
            payload = TimetablePublicationSerializer(publication).data
        else:
            payload = {
                "id": None,
                "classroom": classroom.id,
                "classroom_name": classroom.name,
                "is_published": False,
                "is_locked": False,
                "published_by": None,
                "published_by_name": "",
                "published_at": None,
                "notes": "",
            }

        slot_count = self.get_queryset().filter(assignment__classroom=classroom).count()
        payload["slot_count"] = slot_count
        return payload

    def _class_slots_queryset(self, classroom):
        return self.get_queryset().filter(assignment__classroom=classroom)

    def _teacher_workload_rows(self, slots_queryset):
        rows = {}
        for slot in slots_queryset:
            assignment = slot.assignment
            teacher = assignment.teacher
            teacher_id = teacher.id
            row = rows.setdefault(
                teacher_id,
                {
                    "teacher": teacher.id,
                    "teacher_code": teacher.employee_code,
                    "teacher_name": self._teacher_name(teacher),
                    "slot_count": 0,
                    "class_count": 0,
                    "classrooms": set(),
                    "per_day_minutes": {day: 0 for day in self.DAY_ORDER},
                    "total_minutes": 0,
                },
            )

            duration = self._minutes(slot.end_time) - self._minutes(slot.start_time)
            if duration < 0:
                duration = 0

            row["slot_count"] += 1
            row["total_minutes"] += duration
            row["per_day_minutes"][slot.day_of_week] += duration
            row["classrooms"].add(assignment.classroom_id)

        result = []
        for row in rows.values():
            row["class_count"] = len(row["classrooms"])
            del row["classrooms"]
            row["total_hours"] = round(row["total_minutes"] / 60, 2)
            row["per_day_hours"] = {
                day: round(minutes / 60, 2)
                for day, minutes in row["per_day_minutes"].items()
            }
            if row["total_minutes"] >= 26 * 60:
                row["load_level"] = "overload"
            elif row["total_minutes"] >= 20 * 60:
                row["load_level"] = "watch"
            else:
                row["load_level"] = "ok"
            result.append(row)

        result.sort(key=lambda item: (-item["total_minutes"], item["teacher_code"]))
        return result

    @staticmethod
    def _assignment_target_maps(target_assignments):
        exact = {}
        by_subject = {}
        for assignment in target_assignments:
            exact[(assignment.subject_id, assignment.teacher_id)] = assignment
            by_subject.setdefault(assignment.subject_id, []).append(assignment)

        for assignments in by_subject.values():
            assignments.sort(key=lambda assignment: (assignment.teacher_id, assignment.id))

        return exact, by_subject

    def _resolve_target_assignment(self, source_assignment, exact_map, subject_map):
        exact = exact_map.get((source_assignment.subject_id, source_assignment.teacher_id))
        if exact:
            return exact, "exact"

        subject_matches = subject_map.get(source_assignment.subject_id) or []
        if subject_matches:
            return subject_matches[0], "subject-fallback"

        return None, "unmapped"

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        publication = TimetablePublication.objects.filter(
            classroom=instance.assignment.classroom,
            is_locked=True,
        ).first()
        if publication:
            return Response(
                {
                    "detail": "Emploi du temps verrouillé pour cette classe. "
                    "Déverrouillez avant toute suppression."
                },
                status=400,
            )
        return super().destroy(request, *args, **kwargs)

    def _validate_assignment_scope(self, serializer):
        assignment = serializer.validated_data.get("assignment")
        if not assignment:
            return

        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement is None:
            return

        if assignment.classroom.etablissement_id != target_etablissement.id:
            raise ValidationError({
                "assignment": "Cette affectation n'appartient pas a l'etablissement actif."
            })

    def perform_create(self, serializer):
        self._validate_assignment_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_assignment_scope(serializer)
        serializer.save()

    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            queryset = queryset.filter(assignment__classroom__etablissement=requested_etablissement)
        elif self._has_requested_scope():
            return queryset.none()
        elif getattr(user, "role", None) != "super_admin":
            queryset = queryset.filter(assignment__classroom__etablissement=getattr(user, "etablissement", None))

        classroom = self.request.query_params.get("classroom")
        if classroom:
            queryset = queryset.filter(assignment__classroom_id=classroom)
        return queryset

    @action(detail=False, methods=["get"], permission_classes=[permissions.IsAuthenticated])
    def publication_status(self, request):
        classroom_id = self._parse_classroom_id(request)
        if not classroom_id:
            return Response({"detail": "classroom est requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)
        return Response(self._publication_response(classroom))

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def publish_class(self, request):
        classroom_id = self._parse_classroom_id(request)
        if not classroom_id:
            return Response({"detail": "classroom est requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)

        lock_value = request.data.get("lock")
        if isinstance(lock_value, bool):
            lock_after_publish = lock_value
        elif lock_value is None:
            lock_after_publish = True
        else:
            lock_after_publish = str(lock_value).strip().lower() in {"1", "true", "yes", "on"}

        notes = str(request.data.get("notes") or "").strip()
        publication, _ = TimetablePublication.objects.get_or_create(classroom=classroom)
        publication.is_published = True
        publication.is_locked = lock_after_publish
        publication.published_by = request.user
        publication.published_at = timezone.now()
        publication.notes = notes
        publication.save()

        return Response(self._publication_response(classroom))

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def unpublish_class(self, request):
        classroom_id = self._parse_classroom_id(request)
        if not classroom_id:
            return Response({"detail": "classroom est requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)
        publication, _ = TimetablePublication.objects.get_or_create(classroom=classroom)
        publication.is_published = False
        publication.is_locked = False
        publication.published_by = None
        publication.published_at = None
        publication.notes = ""
        publication.save()

        return Response(self._publication_response(classroom))

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def lock_class(self, request):
        classroom_id = self._parse_classroom_id(request)
        if not classroom_id:
            return Response({"detail": "classroom est requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)
        publication, _ = TimetablePublication.objects.get_or_create(classroom=classroom)

        if not publication.is_published:
            return Response(
                {"detail": "Publiez d'abord l'emploi du temps avant de le verrouiller."},
                status=400,
            )

        publication.is_locked = True
        publication.save(update_fields=["is_locked", "updated_at"])
        return Response(self._publication_response(classroom))

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def unlock_class(self, request):
        classroom_id = self._parse_classroom_id(request)
        if not classroom_id:
            return Response({"detail": "classroom est requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)
        publication, _ = TimetablePublication.objects.get_or_create(classroom=classroom)
        publication.is_locked = False
        publication.save(update_fields=["is_locked", "updated_at"])
        return Response(self._publication_response(classroom))

    @action(detail=False, methods=["get"], permission_classes=[permissions.IsAuthenticated])
    def teacher_workload(self, request):
        classroom_id = self._parse_classroom_id(request)
        queryset = self.get_queryset()
        if classroom_id:
            queryset = queryset.filter(assignment__classroom_id=classroom_id)

        rows = self._teacher_workload_rows(queryset)
        total_minutes = sum(item["total_minutes"] for item in rows)
        payload = {
            "classroom": classroom_id,
            "teacher_count": len(rows),
            "total_minutes": total_minutes,
            "total_hours": round(total_minutes / 60, 2),
            "items": rows,
        }
        return Response(payload)

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def duplicate_schedule(self, request):
        source_classroom_id = request.data.get("source_classroom")
        target_classroom_id = request.data.get("target_classroom")

        try:
            source_classroom_id = int(source_classroom_id)
            target_classroom_id = int(target_classroom_id)
        except (TypeError, ValueError):
            return Response(
                {"detail": "source_classroom et target_classroom sont requis."},
                status=400,
            )

        if source_classroom_id == target_classroom_id:
            return Response(
                {"detail": "La classe source et la classe cible doivent être différentes."},
                status=400,
            )

        source_classroom = self._get_scoped_classroom_or_404(source_classroom_id)
        target_classroom = self._get_scoped_classroom_or_404(target_classroom_id)

        publication = TimetablePublication.objects.filter(
            classroom=target_classroom,
            is_locked=True,
        ).first()
        if publication:
            return Response(
                {
                    "detail": "Classe cible verrouillée. Déverrouillez avant duplication.",
                },
                status=400,
            )

        requested_days = request.data.get("days")
        if isinstance(requested_days, str):
            requested_days = [item.strip().upper() for item in requested_days.split(",") if item.strip()]
        if not isinstance(requested_days, list) or not requested_days:
            requested_days = list(self.DAY_ORDER)
        copy_days = [day for day in requested_days if day in self.DAY_ORDER]
        if not copy_days:
            return Response({"detail": "Aucun jour valide fourni."}, status=400)

        overwrite = self._to_bool(request.data.get("overwrite"), default=False)
        keep_room = self._to_bool(request.data.get("keep_room"), default=True)

        source_slots = list(
            self.get_queryset()
            .filter(assignment__classroom=source_classroom, day_of_week__in=copy_days)
            .order_by("day_of_week", "start_time", "end_time", "id")
        )
        if not source_slots:
            return Response(
                {"detail": "Aucun créneau à copier pour la classe source."},
                status=400,
            )

        target_assignments = list(
            TeacherAssignment.objects.select_related("teacher", "subject", "classroom").filter(
                classroom=target_classroom
            )
        )
        if not target_assignments:
            return Response(
                {
                    "detail": "La classe cible n'a aucune affectation. Ajoutez d'abord les affectations.",
                },
                status=400,
            )

        exact_map, subject_map = self._assignment_target_maps(target_assignments)

        summary = {
            "source_classroom": source_classroom.id,
            "target_classroom": target_classroom.id,
            "days": copy_days,
            "overwrite": overwrite,
            "keep_room": keep_room,
            "source_slots": len(source_slots),
            "deleted": 0,
            "created": 0,
            "updated": 0,
            "skipped_unmapped": 0,
            "skipped_conflicts": 0,
            "mapping_examples": [],
            "conflicts": [],
            "unmapped": [],
        }

        with transaction.atomic():
            if overwrite:
                delete_qs = TeacherScheduleSlot.objects.filter(
                    assignment__classroom=target_classroom,
                    day_of_week__in=copy_days,
                )
                deleted_count, _ = delete_qs.delete()
                summary["deleted"] = deleted_count

            for source_slot in source_slots:
                source_assignment = source_slot.assignment
                target_assignment, mapping_mode = self._resolve_target_assignment(
                    source_assignment,
                    exact_map,
                    subject_map,
                )

                if not target_assignment:
                    summary["skipped_unmapped"] += 1
                    if len(summary["unmapped"]) < 20:
                        summary["unmapped"].append(
                            {
                                "day": source_slot.day_of_week,
                                "time": self._slot_range_label(source_slot),
                                "subject_code": source_assignment.subject.code,
                                "teacher_code": source_assignment.teacher.employee_code,
                            }
                        )
                    continue

                room_value = source_slot.room if keep_room else ""

                overlapping = TeacherScheduleSlot.objects.select_related(
                    "assignment",
                    "assignment__teacher",
                    "assignment__subject",
                    "assignment__classroom",
                ).filter(
                    day_of_week=source_slot.day_of_week,
                    start_time__lt=source_slot.end_time,
                    end_time__gt=source_slot.start_time,
                ).exclude(
                    assignment=target_assignment,
                    start_time=source_slot.start_time,
                    end_time=source_slot.end_time,
                )

                class_conflict = overlapping.filter(
                    assignment__classroom=target_classroom
                ).exists()
                teacher_conflict = overlapping.filter(
                    assignment__teacher=target_assignment.teacher
                ).exists()
                room_conflict = False
                if room_value.strip():
                    room_conflict = overlapping.exclude(room__exact="").filter(
                        room__iexact=room_value.strip()
                    ).exists()

                if class_conflict or teacher_conflict or room_conflict:
                    summary["skipped_conflicts"] += 1
                    if len(summary["conflicts"]) < 20:
                        labels = []
                        if class_conflict:
                            labels.append("classe")
                        if teacher_conflict:
                            labels.append("enseignant")
                        if room_conflict:
                            labels.append("salle")
                        summary["conflicts"].append(
                            {
                                "day": source_slot.day_of_week,
                                "time": self._slot_range_label(source_slot),
                                "subject_code": target_assignment.subject.code,
                                "teacher_code": target_assignment.teacher.employee_code,
                                "types": labels,
                            }
                        )
                    continue

                duplicated, created = TeacherScheduleSlot.objects.update_or_create(
                    assignment=target_assignment,
                    day_of_week=source_slot.day_of_week,
                    start_time=source_slot.start_time,
                    end_time=source_slot.end_time,
                    defaults={"room": room_value},
                )

                if created:
                    summary["created"] += 1
                else:
                    summary["updated"] += 1

                if len(summary["mapping_examples"]) < 20:
                    summary["mapping_examples"].append(
                        {
                            "day": duplicated.day_of_week,
                            "time": self._slot_range_label(duplicated),
                            "subject_code": duplicated.assignment.subject.code,
                            "teacher_code": duplicated.assignment.teacher.employee_code,
                            "mode": mapping_mode,
                        }
                    )

        return Response(summary)

    @action(detail=False, methods=["get"], permission_classes=[permissions.IsAuthenticated])
    def export_excel(self, request):
        classroom_id = self._parse_classroom_id(request)

        if classroom_id:
            classrooms = list(self._scoped_classroom_queryset().filter(id=classroom_id).order_by("name"))
            if not classrooms:
                return Response({"detail": "Classe introuvable."}, status=404)
            filename = f"planning_classe_{classroom_id}.xlsx"
        else:
            classrooms = list(self._scoped_classroom_queryset().order_by("name"))
            filename = "planning_global_multi_classes.xlsx"

        wb = Workbook()
        default_sheet = wb.active
        wb.remove(default_sheet)

        workload_rows = self._teacher_workload_rows(self.get_queryset())
        ws_load = wb.create_sheet("Charge Enseignants")
        ws_load.append(
            [
                "Code enseignant",
                "Nom",
                "Horaires",
                "Classes",
                "Lundi",
                "Mardi",
                "Mercredi",
                "Jeudi",
                "Vendredi",
                "Samedi",
                "Total (h)",
                "Niveau",
            ]
        )
        for row in workload_rows:
            ws_load.append(
                [
                    row["teacher_code"],
                    row["teacher_name"],
                    row["slot_count"],
                    row["class_count"],
                    row["per_day_hours"]["MON"],
                    row["per_day_hours"]["TUE"],
                    row["per_day_hours"]["WED"],
                    row["per_day_hours"]["THU"],
                    row["per_day_hours"]["FRI"],
                    row["per_day_hours"]["SAT"],
                    row["total_hours"],
                    row["load_level"],
                ]
            )

        header_fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")
        for row in ws_load.iter_rows(min_row=1, max_row=1):
            for cell in row:
                cell.font = Font(bold=True)
                cell.fill = header_fill
                cell.alignment = Alignment(horizontal="center", vertical="center")

        for classroom in classrooms:
            ws = wb.create_sheet(self._sheet_title(classroom.name))
            etab_meta = self._etablissement_meta_lines(classroom)
            ws.merge_cells("A1:G1")
            ws["A1"] = f"{etab_meta['name']} - Emploi du temps"
            ws["A1"].font = Font(size=13, bold=True)
            ws["A1"].alignment = Alignment(horizontal="center", vertical="center")

            ws.merge_cells("A2:G2")
            ws["A2"] = f"Classe: {classroom.name}"
            ws["A2"].font = Font(size=11, bold=True)
            ws["A2"].alignment = Alignment(horizontal="center", vertical="center")

            ws.merge_cells("A3:G3")
            generated_label = f"Genere le {timezone.localtime().strftime('%d/%m/%Y %H:%M')}"
            ws["A3"] = (
                f"{etab_meta['details']} | {generated_label}"
                if etab_meta["details"]
                else generated_label
            )
            ws["A3"].alignment = Alignment(horizontal="center", vertical="center")

            ws.row_dimensions[1].height = 24
            ws.row_dimensions[2].height = 20
            ws.row_dimensions[3].height = 18

            if XLImage and etab_meta.get("logo_path"):
                try:
                    logo = XLImage(etab_meta["logo_path"])
                    logo.width = 46
                    logo.height = 46
                    ws.add_image(logo, "G1")
                except Exception:
                    pass

            headers = ["Horaire", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
            ws.append(headers)
            for index, header in enumerate(headers, start=1):
                cell = ws.cell(row=4, column=index)
                cell.value = header
                cell.font = Font(bold=True)
                cell.fill = header_fill
                cell.alignment = Alignment(horizontal="center", vertical="center")

            class_slots = list(
                self._class_slots_queryset(classroom)
                .order_by("day_of_week", "start_time", "end_time", "id")
            )
            matrix = self._build_class_matrix(class_slots)
            ranges = self._sorted_ranges(matrix)

            if not ranges:
                ws.append(["Aucun horaire planifié", "", "", "", "", "", ""])
            else:
                for range_label in ranges:
                    day_map = matrix[range_label]
                    ws.append(
                        [
                            range_label,
                            " | ".join(day_map["MON"]),
                            " | ".join(day_map["TUE"]),
                            " | ".join(day_map["WED"]),
                            " | ".join(day_map["THU"]),
                            " | ".join(day_map["FRI"]),
                            " | ".join(day_map["SAT"]),
                        ]
                    )

            ws.column_dimensions["A"].width = 18
            for col in ["B", "C", "D", "E", "F", "G"]:
                ws.column_dimensions[col].width = 28

            for row in ws.iter_rows(min_row=5, max_row=ws.max_row, min_col=1, max_col=7):
                for cell in row:
                    cell.alignment = Alignment(vertical="top", wrap_text=True)

        stream = BytesIO()
        wb.save(stream)
        response = HttpResponse(
            stream.getvalue(),
            content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        response["Cache-Control"] = "no-store, max-age=0"
        return response

    @action(detail=False, methods=["get"], permission_classes=[permissions.IsAuthenticated])
    def export_pdf(self, request):
        classroom_id = self._parse_classroom_id(request)

        if classroom_id:
            classrooms = list(self._scoped_classroom_queryset().filter(id=classroom_id).order_by("name"))
            if not classrooms:
                return Response({"detail": "Classe introuvable."}, status=404)
            filename = f"planning_classe_{classroom_id}.pdf"
        else:
            classrooms = list(self._scoped_classroom_queryset().order_by("name"))
            filename = "planning_global_multi_classes.pdf"

        pdf = FPDF(orientation="L", unit="mm", format="A4")
        pdf.set_auto_page_break(auto=True, margin=12)

        col_widths = [28, 41, 41, 41, 41, 41, 41]

        def draw_headers():
            pdf.set_font("Helvetica", "B", 9)
            for header, width in zip(
                ["Horaire", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"],
                col_widths,
            ):
                pdf.cell(width, 8, self._pdf_text(header), border=1, align="C")
            pdf.ln(8)

        for classroom in classrooms:
            class_slots = list(
                self._class_slots_queryset(classroom)
                .order_by("day_of_week", "start_time", "end_time", "id")
            )
            matrix = self._build_class_matrix(class_slots)
            ranges = self._sorted_ranges(matrix)
            etab_meta = self._etablissement_meta_lines(classroom)

            pdf.add_page()
            title_x = 10
            logo_path = etab_meta.get("logo_path")
            if logo_path:
                try:
                    pdf.image(logo_path, x=10, y=8, w=15)
                    title_x = 28
                except Exception:
                    title_x = 10

            pdf.set_font("Helvetica", "B", 14)
            pdf.set_x(title_x)
            pdf.cell(
                0,
                8,
                self._pdf_text(f"{etab_meta['name']} - Emploi du temps"),
                ln=1,
            )
            pdf.set_font("Helvetica", "B", 11)
            pdf.set_x(title_x)
            pdf.cell(
                0,
                6,
                self._pdf_text(f"Classe: {classroom.name}"),
                ln=1,
            )
            pdf.set_font("Helvetica", "", 9)
            if etab_meta["details"]:
                pdf.set_x(title_x)
                pdf.cell(0, 6, self._pdf_text(etab_meta["details"]), ln=1)
            pdf.set_x(title_x)
            pdf.cell(
                0,
                6,
                self._pdf_text(f"Généré le {timezone.localtime().strftime('%d/%m/%Y %H:%M')}"),
                ln=1,
            )
            pdf.ln(2)

            draw_headers()

            if not ranges:
                pdf.set_font("Helvetica", "", 10)
                pdf.cell(0, 8, self._pdf_text("Aucun horaire planifié"), ln=1)
                continue

            for range_label in ranges:
                if pdf.get_y() > 185:
                    pdf.add_page()
                    draw_headers()

                day_map = matrix[range_label]
                values = [
                    range_label,
                    " | ".join(day_map["MON"]),
                    " | ".join(day_map["TUE"]),
                    " | ".join(day_map["WED"]),
                    " | ".join(day_map["THU"]),
                    " | ".join(day_map["FRI"]),
                    " | ".join(day_map["SAT"]),
                ]

                pdf.set_font("Helvetica", "", 8)
                for value, width in zip(values, col_widths):
                    text = self._pdf_text(value)
                    if len(text) > 65:
                        text = f"{text[:62]}..."
                    pdf.cell(width, 8, text, border=1)
                pdf.ln(8)

        response = HttpResponse(bytes(pdf.output()), content_type="application/pdf")
        response["Content-Disposition"] = f'attachment; filename="{filename}"'
        response["Cache-Control"] = "no-store, max-age=0"
        return response


class TimetablePublicationViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = TimetablePublication.objects.select_related("classroom", "published_by").all().order_by("classroom__name")
    serializer_class = TimetablePublicationSerializer
    permission_classes = [permissions.IsAuthenticated]
    filterset_fields = ["classroom", "is_published", "is_locked"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            return qs.filter(classroom__etablissement=requested_etablissement)

        if self._has_requested_scope():
            return qs.none()

        if getattr(user, "role", None) == "super_admin":
            return qs

        return qs.filter(classroom__etablissement=getattr(user, "etablissement", None))


class ParentProfileViewSet(BaseModelViewSet):
    queryset = ParentProfile.objects.all()
    serializer_class = ParentProfileSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def get_queryset(self):
        user = self.request.user
        qs = ParentProfile.objects.select_related("user")

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(etablissement=requested_etablissement)

        if self._has_requested_scope():
            return qs.none()

        if hasattr(user, "role") and user.role == "super_admin":
            user_etablissement = getattr(user, "etablissement", None)
            if user_etablissement is not None:
                return qs.filter(etablissement=user_etablissement)
            return qs.none()

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is None:
            return qs.none()
        return qs.filter(etablissement=user_etablissement)

    def perform_create(self, serializer):
        user = self.request.user
        target = self._requested_etablissement() if getattr(user, "role", None) == UserRole.SUPER_ADMIN else getattr(user, "etablissement", None)
        if getattr(user, "role", None) == UserRole.SUPER_ADMIN and target is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(etablissement=target)

    def perform_update(self, serializer):
        user = self.request.user
        target = self._requested_etablissement() if getattr(user, "role", None) == UserRole.SUPER_ADMIN else getattr(user, "etablissement", None)
        if getattr(user, "role", None) == UserRole.SUPER_ADMIN and target is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(etablissement=target)


class StudentViewSet(BaseModelViewSet):
    queryset = Student.objects.all()
    serializer_class = StudentSerializer
    parser_classes = (MultiPartParser, FormParser, JSONParser)
    pagination_class = StandardResultsSetPagination
    filterset_fields = [
        "classroom",
        "is_archived",
        "parent",
        "user",
        "etablissement",
        "enrollment_date",
        "created_at",
    ]
    search_fields = [
        "matricule",
        "user__first_name",
        "user__last_name",
        "user__username",
        "classroom__name",
        "parent__user__first_name",
        "parent__user__last_name",
    ]
    ordering_fields = [
        "created_at",
        "matricule",
        "enrollment_date",
        "user__last_name",
        "user__first_name",
        "classroom__name",
    ]
    ordering = ["-created_at"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin":
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def _validate_student_scope(self, serializer, instance=None):
        classroom = serializer.validated_data.get("classroom") or (instance.classroom if instance else None)
        parent = serializer.validated_data.get("parent") or (instance.parent if instance else None)
        target_etablissement = self._resolve_target_etablissement()

        if target_etablissement is None and classroom is not None:
            target_etablissement = classroom.etablissement

        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})

        if target_etablissement is None:
            return None

        if classroom and classroom.etablissement_id != target_etablissement.id:
            raise ValidationError({"classroom": "La classe n'appartient pas a l'etablissement actif."})

        if parent and parent.etablissement_id != target_etablissement.id:
            raise ValidationError({"parent": "Le parent n'appartient pas a l'etablissement actif."})

        user_obj = serializer.validated_data.get("user") or (instance.user if instance else None)
        if user_obj and user_obj.etablissement_id not in (None, target_etablissement.id):
            raise ValidationError({"user": "Le compte utilisateur n'appartient pas a l'etablissement actif."})

        if user_obj and user_obj.etablissement_id is None:
            user_obj.etablissement = target_etablissement
            user_obj.save(update_fields=["etablissement"])

        return target_etablissement

    def get_queryset(self):
        user = self.request.user
        qs = Student.objects.select_related("user", "classroom", "parent", "parent__user")
        role = getattr(user, "role", "")
        if role == UserRole.STUDENT:
            return qs.filter(user_id=user.id)
        if role == UserRole.PARENT:
            return qs.filter(parent__user_id=user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(
                Q(classroom__etablissement=requested_etablissement)
                | Q(classroom__isnull=True, etablissement=requested_etablissement)
            )

        if self._has_requested_scope():
            return qs.none()

        if hasattr(user, "role") and user.role == "super_admin":
            return qs.none()

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is None:
            return qs.none()
        return qs.filter(
            Q(classroom__etablissement=user_etablissement)
            | Q(classroom__isnull=True, etablissement=user_etablissement)
        )

    def perform_create(self, serializer):
        target_etablissement = self._validate_student_scope(serializer)
        serializer.save(etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._validate_student_scope(serializer, instance=serializer.instance)
        serializer.save(etablissement=target_etablissement)

    @action(
        detail=True,
        methods=["post", "patch"],
        url_path="upload-photo",
        parser_classes=[MultiPartParser, FormParser],
    )
    def upload_photo(self, request, pk=None):
        student = self.get_object()
        uploaded_photo = request.FILES.get("photo") or request.data.get("photo")
        if not uploaded_photo:
            return Response({"photo": ["Aucune image fournie."]}, status=400)

        serializer = self.get_serializer(
            student,
            data={"photo": uploaded_photo},
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        serializer.save(etablissement=student.etablissement)
        return Response(serializer.data)


class StudentAcademicHistoryViewSet(BaseModelViewSet):
    queryset = StudentAcademicHistory.objects.select_related("student", "academic_year", "classroom").all().order_by("-academic_year_id", "rank")
    serializer_class = StudentAcademicHistorySerializer
    filterset_fields = ["student", "academic_year", "classroom"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user
        role = getattr(user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return queryset.filter(classroom__etablissement=requested_etablissement)

        if self._has_requested_scope():
            return queryset.none()

        if role == UserRole.SUPER_ADMIN:
            return queryset

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is None:
            return queryset.none()
        return queryset.filter(classroom__etablissement=user_etablissement)


class GradeViewSet(BaseModelViewSet):
    queryset = Grade.objects.select_related("student", "subject", "classroom", "academic_year").all().order_by("-id")
    serializer_class = GradeSerializer
    pagination_class = GradePagination
    filterset_fields = ["classroom", "academic_year", "term", "subject", "student"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def _scoped_classroom_queryset(self):
        user = self.request.user
        requested = self._requested_etablissement()
        qs = ClassRoom.objects.select_related("etablissement")

        if requested is not None:
            return qs.filter(etablissement=requested)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(etablissement=getattr(user, "etablissement", None))

    def _get_scoped_classroom_or_404(self, classroom_id):
        return get_object_or_404(self._scoped_classroom_queryset(), id=classroom_id)

    def _validate_grade_scope(self, serializer, instance=None):
        student = serializer.validated_data.get("student") or (instance.student if instance else None)
        classroom = serializer.validated_data.get("classroom") or (instance.classroom if instance else None)

        if not student or not classroom:
            return

        role = getattr(self.request.user, "role", "")
        if role == UserRole.STUDENT and student.user_id != self.request.user.id:
            raise ValidationError({"student": "Vous ne pouvez saisir que vos propres notes."})
        if role == UserRole.PARENT:
            if not student.parent or student.parent.user_id != self.request.user.id:
                raise ValidationError({"student": "Vous ne pouvez saisir que les notes de vos enfants."})

        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement is None:
            return

        student_etablissement_id = getattr(student, "etablissement_id", None)
        classroom_etablissement_id = getattr(getattr(student, "classroom", None), "etablissement_id", None)
        if student_etablissement_id != target_etablissement.id and classroom_etablissement_id != target_etablissement.id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})
        if classroom.etablissement_id != target_etablissement.id:
            raise ValidationError({"classroom": "La classe n'appartient pas a l'etablissement actif."})

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return queryset.filter(classroom__etablissement=requested_etablissement)

        if self._has_requested_scope():
            return queryset.none()

        if getattr(self.request.user, "role", None) == "super_admin":
            return queryset

        return queryset.filter(classroom__etablissement=getattr(self.request.user, "etablissement", None))

    @staticmethod
    def _parse_positive_int(value):
        try:
            parsed = int(value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    @staticmethod
    def _normalize_term_or_none(value):
        return normalize_term(value)

    @staticmethod
    def _locked_term_message(prefix="Modification"):
        return f"Cette période est validée par la direction. {prefix} interdite."

    @staticmethod
    def _value_changed(old_value, new_value):
        if hasattr(old_value, "pk") and hasattr(new_value, "pk"):
            return old_value.pk != new_value.pk
        return old_value != new_value

    def _immutable_fields_changed(self, instance, validated_data):
        immutable_fields = ("student", "subject", "classroom", "academic_year", "term")
        changed = []
        for field in immutable_fields:
            if field not in validated_data:
                continue
            old_value = getattr(instance, field)
            new_value = validated_data[field]
            if self._value_changed(old_value, new_value):
                changed.append(field)
        return changed

    def _is_term_validated(self, classroom_id, academic_year_id, term):
        normalized_term = self._normalize_term_or_none(term)
        if not classroom_id or not academic_year_id or not normalized_term:
            return False
        return GradeValidation.objects.filter(
            classroom_id=classroom_id,
            academic_year_id=academic_year_id,
            term=normalized_term,
            is_validated=True,
        ).exists()

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        self._validate_grade_scope(serializer)
        classroom_id = serializer.validated_data.get("classroom").id if serializer.validated_data.get("classroom") else None
        academic_year_id = serializer.validated_data.get("academic_year").id if serializer.validated_data.get("academic_year") else None
        term = serializer.validated_data.get("term")
        if self._is_term_validated(classroom_id, academic_year_id, term):
            return Response({"detail": self._locked_term_message()}, status=400)
        self.perform_create(serializer)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=201, headers=headers)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop("partial", False)
        instance = self.get_object()

        if self._is_term_validated(instance.classroom_id, instance.academic_year_id, instance.term):
            return Response({"detail": self._locked_term_message()}, status=400)

        serializer = self.get_serializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        self._validate_grade_scope(serializer, instance=instance)

        immutable_changed = self._immutable_fields_changed(instance, serializer.validated_data)
        if immutable_changed:
            return Response(
                {
                    "detail": (
                        "Les champs student, subject, classroom, academic_year et term "
                        "sont immuables après création."
                    ),
                    "fields": immutable_changed,
                },
                status=400,
            )

        classroom = serializer.validated_data.get("classroom", instance.classroom)
        academic_year = serializer.validated_data.get("academic_year", instance.academic_year)
        term = serializer.validated_data.get("term", instance.term)

        if self._is_term_validated(classroom.id, academic_year.id, term):
            return Response({"detail": self._locked_term_message()}, status=400)

        self.perform_update(serializer)
        return Response(serializer.data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        if self._is_term_validated(instance.classroom_id, instance.academic_year_id, instance.term):
            return Response({"detail": self._locked_term_message(prefix="Suppression")}, status=400)
        return super().destroy(request, *args, **kwargs)

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def recalculate_ranking(self, request):
        classroom_id = self._parse_positive_int(request.data.get("classroom"))
        academic_year_id = self._parse_positive_int(request.data.get("academic_year"))
        term = self._normalize_term_or_none(request.data.get("term"))

        if not classroom_id or not academic_year_id or not term:
            return Response(
                {"detail": "classroom, academic_year et term (T1/T2/T3) sont requis."},
                status=400,
            )

        classroom = self._get_scoped_classroom_or_404(classroom_id)
        academic_year = get_object_or_404(AcademicYear, id=academic_year_id)

        if self._is_term_validated(classroom.id, academic_year.id, term):
            return Response({"detail": self._locked_term_message(prefix="Recalcul")}, status=400)

        recalculate_term_ranking(classroom, academic_year, term)
        return Response({"detail": "Classement recalculé avec succès."})

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def validate_term(self, request):
        classroom_id = self._parse_positive_int(request.data.get("classroom"))
        academic_year_id = self._parse_positive_int(request.data.get("academic_year"))
        term = self._normalize_term_or_none(request.data.get("term"))
        notes = request.data.get("notes", "")

        if not classroom_id or not academic_year_id or not term:
            return Response({"detail": "classroom, academic_year et term (T1/T2/T3) sont requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)
        academic_year = get_object_or_404(AcademicYear, id=academic_year_id)
        validation, _ = GradeValidation.objects.update_or_create(
            classroom=classroom,
            academic_year=academic_year,
            term=term,
            defaults={
                "is_validated": True,
                "validated_by": request.user,
                "validated_at": timezone.now(),
                "notes": notes,
            },
        )
        serializer = GradeValidationSerializer(validation)
        return Response(serializer.data)

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def unvalidate_term(self, request):
        classroom_id = self._parse_positive_int(request.data.get("classroom"))
        academic_year_id = self._parse_positive_int(request.data.get("academic_year"))
        term = self._normalize_term_or_none(request.data.get("term"))

        if not classroom_id or not academic_year_id or not term:
            return Response({"detail": "classroom, academic_year et term (T1/T2/T3) sont requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)
        academic_year = get_object_or_404(AcademicYear, id=academic_year_id)
        validation, _ = GradeValidation.objects.update_or_create(
            classroom=classroom,
            academic_year=academic_year,
            term=term,
            defaults={
                "is_validated": False,
                "validated_by": request.user,
                "validated_at": timezone.now(),
            },
        )
        serializer = GradeValidationSerializer(validation)
        return Response(serializer.data)

    @action(detail=False, methods=["get"], permission_classes=[permissions.IsAuthenticated])
    def validation_status(self, request):
        classroom_id = self._parse_positive_int(request.query_params.get("classroom"))
        academic_year_id = self._parse_positive_int(request.query_params.get("academic_year"))
        term = self._normalize_term_or_none(request.query_params.get("term"))

        if not classroom_id or not academic_year_id or not term:
            return Response({"detail": "classroom, academic_year et term (T1/T2/T3) sont requis."}, status=400)

        classroom = self._get_scoped_classroom_or_404(classroom_id)

        validation = GradeValidation.objects.filter(
            classroom_id=classroom_id,
            academic_year_id=academic_year_id,
            term=term,
        ).first()

        if not validation:
            return Response(
                {
                    "classroom": classroom_id,
                    "academic_year": academic_year_id,
                    "term": term,
                    "is_validated": False,
                    "validated_by_name": "",
                    "validated_at": None,
                    "notes": "",
                }
            )

        serializer = GradeValidationSerializer(validation)
        return Response(serializer.data)


class AttendanceViewSet(BaseModelViewSet):
    queryset = Attendance.objects.select_related("student", "student__user").all().order_by("-date", "-id")
    serializer_class = AttendanceSerializer
    filterset_fields = ["date", "student", "is_absent", "is_late"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return queryset.filter(student__etablissement=requested_etablissement)

        if self._has_requested_scope():
            return queryset.none()

        if getattr(self.request.user, "role", None) == "super_admin":
            return queryset

        return queryset.filter(student__etablissement=getattr(self.request.user, "etablissement", None))

    def _validate_student_scope(self, serializer):
        student = serializer.validated_data.get("student")
        if not student:
            return

        role = getattr(self.request.user, "role", "")
        if role == UserRole.STUDENT and student.user_id != self.request.user.id:
            raise ValidationError({"student": "Vous ne pouvez saisir que vos propres absences."})
        if role == UserRole.PARENT and student.parent_id:
            if student.parent.user_id != self.request.user.id:
                raise ValidationError({"student": "Vous ne pouvez saisir que les absences de vos enfants."})

        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and student.etablissement_id != target_etablissement.id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_student_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_student_scope(serializer)
        serializer.save()

    @action(detail=False, methods=["get"])
    def monthly_stats(self, request):
        month_value = request.query_params.get("month")
        today = timezone.now().date()

        if month_value:
            try:
                year, month = month_value.split("-")
                year = int(year)
                month = int(month)
            except (ValueError, TypeError):
                return Response({"detail": "Format month invalide. Utilisez YYYY-MM."}, status=400)
        else:
            year = today.year
            month = today.month

        queryset = self.get_queryset().filter(date__year=year, date__month=month)
        totals = queryset.aggregate(
            total_records=Count("id"),
            absences=Count("id", filter=Q(is_absent=True)),
            lates=Count("id", filter=Q(is_late=True)),
            justifications=Count("id", filter=Q(proof__isnull=False)),
        )

        per_day = (
            queryset.values("date")
            .annotate(
                absences=Count("id", filter=Q(is_absent=True)),
                lates=Count("id", filter=Q(is_late=True)),
            )
            .order_by("date")
        )

        return Response(
            {
                "month": f"{year:04d}-{month:02d}",
                "total_records": totals["total_records"] or 0,
                "absences": totals["absences"] or 0,
                "lates": totals["lates"] or 0,
                "justifications": totals["justifications"] or 0,
                "daily": list(per_day),
            }
        )


class TeacherAttendanceViewSet(BaseModelViewSet):
    queryset = TeacherAttendance.objects.select_related("teacher", "teacher__user").all().order_by("-date", "-id")
    serializer_class = TeacherAttendanceSerializer
    filterset_fields = ["date", "teacher", "is_absent", "is_late"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.TEACHER:
            return queryset.filter(teacher__user_id=self.request.user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return queryset.filter(teacher__etablissement=requested_etablissement)

        if self._has_requested_scope():
            return queryset.none()

        if getattr(self.request.user, "role", None) == "super_admin":
            return queryset

        return queryset.filter(teacher__etablissement=getattr(self.request.user, "etablissement", None))

    def _validate_teacher_scope(self, serializer):
        teacher = serializer.validated_data.get("teacher")
        if not teacher:
            return

        role = getattr(self.request.user, "role", "")
        if role == UserRole.TEACHER and teacher.user_id != self.request.user.id:
            raise ValidationError({"teacher": "Vous ne pouvez saisir que vos propres absences."})

        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and teacher.etablissement_id != target_etablissement.id:
            raise ValidationError({"teacher": "L'enseignant n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_teacher_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_teacher_scope(serializer)
        serializer.save()

    @action(detail=False, methods=["get"])
    def monthly_stats(self, request):
        month_value = request.query_params.get("month")
        today = timezone.now().date()

        if month_value:
            try:
                year, month = month_value.split("-")
                year = int(year)
                month = int(month)
            except (ValueError, TypeError):
                return Response({"detail": "Format month invalide. Utilisez YYYY-MM."}, status=400)
        else:
            year = today.year
            month = today.month

        queryset = self.get_queryset().filter(date__year=year, date__month=month)
        totals = queryset.aggregate(
            total_records=Count("id"),
            absences=Count("id", filter=Q(is_absent=True)),
            lates=Count("id", filter=Q(is_late=True)),
            justifications=Count("id", filter=Q(proof__isnull=False)),
        )

        per_day = (
            queryset.values("date")
            .annotate(
                absences=Count("id", filter=Q(is_absent=True)),
                lates=Count("id", filter=Q(is_late=True)),
            )
            .order_by("date")
        )

        return Response(
            {
                "month": f"{year:04d}-{month:02d}",
                "total_records": totals["total_records"] or 0,
                "absences": totals["absences"] or 0,
                "lates": totals["lates"] or 0,
                "justifications": totals["justifications"] or 0,
                "daily": list(per_day),
            }
        )


class DisciplineIncidentViewSet(BaseModelViewSet):
    queryset = DisciplineIncident.objects.select_related("student", "student__user", "reported_by").all().order_by("-incident_date", "-id")
    serializer_class = DisciplineIncidentSerializer
    filterset_fields = ["student", "severity", "status", "incident_date", "parent_notified"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return queryset.filter(student__etablissement=requested_etablissement)

        if self._has_requested_scope():
            return queryset.none()

        if getattr(self.request.user, "role", None) == "super_admin":
            return queryset

        return queryset.filter(student__etablissement=getattr(self.request.user, "etablissement", None))

    def _validate_scope(self, serializer):
        student = serializer.validated_data.get("student")
        if not student:
            return
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and student.etablissement_id != target_etablissement.id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_scope(serializer)
        serializer.save()


class StudentFeeViewSet(BaseModelViewSet):
    queryset = StudentFee.objects.select_related("student", "student__user", "academic_year").all().order_by("-due_date", "-id")
    serializer_class = StudentFeeSerializer
    pagination_class = StandardResultsSetPagination
    filterset_fields = ["student", "academic_year", "fee_type"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def _validate_fee_scope(self, serializer, instance=None):
        student = serializer.validated_data.get("student") or (instance.student if instance else None)
        if not student:
            return

        role = getattr(self.request.user, "role", "")
        if role == UserRole.STUDENT and student.user_id != self.request.user.id:
            raise ValidationError({"student": "Vous ne pouvez creer/modifier que vos propres frais."})
        if role == UserRole.PARENT and student.parent_id:
            if student.parent.user_id != self.request.user.id:
                raise ValidationError({"student": "Vous ne pouvez creer/modifier que les frais de vos enfants."})

        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and student.etablissement_id != target_etablissement.id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})

    @staticmethod
    def _with_financial_annotations(queryset):
        paid_amount = Coalesce(
            Sum("payments__amount"),
            Value(0),
            output_field=DecimalField(max_digits=12, decimal_places=2),
        )
        return queryset.annotate(
            amount_paid_annotated=paid_amount,
            balance_annotated=ExpressionWrapper(
                F("amount_due") - paid_amount,
                output_field=DecimalField(max_digits=12, decimal_places=2),
            ),
        )

    def get_queryset(self):
        queryset = self._with_financial_annotations(super().get_queryset())
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return queryset.filter(student__etablissement=requested_etablissement)

        if self._has_requested_scope():
            return queryset.none()

        if getattr(self.request.user, "role", None) == "super_admin":
            return queryset

        return queryset.filter(student__etablissement=getattr(self.request.user, "etablissement", None))

    def perform_create(self, serializer):
        self._validate_fee_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_fee_scope(serializer, instance=self.get_object())
        serializer.save()


class PaymentViewSet(BaseModelViewSet):
    queryset = Payment.objects.all()
    serializer_class = PaymentSerializer
    pagination_class = StandardResultsSetPagination
    filterset_fields = ["fee", "fee__student", "method", "received_by"]
    search_fields = [
        "reference",
        "method",
        "fee__fee_type",
        "fee__student__matricule",
        "fee__student__user__first_name",
        "fee__student__user__last_name",
    ]
    ordering_fields = ["created_at", "amount", "method"]
    ordering = ["-created_at"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def _validate_payment_scope(self, serializer, instance=None):
        fee = serializer.validated_data.get("fee") or (instance.fee if instance else None)
        if not fee:
            return

        student = fee.student
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and student.etablissement_id != target_etablissement.id:
            raise ValidationError({"fee": "Le frais selectionne n'appartient pas a l'etablissement actif."})

    def get_queryset(self):
        user = self.request.user
        qs = Payment.objects.select_related("fee", "fee__student", "fee__student__user", "received_by").order_by("-created_at")
        role = getattr(user, "role", "")
        if role == UserRole.STUDENT:
            return qs.filter(fee__student__user_id=user.id)
        if role == UserRole.PARENT:
            return qs.filter(fee__student__parent__user_id=user.id)
        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if hasattr(user, "role") and user.role == "super_admin":
            return qs.all()
        return qs.filter(etablissement=user.etablissement)

    def perform_create(self, serializer):
        self._validate_payment_scope(serializer)
        serializer.save(
            etablissement=self._resolve_target_etablissement(),
            received_by=self.request.user,
        )

    def perform_update(self, serializer):
        self._validate_payment_scope(serializer, instance=self.get_object())
        serializer.save(etablissement=self._resolve_target_etablissement())


class ExpenseViewSet(BaseModelViewSet):
    queryset = Expense.objects.all().order_by("-date")
    serializer_class = ExpenseSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            return qs.filter(etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(etablissement=getattr(user, "etablissement", None))

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement is None:
            raise ValidationError({"detail": "Etablissement actif requis pour creer une depense."})
        serializer.save(etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement is None:
            raise ValidationError({"detail": "Etablissement actif requis pour modifier une depense."})
        serializer.save(etablissement=target_etablissement)


class TeacherPayrollViewSet(BaseModelViewSet):
    queryset = TeacherPayroll.objects.select_related("teacher", "paid_by").all().order_by("-paid_on")
    serializer_class = TeacherPayrollSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def _validate_payroll_scope(self, serializer, instance=None):
        teacher = serializer.validated_data.get("teacher") or (instance.teacher if instance else None)
        if not teacher:
            return
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and teacher.etablissement_id != target_etablissement.id:
            raise ValidationError({"teacher": "L'enseignant n'appartient pas a l'etablissement actif."})

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            return qs.filter(teacher__etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(teacher__etablissement=getattr(user, "etablissement", None))

    def perform_create(self, serializer):
        self._validate_payroll_scope(serializer)
        serializer.save(paid_by=self.request.user)

    def perform_update(self, serializer):
        self._validate_payroll_scope(serializer, instance=self.get_object())
        serializer.save(paid_by=self.request.user)


class AnnouncementViewSet(EtablissementScopedModelViewSet):
    queryset = Announcement.objects.select_related("author", "etablissement").all().order_by("-created_at")
    serializer_class = AnnouncementSerializer

    def get_queryset(self):
        return self._filter_by_scope(super().get_queryset(), field_name="etablissement")

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(author=self.request.user, etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(etablissement=target_etablissement)


class NotificationViewSet(EtablissementScopedModelViewSet):
    queryset = Notification.objects.select_related("recipient", "etablissement").all().order_by("-created_at")
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return self._filter_by_scope(super().get_queryset(), field_name="etablissement")

    def _validate_scope(self, serializer):
        recipient = serializer.validated_data.get("recipient")
        target_etablissement = self._resolve_target_etablissement()
        if not recipient or not target_etablissement:
            return
        if recipient.etablissement_id not in (None, target_etablissement.id):
            raise ValidationError({"recipient": "Le destinataire n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        self._validate_scope(serializer)
        serializer.save(etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        self._validate_scope(serializer)
        serializer.save(etablissement=target_etablissement)


class SmsProviderConfigViewSet(EtablissementScopedModelViewSet):
    queryset = SmsProviderConfig.objects.select_related("etablissement").all().order_by("-id")
    serializer_class = SmsProviderConfigSerializer

    def get_queryset(self):
        return self._filter_by_scope(super().get_queryset(), field_name="etablissement")

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(etablissement=target_etablissement)


class BookViewSet(BaseModelViewSet):
    queryset = Book.objects.all()
    serializer_class = BookSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested = self._requested_etablissement()
        if getattr(user, "role", None) == UserRole.SUPER_ADMIN and requested:
            return requested
        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = Book.objects.all()

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(etablissement=requested_etablissement)

        if self._has_requested_scope():
            return qs.none()

        if hasattr(user, "role") and user.role == "super_admin":
            return qs.all()

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is None:
            return qs.none()
        return qs.filter(etablissement=user_etablissement)

    def perform_create(self, serializer):
        serializer.save(etablissement=self._resolve_target_etablissement())

    def perform_update(self, serializer):
        serializer.save(etablissement=self._resolve_target_etablissement())


class BorrowViewSet(BaseModelViewSet):
    queryset = Borrow.objects.select_related("student", "book").all()
    serializer_class = BorrowSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        role = getattr(user, "role", "")

        if role == UserRole.STUDENT:
            return qs.filter(student__user_id=user.id)
        if role == UserRole.PARENT:
            return qs.filter(student__parent__user_id=user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(student__etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(student__etablissement=getattr(user, "etablissement", None))

    def _validate_scope(self, serializer):
        student = serializer.validated_data.get("student")
        book = serializer.validated_data.get("book")
        if not student or not book:
            return
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and student.etablissement_id != target_etablissement.id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})
        if target_etablissement and book.etablissement_id != target_etablissement.id:
            raise ValidationError({"book": "Le livre n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_scope(serializer)
        serializer.save()


class CanteenMenuViewSet(BaseModelViewSet):
    queryset = CanteenMenu.objects.all()
    serializer_class = CanteenMenuSerializer
    filterset_fields = ["menu_date", "is_active"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested = self._requested_etablissement()
        if getattr(user, "role", None) == UserRole.SUPER_ADMIN and requested:
            return requested
        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = CanteenMenu.objects.all().order_by("-menu_date", "-id")

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(etablissement=requested_etablissement)

        if self._has_requested_scope():
            return qs.none()

        if hasattr(user, "role") and user.role == "super_admin":
            return qs.all()

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is None:
            return qs.none()
        return qs.filter(etablissement=user_etablissement)

    def perform_create(self, serializer):
        serializer.save(etablissement=self._resolve_target_etablissement())

    def perform_update(self, serializer):
        serializer.save(etablissement=self._resolve_target_etablissement())


class CanteenSubscriptionViewSet(BaseModelViewSet):
    queryset = CanteenSubscription.objects.select_related("student", "student__user", "academic_year").all().order_by("-created_at")
    serializer_class = CanteenSubscriptionSerializer
    filterset_fields = ["student", "academic_year", "status"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        role = getattr(user, "role", "")

        if role == UserRole.STUDENT:
            return qs.filter(student__user_id=user.id)
        if role == UserRole.PARENT:
            return qs.filter(student__parent__user_id=user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(student__etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(student__etablissement=getattr(user, "etablissement", None))

    def _validate_scope(self, serializer):
        student = serializer.validated_data.get("student")
        if not student:
            return
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and student.etablissement_id != target_etablissement.id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_scope(serializer)
        serializer.save()


class CanteenServiceViewSet(BaseModelViewSet):
    queryset = CanteenService.objects.select_related("student", "student__user", "menu").all().order_by("-served_on", "-id")
    serializer_class = CanteenServiceSerializer
    filterset_fields = ["student", "menu", "served_on", "is_paid"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        role = getattr(user, "role", "")

        if role == UserRole.STUDENT:
            return qs.filter(student__user_id=user.id)
        if role == UserRole.PARENT:
            return qs.filter(student__parent__user_id=user.id)

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            return qs.filter(student__etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(student__etablissement=getattr(user, "etablissement", None))

    def _validate_scope(self, serializer):
        student = serializer.validated_data.get("student")
        menu = serializer.validated_data.get("menu")
        if not student or not menu:
            return
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and student.etablissement_id != target_etablissement.id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})
        if target_etablissement and menu.etablissement_id != target_etablissement.id:
            raise ValidationError({"menu": "Le menu n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_scope(serializer)
        serializer.save()


class ExamSessionViewSet(BaseModelViewSet):
    queryset = ExamSession.objects.select_related("academic_year").all()
    serializer_class = ExamSessionSerializer


class ExamPlanningViewSet(BaseModelViewSet):
    queryset = ExamPlanning.objects.select_related("session", "classroom", "subject").all()
    serializer_class = ExamPlanningSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin" and requested_etablissement:
            return requested_etablissement

        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            return qs.filter(classroom__etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(classroom__etablissement=getattr(user, "etablissement", None))

    def _validate_scope(self, serializer):
        classroom = serializer.validated_data.get("classroom")
        if not classroom:
            return
        target_etablissement = self._resolve_target_etablissement()
        if target_etablissement and classroom.etablissement_id != target_etablissement.id:
            raise ValidationError({"classroom": "La classe n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_scope(serializer)
        serializer.save()


class ExamInvigilationViewSet(BaseModelViewSet):
    queryset = ExamInvigilation.objects.select_related("planning", "planning__session", "planning__classroom", "planning__subject", "supervisor").all().order_by("-created_at")
    serializer_class = ExamInvigilationSerializer
    filterset_fields = ["planning", "supervisor", "planning__session"]

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        requested_id = self.request.headers.get("X-Etablissement-Id") or self.request.query_params.get("etablissement")
        if requested_id not in (None, ""):
            try:
                return qs.filter(planning__classroom__etablissement_id=int(requested_id))
            except (TypeError, ValueError):
                return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(planning__classroom__etablissement=getattr(user, "etablissement", None))

    def _validate_scope(self, serializer):
        planning = serializer.validated_data.get("planning")
        if not planning:
            return
        user = self.request.user
        requested_id = self.request.headers.get("X-Etablissement-Id") or self.request.query_params.get("etablissement")
        target_id = None
        if requested_id not in (None, "") and getattr(user, "role", None) == "super_admin":
            try:
                target_id = int(requested_id)
            except (TypeError, ValueError):
                target_id = None
        if target_id is None:
            target_id = getattr(user, "etablissement_id", None)
        if target_id and planning.classroom.etablissement_id != target_id:
            raise ValidationError({"planning": "Le planning n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_scope(serializer)
        serializer.save()


class ExamResultViewSet(BaseModelViewSet):
    queryset = ExamResult.objects.select_related("session", "student", "subject").all()
    serializer_class = ExamResultSerializer

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        role = getattr(user, "role", "")
        if role == UserRole.STUDENT:
            return qs.filter(student__user_id=user.id)
        if role == UserRole.PARENT:
            return qs.filter(student__parent__user_id=user.id)

        requested_id = self.request.headers.get("X-Etablissement-Id") or self.request.query_params.get("etablissement")
        if requested_id not in (None, ""):
            try:
                return qs.filter(student__etablissement_id=int(requested_id))
            except (TypeError, ValueError):
                return qs.none()
        if getattr(user, "role", None) == "super_admin":
            return qs
        return qs.filter(student__etablissement=getattr(user, "etablissement", None))

    def _validate_scope(self, serializer):
        student = serializer.validated_data.get("student")
        if not student:
            return
        user = self.request.user
        requested_id = self.request.headers.get("X-Etablissement-Id") or self.request.query_params.get("etablissement")
        target_id = None
        if requested_id not in (None, "") and getattr(user, "role", None) == "super_admin":
            try:
                target_id = int(requested_id)
            except (TypeError, ValueError):
                target_id = None
        if target_id is None:
            target_id = getattr(user, "etablissement_id", None)
        student_etablissement_id = getattr(student, "etablissement_id", None)
        classroom_etablissement_id = getattr(getattr(student, "classroom", None), "etablissement_id", None)
        if target_id and student_etablissement_id != target_id and classroom_etablissement_id != target_id:
            raise ValidationError({"student": "L'eleve n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        self._validate_scope(serializer)
        serializer.save()


class SupplierViewSet(EtablissementScopedModelViewSet):
    queryset = Supplier.objects.select_related("etablissement").all()
    serializer_class = SupplierSerializer

    def get_queryset(self):
        return self._filter_by_scope(super().get_queryset(), field_name="etablissement")

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        serializer.save(etablissement=target_etablissement)


class StockItemViewSet(EtablissementScopedModelViewSet):
    queryset = StockItem.objects.select_related("supplier", "etablissement").all()
    serializer_class = StockItemSerializer

    def get_queryset(self):
        return self._filter_by_scope(super().get_queryset(), field_name="etablissement")

    def _validate_scope(self, serializer):
        supplier = serializer.validated_data.get("supplier") or getattr(serializer.instance, "supplier", None)
        target_etablissement = self._resolve_target_etablissement()
        if not supplier or not target_etablissement:
            return
        if supplier.etablissement_id != target_etablissement.id:
            raise ValidationError({"supplier": "Le fournisseur n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        self._validate_scope(serializer)
        serializer.save(etablissement=target_etablissement)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        self._validate_scope(serializer)
        serializer.save(etablissement=target_etablissement)

    @action(detail=False, methods=["get"])
    def low_stock(self, request):
        queryset = self.get_queryset().filter(quantity__lte=F("minimum_threshold"))
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)


class StockMovementViewSet(BaseModelViewSet):
    queryset = StockMovement.objects.select_related("item", "item__etablissement").all().order_by("-created_at")
    serializer_class = StockMovementSerializer

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested_etablissement = self._requested_etablissement()
        if getattr(user, "role", None) == UserRole.SUPER_ADMIN and requested_etablissement:
            return requested_etablissement
        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = super().get_queryset()
        requested_etablissement = self._requested_etablissement()

        if requested_etablissement is not None:
            return qs.filter(item__etablissement=requested_etablissement)
        if self._has_requested_scope():
            return qs.none()
        if getattr(user, "role", None) == UserRole.SUPER_ADMIN:
            return qs

        user_etablissement = getattr(user, "etablissement", None)
        if user_etablissement is None:
            return qs.none()
        return qs.filter(item__etablissement=user_etablissement)

    def _validate_scope(self, serializer):
        item = serializer.validated_data.get("item") or getattr(serializer.instance, "item", None)
        target_etablissement = self._resolve_target_etablissement()
        if not item or not target_etablissement:
            return
        if item.etablissement_id != target_etablissement.id:
            raise ValidationError({"item": "L'article n'appartient pas a l'etablissement actif."})

    def perform_create(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        self._validate_scope(serializer)
        serializer.save()

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == UserRole.SUPER_ADMIN and target_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})
        self._validate_scope(serializer)
        serializer.save()


class DashboardViewSet(viewsets.ViewSet):
    permission_classes = [permissions.IsAuthenticated]

    @staticmethod
    def _requested_etablissement_id(request):
        raw_value = (
            request.headers.get("X-Etablissement-Id")
            or request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    @staticmethod
    def _requested_etablissement_name(request):
        raw_name = (
            request.headers.get("X-Etablissement-Name")
            or request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self, request):
        requested_id = self._requested_etablissement_id(request)
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name(request)
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _resolve_dashboard_scope(self, request):
        user = request.user
        requested = self._requested_etablissement(request)
        if getattr(user, "role", None) == "super_admin":
            return requested
        return getattr(user, "etablissement", None)

    def list(self, request):
        month_start = timezone.now().date().replace(day=1)
        active_etablissement = self._resolve_dashboard_scope(request)
        if getattr(request.user, "role", None) == UserRole.SUPER_ADMIN and active_etablissement is None:
            raise ValidationError({"etablissement": "Selectionnez un etablissement actif."})

        payment_qs = Payment.objects.filter(created_at__date__gte=month_start)
        students_qs = Student.objects.filter(is_archived=False)
        attendance_qs = Attendance.objects.filter(is_absent=True, date__gte=month_start)
        classrooms_qs = ClassRoom.objects.all()
        teachers_qs = Teacher.objects.all()

        if active_etablissement is not None:
            payment_qs = payment_qs.filter(etablissement=active_etablissement)
            students_qs = students_qs.filter(etablissement=active_etablissement)
            attendance_qs = attendance_qs.filter(student__etablissement=active_etablissement)
            classrooms_qs = classrooms_qs.filter(etablissement=active_etablissement)
            teachers_qs = teachers_qs.filter(etablissement=active_etablissement)

        revenue = payment_qs.aggregate(value=Sum("amount"))["value"] or 0
        expenses_qs = Expense.objects.filter(date__gte=month_start)
        if active_etablissement is not None:
            expenses_qs = expenses_qs.filter(etablissement=active_etablissement)
        expenses = expenses_qs.aggregate(value=Sum("amount"))["value"] or 0
        students = students_qs.count()
        absences = attendance_qs.count()
        classroom_count = classrooms_qs.count()
        teacher_count = teachers_qs.count()

        etablissement_payload = None
        if active_etablissement is not None:
            etablissement_payload = {
                "id": active_etablissement.id,
                "name": active_etablissement.name,
                "address": active_etablissement.address,
                "phone": active_etablissement.phone,
                "email": active_etablissement.email,
            }

        return Response(
            {
                "students": students,
                "monthly_revenue": revenue,
                "monthly_expenses": expenses,
                "monthly_profit": revenue - expenses,
                "monthly_absences": absences,
                "classrooms": classroom_count,
                "teachers": teacher_count,
                "active_etablissement": etablissement_payload,
            }
        )
