from django.urls import path
from .views import (
    BatchPaymentReceiptsPdfView,
    BulletinDeliveryMarkSentView,
    BulletinPdfView,
    BulletinShareDownloadView,
    BulletinWhatsAppView,
    ClassBulletinsPdfView,
    ClassBulletinsWhatsAppView,
    ClassRosterPdfView,
    ClassStudentCardsPdfView,
    ClassStudentCardsPreflightView,
    ExpenseJournalExportView,
    ExpenseJournalPageView,
    PaymentExcelExportView,
    PaymentJournalExportView,
    PaymentJournalPageView,
    PaymentReceiptPdfView,
    ReceiptsPageView,
    ReportsContextView,
    StaffRosterPdfView,
    BulletinDePaiePdfView,
    CertificatFrequentationPdfView,
    CertificatTravailPdfView,
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
    # Envoi des bulletins aux familles par WhatsApp. GET dit ce qui est
    # possible, POST prepare les liens: un ecran qui s'affiche ne doit pas
    # ouvrir une ligne d'historique.
    path(
        "bulletin/<int:student_id>/<int:academic_year_id>/<str:term>/whatsapp/",
        BulletinWhatsAppView.as_view(),
        name="bulletin-whatsapp",
    ),
    path(
        "bulletins/class/<int:classroom_id>/<int:academic_year_id>/<str:term>/whatsapp/",
        ClassBulletinsWhatsAppView.as_view(),
        name="class-bulletins-whatsapp",
    ),
    path(
        "bulletin-deliveries/<int:delivery_id>/sent/",
        BulletinDeliveryMarkSentView.as_view(),
        name="bulletin-delivery-mark-sent",
    ),
    # Cible du lien recu par la famille. Publique: un parent n'a pas de
    # compte. La signature et l'expiration tiennent lieu de cle d'acces.
    path(
        "bulletin-partage/<int:student_id>/<int:academic_year_id>/<str:term>/<int:expire>/<str:signature>/",
        BulletinShareDownloadView.as_view(),
        name="bulletin-partage",
    ),
    # Les recus page par page: le contexte de l'ecran les servait tous.
    path("receipts/", ReceiptsPageView.as_view(), name="reports-receipts"),
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
    # Le certificat de frequentation, delivre a la demande d'une famille:
    # dossier de bourse, demande de visa, abonnement de transport, ouverture
    # de compte. Il etait redige a la main sur papier a en-tete.
    # Le bulletin de salaire d'un enseignant. La paie se calculait, se
    # validait et se payait sans qu'aucune piece n'en sorte.
    path(
        "bulletin-salaire/<int:payroll_id>/",
        BulletinDePaiePdfView.as_view(),
        name="bulletin-salaire-pdf",
    ),
    path(
        "certificat-frequentation/<int:student_id>/",
        CertificatFrequentationPdfView.as_view(),
        name="certificat-frequentation-pdf",
    ),
    # Le pendant pour le personnel: une banque ou un bailleur demande la
    # preuve qu'une personne travaille bien ici.
    path(
        "certificat-travail/<int:teacher_id>/",
        CertificatTravailPdfView.as_view(),
        name="certificat-travail-pdf",
    ),
    path("student-cards/class/<int:classroom_id>/", ClassStudentCardsPdfView.as_view(), name="class-student-cards-pdf"),
    # Interroge avant d'imprimer: combien d'eleves, combien sans photo,
    # et le QR sera-t-il vivant. Rien de tout cela ne se corrige apres
    # la decoupe.
    path(
        "student-cards/class/<int:classroom_id>/verification/",
        ClassStudentCardsPreflightView.as_view(),
        name="class-student-cards-preflight",
    ),
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
