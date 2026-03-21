from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .views import (
    AcademicYearViewSet,
    AnnouncementViewSet,
    AttendanceViewSet,
    BookViewSet,
    BorrowViewSet,
    CanteenMenuViewSet,
    CanteenServiceViewSet,
    CanteenSubscriptionViewSet,
    ClassRoomViewSet,
    DashboardViewSet,
    DisciplineIncidentViewSet,
    EtablissementViewSet,
    ExamPlanningViewSet,
    ExamInvigilationViewSet,
    ExamResultViewSet,
    ExamSessionViewSet,
    ExpenseViewSet,
    GradeViewSet,
    LevelViewSet,
    NotificationViewSet,
    ParentProfileViewSet,
    PaymentViewSet,
    SectionViewSet,
    StockItemViewSet,
    StockMovementViewSet,
    StudentAcademicHistoryViewSet,
    StudentFeeViewSet,
    StudentViewSet,
    SubjectViewSet,
    SupplierViewSet,
    SmsProviderConfigViewSet,
    TeacherAttendanceViewSet,
    TeacherAssignmentViewSet,
    TimetablePublicationViewSet,
    TeacherScheduleSlotViewSet,
    TeacherPayrollViewSet,
    TeacherViewSet,
)

router = DefaultRouter()
router.register(r"etablissements", EtablissementViewSet, basename="etablissements")
router.register(r"dashboard", DashboardViewSet, basename="dashboard")
router.register(r"academic-years", AcademicYearViewSet)
router.register(r"levels", LevelViewSet)
router.register(r"sections", SectionViewSet)
router.register(r"classrooms", ClassRoomViewSet)
router.register(r"subjects", SubjectViewSet)
router.register(r"teachers", TeacherViewSet)
router.register(r"teacher-assignments", TeacherAssignmentViewSet)
router.register(r"teacher-schedule-slots", TeacherScheduleSlotViewSet)
router.register(r"timetable-publications", TimetablePublicationViewSet, basename="timetable-publications")
router.register(r"parents", ParentProfileViewSet)
router.register(r"students", StudentViewSet)
router.register(r"student-history", StudentAcademicHistoryViewSet)
router.register(r"grades", GradeViewSet)
router.register(r"attendances", AttendanceViewSet)
router.register(r"teacher-attendances", TeacherAttendanceViewSet)
router.register(r"discipline-incidents", DisciplineIncidentViewSet)
router.register(r"fees", StudentFeeViewSet)
router.register(r"payments", PaymentViewSet)
router.register(r"expenses", ExpenseViewSet)
router.register(r"teacher-payrolls", TeacherPayrollViewSet)
router.register(r"announcements", AnnouncementViewSet)
router.register(r"notifications", NotificationViewSet)
router.register(r"sms-providers", SmsProviderConfigViewSet)
router.register(r"books", BookViewSet)
router.register(r"borrows", BorrowViewSet)
router.register(r"canteen-menus", CanteenMenuViewSet)
router.register(r"canteen-subscriptions", CanteenSubscriptionViewSet)
router.register(r"canteen-services", CanteenServiceViewSet)
router.register(r"exam-sessions", ExamSessionViewSet)
router.register(r"exam-plannings", ExamPlanningViewSet)
router.register(r"exam-invigilations", ExamInvigilationViewSet)
router.register(r"exam-results", ExamResultViewSet)
router.register(r"suppliers", SupplierViewSet)
router.register(r"stock-items", StockItemViewSet)
router.register(r"stock-movements", StockMovementViewSet)

urlpatterns = [
    path("", include(router.urls)),
]
