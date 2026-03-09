from django.db.models import Count, F, Q, Sum
from django.utils import timezone
from django.shortcuts import get_object_or_404
from rest_framework import permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from apps.accounts.models import UserRole
from apps.accounts.permissions import IsAdminOrDirector, IsReadOnlyForParentStudent
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
    TeacherPayrollSerializer,
    TeacherSerializer,
)


class BaseModelViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated, IsReadOnlyForParentStudent]


class AcademicYearViewSet(BaseModelViewSet):
    queryset = AcademicYear.objects.all().order_by("-id")
    serializer_class = AcademicYearSerializer


class LevelViewSet(BaseModelViewSet):
    queryset = Level.objects.all().order_by("name")
    serializer_class = LevelSerializer


class SectionViewSet(BaseModelViewSet):
    queryset = Section.objects.all().order_by("name")
    serializer_class = SectionSerializer


class ClassRoomViewSet(BaseModelViewSet):
    queryset = ClassRoom.objects.select_related("level", "section", "academic_year").all()
    serializer_class = ClassRoomSerializer


class SubjectViewSet(BaseModelViewSet):
    queryset = Subject.objects.all().order_by("name")
    serializer_class = SubjectSerializer


class TeacherViewSet(BaseModelViewSet):
    queryset = Teacher.objects.select_related("user").all()
    serializer_class = TeacherSerializer


class TeacherAssignmentViewSet(BaseModelViewSet):
    queryset = TeacherAssignment.objects.select_related("teacher", "subject", "classroom").all()
    serializer_class = TeacherAssignmentSerializer


class ParentProfileViewSet(BaseModelViewSet):
    queryset = ParentProfile.objects.select_related("user").all()
    serializer_class = ParentProfileSerializer


class StudentViewSet(BaseModelViewSet):
    queryset = Student.objects.select_related("user", "classroom", "parent", "parent__user").all()
    serializer_class = StudentSerializer
    filterset_fields = ["classroom", "is_archived", "parent", "user"]
    search_fields = ["matricule", "user__first_name", "user__last_name", "user__username"]
    ordering_fields = ["created_at", "matricule"]
    ordering = ["-created_at"]

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(parent__user_id=self.request.user.id)
        return queryset


class StudentAcademicHistoryViewSet(BaseModelViewSet):
    queryset = StudentAcademicHistory.objects.select_related("student", "academic_year", "classroom").all().order_by("-academic_year_id", "rank")
    serializer_class = StudentAcademicHistorySerializer
    filterset_fields = ["student", "academic_year", "classroom"]

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)
        return queryset


class GradeViewSet(BaseModelViewSet):
    queryset = Grade.objects.select_related("student", "subject", "classroom", "academic_year").all()
    serializer_class = GradeSerializer
    filterset_fields = ["classroom", "academic_year", "term", "subject"]

    def _is_term_validated(self, classroom_id, academic_year_id, term):
        if not classroom_id or not academic_year_id or not term:
            return False
        return GradeValidation.objects.filter(
            classroom_id=classroom_id,
            academic_year_id=academic_year_id,
            term=term,
            is_validated=True,
        ).exists()

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        classroom_id = serializer.validated_data.get("classroom").id if serializer.validated_data.get("classroom") else None
        academic_year_id = serializer.validated_data.get("academic_year").id if serializer.validated_data.get("academic_year") else None
        term = serializer.validated_data.get("term")
        if self._is_term_validated(classroom_id, academic_year_id, term):
            return Response({"detail": "Cette période est validée par la direction. Modification interdite."}, status=400)
        self.perform_create(serializer)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=201, headers=headers)

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop("partial", False)
        instance = self.get_object()
        serializer = self.get_serializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)

        classroom = serializer.validated_data.get("classroom", instance.classroom)
        academic_year = serializer.validated_data.get("academic_year", instance.academic_year)
        term = serializer.validated_data.get("term", instance.term)

        if self._is_term_validated(classroom.id, academic_year.id, term):
            return Response({"detail": "Cette période est validée par la direction. Modification interdite."}, status=400)

        self.perform_update(serializer)
        return Response(serializer.data)

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        if self._is_term_validated(instance.classroom_id, instance.academic_year_id, instance.term):
            return Response({"detail": "Cette période est validée par la direction. Suppression interdite."}, status=400)
        return super().destroy(request, *args, **kwargs)

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def recalculate_ranking(self, request):
        classroom_id = request.data.get("classroom")
        academic_year_id = request.data.get("academic_year")
        term = request.data.get("term")
        classroom = ClassRoom.objects.get(id=classroom_id)
        academic_year = AcademicYear.objects.get(id=academic_year_id)
        recalculate_term_ranking(classroom, academic_year, term)
        return Response({"detail": "Classement recalculé avec succès."})

    @action(detail=False, methods=["post"], permission_classes=[permissions.IsAuthenticated, IsAdminOrDirector])
    def validate_term(self, request):
        classroom_id = request.data.get("classroom")
        academic_year_id = request.data.get("academic_year")
        term = request.data.get("term")
        notes = request.data.get("notes", "")

        if not classroom_id or not academic_year_id or not term:
            return Response({"detail": "classroom, academic_year et term sont requis."}, status=400)

        classroom = get_object_or_404(ClassRoom, id=classroom_id)
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
        classroom_id = request.data.get("classroom")
        academic_year_id = request.data.get("academic_year")
        term = request.data.get("term")

        if not classroom_id or not academic_year_id or not term:
            return Response({"detail": "classroom, academic_year et term sont requis."}, status=400)

        classroom = get_object_or_404(ClassRoom, id=classroom_id)
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
        classroom_id = request.query_params.get("classroom")
        academic_year_id = request.query_params.get("academic_year")
        term = request.query_params.get("term")

        if not classroom_id or not academic_year_id or not term:
            return Response({"detail": "classroom, academic_year et term sont requis."}, status=400)

        validation = GradeValidation.objects.filter(
            classroom_id=classroom_id,
            academic_year_id=academic_year_id,
            term=term,
        ).first()

        if not validation:
            return Response(
                {
                    "classroom": int(classroom_id),
                    "academic_year": int(academic_year_id),
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

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)
        return queryset

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

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)
        return queryset


class StudentFeeViewSet(BaseModelViewSet):
    queryset = StudentFee.objects.select_related("student", "student__user", "academic_year").all().order_by("-due_date", "-id")
    serializer_class = StudentFeeSerializer
    filterset_fields = ["student", "academic_year", "fee_type"]

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(student__parent__user_id=self.request.user.id)
        return queryset


class PaymentViewSet(BaseModelViewSet):
    queryset = Payment.objects.select_related("fee", "fee__student", "fee__student__user", "received_by").all().order_by("-created_at")
    serializer_class = PaymentSerializer
    filterset_fields = ["fee", "fee__student", "method", "received_by"]

    def get_queryset(self):
        queryset = super().get_queryset()
        role = getattr(self.request.user, "role", "")

        if role == UserRole.STUDENT:
            return queryset.filter(fee__student__user_id=self.request.user.id)
        if role == UserRole.PARENT:
            return queryset.filter(fee__student__parent__user_id=self.request.user.id)
        return queryset


class ExpenseViewSet(BaseModelViewSet):
    queryset = Expense.objects.all().order_by("-date")
    serializer_class = ExpenseSerializer


class TeacherPayrollViewSet(BaseModelViewSet):
    queryset = TeacherPayroll.objects.select_related("teacher", "paid_by").all().order_by("-paid_on")
    serializer_class = TeacherPayrollSerializer


class AnnouncementViewSet(BaseModelViewSet):
    queryset = Announcement.objects.select_related("author").all().order_by("-created_at")
    serializer_class = AnnouncementSerializer


class NotificationViewSet(BaseModelViewSet):
    queryset = Notification.objects.select_related("recipient").all().order_by("-created_at")
    serializer_class = NotificationSerializer


class SmsProviderConfigViewSet(BaseModelViewSet):
    queryset = SmsProviderConfig.objects.all().order_by("-id")
    serializer_class = SmsProviderConfigSerializer


class BookViewSet(BaseModelViewSet):
    queryset = Book.objects.all()
    serializer_class = BookSerializer


class BorrowViewSet(BaseModelViewSet):
    queryset = Borrow.objects.select_related("student", "book").all()
    serializer_class = BorrowSerializer


class CanteenMenuViewSet(BaseModelViewSet):
    queryset = CanteenMenu.objects.all().order_by("-menu_date", "-id")
    serializer_class = CanteenMenuSerializer
    filterset_fields = ["menu_date", "is_active"]


class CanteenSubscriptionViewSet(BaseModelViewSet):
    queryset = CanteenSubscription.objects.select_related("student", "student__user", "academic_year").all().order_by("-created_at")
    serializer_class = CanteenSubscriptionSerializer
    filterset_fields = ["student", "academic_year", "status"]


class CanteenServiceViewSet(BaseModelViewSet):
    queryset = CanteenService.objects.select_related("student", "student__user", "menu").all().order_by("-served_on", "-id")
    serializer_class = CanteenServiceSerializer
    filterset_fields = ["student", "menu", "served_on", "is_paid"]


class ExamSessionViewSet(BaseModelViewSet):
    queryset = ExamSession.objects.select_related("academic_year").all()
    serializer_class = ExamSessionSerializer


class ExamPlanningViewSet(BaseModelViewSet):
    queryset = ExamPlanning.objects.select_related("session", "classroom", "subject").all()
    serializer_class = ExamPlanningSerializer


class ExamInvigilationViewSet(BaseModelViewSet):
    queryset = ExamInvigilation.objects.select_related("planning", "planning__session", "planning__classroom", "planning__subject", "supervisor").all().order_by("-created_at")
    serializer_class = ExamInvigilationSerializer
    filterset_fields = ["planning", "supervisor", "planning__session"]


class ExamResultViewSet(BaseModelViewSet):
    queryset = ExamResult.objects.select_related("session", "student", "subject").all()
    serializer_class = ExamResultSerializer


class SupplierViewSet(BaseModelViewSet):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer


class StockItemViewSet(BaseModelViewSet):
    queryset = StockItem.objects.select_related("supplier").all()
    serializer_class = StockItemSerializer

    @action(detail=False, methods=["get"])
    def low_stock(self, request):
        queryset = self.get_queryset().filter(quantity__lte=F("minimum_threshold"))
        serializer = self.get_serializer(queryset, many=True)
        return Response(serializer.data)


class StockMovementViewSet(BaseModelViewSet):
    queryset = StockMovement.objects.select_related("item").all().order_by("-created_at")
    serializer_class = StockMovementSerializer


class DashboardViewSet(viewsets.ViewSet):
    permission_classes = [permissions.IsAuthenticated]

    def list(self, request):
        month_start = timezone.now().date().replace(day=1)
        revenue = Payment.objects.filter(created_at__date__gte=month_start).aggregate(value=Sum("amount"))["value"] or 0
        expenses = Expense.objects.filter(date__gte=month_start).aggregate(value=Sum("amount"))["value"] or 0
        students = Student.objects.filter(is_archived=False).count()
        absences = Attendance.objects.filter(is_absent=True, date__gte=month_start).count()
        return Response(
            {
                "students": students,
                "monthly_revenue": revenue,
                "monthly_expenses": expenses,
                "monthly_profit": revenue - expenses,
                "monthly_absences": absences,
            }
        )
