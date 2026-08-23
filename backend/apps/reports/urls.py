from django.urls import path
from .views import (
    BatchPaymentReceiptsPdfView,
    BulletinPdfView,
    ClassBulletinsPdfView,
    ClassRosterPdfView,
    ClassStudentCardsPdfView,
    ExpenseJournalExportView,
    ExpenseJournalPageView,
    PaymentExcelExportView,
    PaymentJournalExportView,
    PaymentJournalPageView,
    PaymentReceiptPdfView,
    ReportsContextView,
    StaffRosterPdfView,
    StudentCardPdfView,
    StudentCardVerifyView,
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
    path("receipts/batch/", BatchPaymentReceiptsPdfView.as_view(), name="payment-receipts-batch-pdf"),
    path("payments/export-excel/", PaymentExcelExportView.as_view(), name="payments-export-excel"),
    path("journal-payments/export/", PaymentJournalExportView.as_view(), name="journal-payments-export-flat"),
    path("journal-expenses/export/", ExpenseJournalExportView.as_view(), name="journal-expenses-export-flat"),
    path("journal/payments/export/", PaymentJournalExportView.as_view(), name="journal-payments-export"),
    path("journal/expenses/export/", ExpenseJournalExportView.as_view(), name="journal-expenses-export"),
    path("journal/payments/", PaymentJournalPageView.as_view(), name="journal-payments-page"),
    path("journal/expenses/", ExpenseJournalPageView.as_view(), name="journal-expenses-page"),
    path("student-card/<int:student_id>/", StudentCardPdfView.as_view(), name="student-card-pdf"),
    path("student-cards/class/<int:classroom_id>/", ClassStudentCardsPdfView.as_view(), name="class-student-cards-pdf"),
    # Cible du QR imprime sur la carte. Publique: celui qui controle au
    # portail n'a pas de compte. La signature tient lieu de cle d'acces.
    path(
        "carte/<int:student_id>/<str:annee>/<str:signature>/",
        StudentCardVerifyView.as_view(),
        name="student-card-verify",
    ),
    # Sans classe: toutes les classes de l'etablissement, une par page,
    # suivies du recapitulatif des effectifs.
    path("class-roster/", ClassRosterPdfView.as_view(), name="class-roster-all-pdf"),
    path("class-roster/<int:classroom_id>/", ClassRosterPdfView.as_view(), name="class-roster-pdf"),
    path("staff-roster/", StaffRosterPdfView.as_view(), name="staff-roster-pdf"),
]
