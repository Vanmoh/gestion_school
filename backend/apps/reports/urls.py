from django.urls import path
from .views import (
    BulletinPdfView,
    ClassStudentCardsPdfView,
    PaymentExcelExportView,
    PaymentReceiptPdfView,
    ReportsContextView,
    StudentCardPdfView,
)

urlpatterns = [
    path("context/", ReportsContextView.as_view(), name="reports-context"),
    path("bulletin/<int:student_id>/<int:academic_year_id>/<str:term>/", BulletinPdfView.as_view(), name="bulletin-pdf"),
    path("receipt/<int:payment_id>/", PaymentReceiptPdfView.as_view(), name="payment-receipt-pdf"),
    path("payments/export-excel/", PaymentExcelExportView.as_view(), name="payments-export-excel"),
    path("student-card/<int:student_id>/", StudentCardPdfView.as_view(), name="student-card-pdf"),
    path("student-cards/class/<int:classroom_id>/", ClassStudentCardsPdfView.as_view(), name="class-student-cards-pdf"),
]
