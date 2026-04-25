from django.urls import path
from .views import (
    BulletinPdfView,
    ClassBulletinsPdfView,
    ClassStudentCardsPdfView,
    ExpenseJournalExportView,
    ExpenseJournalPageView,
    PaymentExcelExportView,
    PaymentJournalExportView,
    PaymentJournalPageView,
    PaymentReceiptPdfView,
    ReportsContextView,
    StudentCardPdfView,
)

urlpatterns = [
    path("context/", ReportsContextView.as_view(), name="reports-context"),
    path("bulletin/<int:student_id>/<int:academic_year_id>/<str:term>/", BulletinPdfView.as_view(), name="bulletin-pdf"),
    path(
        "bulletins/class/<int:classroom_id>/<int:academic_year_id>/<str:term>/",
        ClassBulletinsPdfView.as_view(),
        name="class-bulletins-pdf",
    ),
    path("receipt/<int:payment_id>/", PaymentReceiptPdfView.as_view(), name="payment-receipt-pdf"),
    path("payments/export-excel/", PaymentExcelExportView.as_view(), name="payments-export-excel"),
    path("journal-payments/export/", PaymentJournalExportView.as_view(), name="journal-payments-export-flat"),
    path("journal-expenses/export/", ExpenseJournalExportView.as_view(), name="journal-expenses-export-flat"),
    path("journal/payments/export/", PaymentJournalExportView.as_view(), name="journal-payments-export"),
    path("journal/expenses/export/", ExpenseJournalExportView.as_view(), name="journal-expenses-export"),
    path("journal/payments/", PaymentJournalPageView.as_view(), name="journal-payments-page"),
    path("journal/expenses/", ExpenseJournalPageView.as_view(), name="journal-expenses-page"),
    path("student-card/<int:student_id>/", StudentCardPdfView.as_view(), name="student-card-pdf"),
    path("student-cards/class/<int:classroom_id>/", ClassStudentCardsPdfView.as_view(), name="class-student-cards-pdf"),
]
