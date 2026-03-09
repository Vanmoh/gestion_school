from pathlib import Path

from django.conf import settings
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from fpdf import FPDF
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from apps.accounts.models import UserRole
from apps.school.models import AcademicYear, ClassRoom, Grade, Payment, Student
from apps.school.serializers import AcademicYearSerializer, PaymentSerializer, StudentSerializer


def _pdf_text(value) -> str:
    return str(value or "").encode("latin-1", "replace").decode("latin-1")


def _school_logo_path() -> str | None:
    raw_path = str(getattr(settings, "SCHOOL_LOGO_PATH", "") or "").strip()
    if not raw_path:
        return None

    path = Path(raw_path)
    if not path.is_absolute():
        path = Path(settings.BASE_DIR) / path

    return str(path) if path.exists() else None


def pdf_output_response(pdf: FPDF, filename: str) -> HttpResponse:
    data = bytes(pdf.output())
    response = HttpResponse(data, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    return response


def _school_identity() -> dict[str, str]:
    return {
        "name": getattr(settings, "SCHOOL_NAME", "LYCEE TECHNIQUE OUMAR BAH"),
        "short": getattr(settings, "SCHOOL_SHORT", "LTOB"),
        "level": getattr(settings, "SCHOOL_LEVEL", "1er etage"),
        "phone": getattr(settings, "SCHOOL_PHONE", ""),
    }


def _student_photo_path(student: Student) -> str | None:
    if not getattr(student, "photo", None):
        return None

    try:
        raw_path = str(student.photo.path or "").strip()
    except Exception:
        raw_path = ""

    if not raw_path:
        return None

    path = Path(raw_path)
    return str(path) if path.exists() else None


def _add_student_card_page(
    pdf: FPDF,
    student: Student,
    *,
    school: dict[str, str],
    logo_path: str | None,
) -> None:
    pdf.add_page()
    pdf.set_auto_page_break(auto=False)

    page_w = pdf.w
    page_h = pdf.h
    margin = 6

    pdf.set_draw_color(35, 65, 110)
    pdf.set_fill_color(248, 250, 255)
    pdf.rect(margin, margin, page_w - (2 * margin), page_h - (2 * margin), style="DF")

    if logo_path:
        try:
            pdf.image(logo_path, x=10, y=10, w=14)
        except Exception:
            pass

    header_x = 27 if logo_path else 10
    pdf.set_xy(header_x, 10)
    pdf.set_font("Helvetica", "B", 9)
    pdf.multi_cell(page_w - header_x - 10, 4, _pdf_text(school["name"])[:80])

    pdf.set_x(header_x)
    pdf.set_font("Helvetica", size=7)
    subtitle = (
        f"{school['level']} | Tel: {school['phone']}"
        if school["phone"]
        else school["level"]
    )
    pdf.multi_cell(page_w - header_x - 10, 3.5, _pdf_text(subtitle)[:80])

    pdf.set_y(30)
    pdf.set_font("Helvetica", "B", 11)
    pdf.cell(0, 6, _pdf_text("CARTE D'ETUDIANT"), ln=True, align="C")

    photo_x = 10
    photo_y = 40
    photo_w = 28
    photo_h = 34
    pdf.set_draw_color(120, 130, 140)
    pdf.rect(photo_x, photo_y, photo_w, photo_h)

    student_photo_path = _student_photo_path(student)
    if student_photo_path:
        try:
            pdf.image(student_photo_path, x=photo_x, y=photo_y, w=photo_w, h=photo_h)
        except Exception:
            pass
    else:
        pdf.set_xy(photo_x, photo_y + (photo_h / 2) - 2)
        pdf.set_font("Helvetica", size=7)
        pdf.cell(photo_w, 4, _pdf_text("Photo"), align="C")

    student_user = student.user
    student_name = student_user.get_full_name().strip() if student_user else ""
    student_name = student_name or (student_user.username if student_user else "")
    class_name = student.classroom.name if student.classroom else "Non attribuee"
    parent_name = ""
    if student.parent and student.parent.user:
        parent_name = student.parent.user.get_full_name().strip() or student.parent.user.username

    birth_date = student.birth_date.strftime("%d/%m/%Y") if student.birth_date else "-"

    info_x = 42
    info_label_w = 18
    info_value_w = page_w - info_x - 8
    rows = [
        ("Nom", student_name),
        ("Matricule", student.matricule),
        ("Classe", class_name),
        ("Naiss.", birth_date),
        ("Parent", parent_name or "-"),
    ]

    y = 40
    for label, value in rows:
        pdf.set_xy(info_x, y)
        pdf.set_font("Helvetica", "B", 7)
        pdf.cell(info_label_w, 4.8, _pdf_text(label))
        pdf.set_font("Helvetica", size=7)
        pdf.multi_cell(info_value_w, 4.8, _pdf_text(value)[:46])
        y = pdf.get_y() + 0.5

    pdf.set_y(page_h - 16)
    pdf.set_font("Helvetica", size=6.5)
    generated_on = timezone.localdate().strftime("%d/%m/%Y")
    pdf.cell(0, 4, _pdf_text(f"Delivree le {generated_on} - {school['short']}"), ln=True, align="R")


def _draw_student_card_block(
    pdf: FPDF,
    student: Student,
    *,
    school: dict[str, str],
    logo_path: str | None,
    x: float,
    y: float,
    width: float,
    height: float,
) -> None:
    pdf.set_draw_color(35, 65, 110)
    pdf.set_fill_color(248, 250, 255)
    pdf.rect(x, y, width, height, style="DF")

    if logo_path:
        try:
            pdf.image(logo_path, x=x + 1.8, y=y + 1.8, w=6.2)
        except Exception:
            pass

    header_x = x + (8.8 if logo_path else 2)
    header_w = max(10, width - (header_x - x) - 1.8)
    pdf.set_xy(header_x, y + 1.6)
    pdf.set_font("Helvetica", "B", 6.3)
    pdf.multi_cell(header_w, 2.8, _pdf_text(school["short"])[:26])

    pdf.set_xy(x + 1.8, y + 6.8)
    pdf.set_font("Helvetica", "B", 6.8)
    pdf.cell(width - 3.6, 3.4, _pdf_text("CARTE D'ETUDIANT"), align="C")

    photo_w = min(16, max(11, width * 0.26))
    photo_h = min(20, max(14, height * 0.26))
    photo_x = x + 1.8
    photo_y = y + 11

    pdf.set_draw_color(125, 135, 145)
    pdf.rect(photo_x, photo_y, photo_w, photo_h)

    student_photo_path = _student_photo_path(student)
    if student_photo_path:
        try:
            pdf.image(student_photo_path, x=photo_x, y=photo_y, w=photo_w, h=photo_h)
        except Exception:
            pass
    else:
        pdf.set_xy(photo_x, photo_y + (photo_h / 2) - 1.3)
        pdf.set_font("Helvetica", size=5.5)
        pdf.cell(photo_w, 2.8, _pdf_text("Photo"), align="C")

    student_user = student.user
    student_name = student_user.get_full_name().strip() if student_user else ""
    student_name = student_name or (student_user.username if student_user else "")
    class_name = student.classroom.name if student.classroom else "Non attribuee"
    birth_date = student.birth_date.strftime("%d/%m/%Y") if student.birth_date else "-"

    info_x = photo_x + photo_w + 1.8
    info_w = max(8, (x + width) - info_x - 1.8)
    rows = [
        ("Nom", student_name),
        ("Mat", student.matricule),
        ("Cls", class_name),
        ("Nais", birth_date),
    ]

    row_y = photo_y
    for label, value in rows:
        pdf.set_xy(info_x, row_y)
        pdf.set_font("Helvetica", "B", 5.4)
        pdf.cell(6.5, 2.9, _pdf_text(label))
        pdf.set_font("Helvetica", size=5.4)
        pdf.cell(max(1, info_w - 6.5), 2.9, _pdf_text(value)[:24])
        row_y += 3.2

    pdf.set_xy(x + 1.8, y + height - 4.2)
    pdf.set_font("Helvetica", size=4.7)
    pdf.cell(width - 3.6, 2.8, _pdf_text(student.matricule), align="R")


def _build_student_cards_pdf(
    students: list[Student],
    *,
    school: dict[str, str],
    logo_path: str | None,
    layout_mode: str,
) -> FPDF:
    if layout_mode in {"a4_9up", "a4_6up"}:
        pdf = FPDF(format="A4")
        pdf.set_auto_page_break(auto=False)

        if layout_mode == "a4_6up":
            cols = 2
            rows = 3
        else:
            cols = 3
            rows = 3
        margin_x = 8.0
        margin_y = 10.0
        gap_x = 4.0
        gap_y = 4.0

        card_w = (pdf.w - (2 * margin_x) - ((cols - 1) * gap_x)) / cols
        card_h = (pdf.h - (2 * margin_y) - ((rows - 1) * gap_y)) / rows

        for index, student in enumerate(students):
            if index % (cols * rows) == 0:
                pdf.add_page()

            slot = index % (cols * rows)
            row = slot // cols
            col = slot % cols
            x = margin_x + col * (card_w + gap_x)
            y = margin_y + row * (card_h + gap_y)

            _draw_student_card_block(
                pdf,
                student,
                school=school,
                logo_path=logo_path,
                x=x,
                y=y,
                width=card_w,
                height=card_h,
            )

        return pdf

    pdf = FPDF(format=(105, 148))
    for student in students:
        _add_student_card_page(pdf, student, school=school, logo_path=logo_path)
    return pdf


def _allowed_students_queryset(user):
    queryset = Student.objects.select_related(
        "user",
        "classroom",
        "parent",
        "parent__user",
    ).all()
    role = getattr(user, "role", "")

    if role == UserRole.STUDENT:
        return queryset.filter(user_id=user.id)
    if role == UserRole.PARENT:
        return queryset.filter(parent__user_id=user.id)
    return queryset


def _allowed_payments_queryset(user):
    queryset = Payment.objects.select_related(
        "fee",
        "fee__student",
        "fee__student__user",
        "fee__student__parent",
        "fee__student__parent__user",
        "fee__academic_year",
        "received_by",
    ).all()
    role = getattr(user, "role", "")

    if role == UserRole.STUDENT:
        return queryset.filter(fee__student__user_id=user.id)
    if role == UserRole.PARENT:
        return queryset.filter(fee__student__parent__user_id=user.id)
    return queryset


def _ensure_student_access(user, student: Student) -> None:
    role = getattr(user, "role", "")
    if role == UserRole.STUDENT and student.user_id != user.id:
        raise PermissionDenied("Accès refusé à ce bulletin.")

    if role == UserRole.PARENT:
        parent_user_id = student.parent.user_id if student.parent else None
        if parent_user_id != user.id:
            raise PermissionDenied("Accès refusé à ce bulletin.")


def _ensure_payment_access(user, payment: Payment) -> None:
    role = getattr(user, "role", "")
    student = payment.fee.student if payment.fee else None

    if role == UserRole.STUDENT:
        if not student or student.user_id != user.id:
            raise PermissionDenied("Accès refusé à ce reçu de paiement.")

    if role == UserRole.PARENT:
        parent_user_id = student.parent.user_id if student and student.parent else None
        if parent_user_id != user.id:
            raise PermissionDenied("Accès refusé à ce reçu de paiement.")


class ReportsContextView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        students = _allowed_students_queryset(request.user).order_by(
            "user__last_name",
            "user__first_name",
            "matricule",
        )
        payments = _allowed_payments_queryset(request.user).order_by("-created_at")
        years = AcademicYear.objects.all().order_by("-start_date", "-id")

        return Response(
            {
                "students": StudentSerializer(students, many=True).data,
                "academic_years": AcademicYearSerializer(years, many=True).data,
                "payments": PaymentSerializer(payments, many=True).data,
            }
        )


class BulletinPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, student_id: int, academic_year_id: int, term: str):
        student = Student.objects.select_related(
            "user",
            "classroom",
            "parent",
            "parent__user",
        ).get(id=student_id)
        _ensure_student_access(request.user, student)
        grades = Grade.objects.filter(student_id=student_id, academic_year_id=academic_year_id, term=term).select_related("subject")
        school_name = getattr(settings, "SCHOOL_NAME", "LYCEE TECHNIQUE OUMAR BAH")
        school_short = getattr(settings, "SCHOOL_SHORT", "LTOB")
        school_level = getattr(settings, "SCHOOL_LEVEL", "1er etage")
        school_phone = getattr(settings, "SCHOOL_PHONE", "")
        logo_path = _school_logo_path()

        student_name = student.user.get_full_name().strip() or student.user.username
        class_name = student.classroom.name if student.classroom else "N/A"
        academic_year_name = (
            AcademicYear.objects.filter(id=academic_year_id)
            .values_list("name", flat=True)
            .first()
            or str(academic_year_id)
        )

        weighted_sum = 0
        coef_sum = 0
        rows = []
        for grade in grades:
            coef = float(grade.subject.coefficient)
            value = float(grade.value)
            weighted_sum += value * coef
            coef_sum += coef
            rows.append({"subject": grade.subject.name, "coef": coef, "grade": value})
        average = round(weighted_sum / coef_sum, 2) if coef_sum else 0

        if average >= 16:
            mention = "Tres bien"
        elif average >= 14:
            mention = "Bien"
        elif average >= 12:
            mention = "Assez bien"
        elif average >= 10:
            mention = "Passable"
        else:
            mention = "Insuffisant"

        pdf = FPDF()
        pdf.add_page()
        pdf.set_auto_page_break(auto=True, margin=12)

        if logo_path:
            try:
                pdf.image(logo_path, x=10, y=8, w=22)
            except Exception:
                pass

        pdf.set_xy(36 if logo_path else 10, 8)
        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 7, _pdf_text(school_name), ln=True)

        pdf.set_x(36 if logo_path else 10)
        pdf.set_font("Helvetica", size=10)
        header_line = f"{school_level} | Tel: {school_phone}" if school_phone else school_level
        pdf.cell(0, 5, _pdf_text(header_line), ln=True)

        pdf.set_x(36 if logo_path else 10)
        pdf.set_font("Helvetica", "B", 10)
        pdf.cell(0, 5, _pdf_text(f"Application: {school_short} - GESTION SCHOOL"), ln=True)

        top_line_y = max(pdf.get_y() + 2, 30)
        pdf.set_draw_color(60, 60, 60)
        pdf.line(10, top_line_y, 200, top_line_y)
        pdf.set_y(top_line_y + 4)

        pdf.set_font("Helvetica", "B", 16)
        pdf.cell(0, 9, _pdf_text("BULLETIN SCOLAIRE"), ln=True, align="C")
        pdf.ln(1)

        info_label_w = 32
        info_value_w = 58
        info_rows = [
            ("Eleve", student_name),
            ("Matricule", student.matricule),
            ("Classe", class_name),
            ("Annee", academic_year_name),
            ("Periode", term),
        ]

        for index, (label, value) in enumerate(info_rows):
            if index % 2 == 0:
                pdf.set_x(10)
            pdf.set_font("Helvetica", "B", 10)
            pdf.cell(info_label_w, 7, _pdf_text(label), border=1)
            pdf.set_font("Helvetica", size=10)
            pdf.cell(info_value_w, 7, _pdf_text(value)[:36], border=1)
            if index % 2 == 1:
                pdf.ln(7)
        if len(info_rows) % 2 == 1:
            pdf.ln(7)

        pdf.ln(3)
        pdf.set_font("Helvetica", "B", 10)
        pdf.set_fill_color(230, 235, 245)
        pdf.cell(110, 8, _pdf_text("Matiere"), border=1, fill=True)
        pdf.cell(30, 8, _pdf_text("Coef"), border=1, fill=True, align="C")
        pdf.cell(40, 8, _pdf_text("Note"), border=1, fill=True, align="C", ln=True)

        pdf.set_font("Helvetica", size=10)
        if not rows:
            pdf.cell(180, 8, _pdf_text("Aucune note disponible pour cette periode."), border=1, ln=True)
        else:
            for row in rows:
                pdf.cell(110, 8, _pdf_text(str(row["subject"])[:58]), border=1)
                pdf.cell(30, 8, _pdf_text(f"{row['coef']}"), border=1, align="C")
                pdf.cell(40, 8, _pdf_text(f"{row['grade']}"), border=1, align="C", ln=True)

        pdf.ln(4)
        pdf.set_font("Helvetica", "B", 12)
        pdf.cell(0, 7, _pdf_text(f"Moyenne generale: {average}/20"), ln=True)
        pdf.cell(0, 7, _pdf_text(f"Mention: {mention}"), ln=True)

        signature_y = pdf.get_y() + 10
        pdf.line(15, signature_y, 75, signature_y)
        pdf.line(125, signature_y, 185, signature_y)
        pdf.set_y(signature_y + 2)
        pdf.set_font("Helvetica", size=9)
        pdf.cell(60, 5, _pdf_text("Titulaire / Enseignant"), align="C")
        pdf.cell(0, 5, _pdf_text("Direction"), align="R")

        return pdf_output_response(pdf, f"bulletin_{student.matricule}_{term}.pdf")


class PaymentReceiptPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, payment_id: int):
        payment = Payment.objects.select_related(
            "fee__student__user",
            "fee__student__parent",
            "fee__student__parent__user",
            "fee__student__classroom",
            "fee__academic_year",
            "received_by",
        ).get(id=payment_id)
        _ensure_payment_access(request.user, payment)

        school_name = getattr(settings, "SCHOOL_NAME", "LYCEE TECHNIQUE OUMAR BAH")
        school_short = getattr(settings, "SCHOOL_SHORT", "LTOB")
        school_level = getattr(settings, "SCHOOL_LEVEL", "1er etage")
        school_phone = getattr(settings, "SCHOOL_PHONE", "")
        logo_path = _school_logo_path()

        student = payment.fee.student
        student_user = student.user if student else None
        student_name = student_user.get_full_name().strip() if student_user else ""
        student_name = student_name or (student_user.username if student_user else "")
        class_name = student.classroom.name if student and student.classroom else "N/A"
        academic_year = payment.fee.academic_year.name if payment.fee and payment.fee.academic_year else "N/A"

        receiver = payment.received_by
        receiver_name = ""
        if receiver:
            receiver_name = receiver.get_full_name().strip() or receiver.username

        pdf = FPDF(format="A5")
        pdf.add_page()
        pdf.set_auto_page_break(auto=True, margin=10)

        if logo_path:
            try:
                pdf.image(logo_path, x=10, y=9, w=18)
            except Exception:
                pass

        pdf.set_xy(32 if logo_path else 10, 9)
        pdf.set_font("Helvetica", "B", 12)
        pdf.cell(0, 6, _pdf_text(school_name), ln=True)

        pdf.set_x(32 if logo_path else 10)
        pdf.set_font("Helvetica", size=9)
        header_line = f"{school_level} | Tel: {school_phone}" if school_phone else school_level
        pdf.cell(0, 5, _pdf_text(header_line), ln=True)

        pdf.set_x(32 if logo_path else 10)
        pdf.set_font("Helvetica", "B", 9)
        pdf.cell(0, 5, _pdf_text(f"Application: {school_short} - GESTION SCHOOL"), ln=True)

        top_line_y = max(pdf.get_y() + 2, 28)
        pdf.set_draw_color(60, 60, 60)
        pdf.line(10, top_line_y, 138, top_line_y)
        pdf.set_y(top_line_y + 3)

        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 8, _pdf_text("RECU DE PAIEMENT"), ln=True, align="C")
        pdf.ln(2)

        label_width = 38
        value_width = 90

        rows = [
            ("Recu N°", str(payment.id)),
            ("Date", payment.created_at.strftime("%d/%m/%Y %H:%M")),
            ("Eleve", student_name),
            ("Matricule", student.matricule if student else "N/A"),
            ("Classe", class_name),
            ("Annee", academic_year),
            ("Type de frais", payment.fee.get_fee_type_display() if payment.fee else "N/A"),
            ("Montant verse", f"{payment.amount} FCFA"),
            ("Methode", payment.method),
            ("Reference", payment.reference or "-"),
            ("Encaisse par", receiver_name or "N/A"),
            ("Solde restant", f"{payment.fee.balance} FCFA"),
        ]

        for label, value in rows:
            pdf.set_font("Helvetica", "B", 9)
            pdf.cell(label_width, 7, _pdf_text(label), border=1)
            pdf.set_font("Helvetica", size=9)
            pdf.cell(value_width, 7, _pdf_text(str(value))[:78], border=1, ln=True)

        pdf.ln(3)
        pdf.set_font("Helvetica", size=8)
        pdf.multi_cell(
            0,
            4,
            _pdf_text(
                f"Merci pour votre paiement. Ce recu est emis par {school_short}."
            ),
        )

        signature_y = pdf.get_y() + 9
        pdf.line(12, signature_y, 58, signature_y)
        pdf.line(90, signature_y, 136, signature_y)
        pdf.set_y(signature_y + 1)
        pdf.set_font("Helvetica", size=8)
        pdf.cell(46, 5, _pdf_text("Signature caissier"), align="C")
        pdf.cell(0, 5, _pdf_text("Signature parent / eleve"), align="R")

        return pdf_output_response(pdf, f"receipt_{payment.id}.pdf")


class PaymentExcelExportView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "Paiements"

        school_name = getattr(settings, "SCHOOL_NAME", "LYCEE TECHNIQUE OUMAR BAH")
        school_short = getattr(settings, "SCHOOL_SHORT", "LTOB")
        school_level = getattr(settings, "SCHOOL_LEVEL", "1er etage")
        school_phone = getattr(settings, "SCHOOL_PHONE", "")
        logo_path = _school_logo_path()

        columns = [
            "Recu N°",
            "Eleve",
            "Matricule",
            "Classe",
            "Type de frais",
            "Montant (FCFA)",
            "Methode",
            "Reference",
            "Date",
            "Encaisse par",
        ]
        last_col = len(columns)
        last_col_letter = get_column_letter(last_col)

        sheet.merge_cells(f"A1:{last_col_letter}1")
        sheet.merge_cells(f"A2:{last_col_letter}2")
        sheet.merge_cells(f"A3:{last_col_letter}3")

        sheet["A1"] = school_name
        sheet["A2"] = f"{school_level} | Tel: {school_phone}" if school_phone else school_level
        sheet["A3"] = f"ETAT DES PAIEMENTS - {school_short}"

        sheet["A1"].font = Font(bold=True, size=16, color="1F3B63")
        sheet["A2"].font = Font(size=11, color="3F3F3F")
        sheet["A3"].font = Font(bold=True, size=12, color="FFFFFF")
        sheet["A3"].fill = PatternFill(fill_type="solid", fgColor="1F4E78")

        sheet["A1"].alignment = Alignment(horizontal="center", vertical="center")
        sheet["A2"].alignment = Alignment(horizontal="center", vertical="center")
        sheet["A3"].alignment = Alignment(horizontal="center", vertical="center")

        sheet.row_dimensions[1].height = 28
        sheet.row_dimensions[2].height = 20
        sheet.row_dimensions[3].height = 24

        if logo_path:
            try:
                from openpyxl.drawing.image import Image as XLImage

                logo = XLImage(logo_path)
                logo.width = 50
                logo.height = 50
                logo_anchor_col = get_column_letter(max(1, last_col - 1))
                sheet.add_image(logo, f"{logo_anchor_col}1")
            except Exception:
                pass

        thin_side = Side(style="thin", color="C8CDD3")
        thin_border = Border(left=thin_side, right=thin_side, top=thin_side, bottom=thin_side)

        header_row = 5
        for col_index, title in enumerate(columns, start=1):
            cell = sheet.cell(row=header_row, column=col_index, value=title)
            cell.font = Font(bold=True, color="FFFFFF")
            cell.fill = PatternFill(fill_type="solid", fgColor="3A6EA5")
            cell.alignment = Alignment(horizontal="center", vertical="center")
            cell.border = thin_border

        payments = _allowed_payments_queryset(request.user).order_by("-created_at")

        row_index = header_row + 1
        total_amount = 0.0

        for payment in payments:
            student = payment.fee.student if payment.fee else None
            student_user = student.user if student else None
            student_name = ""
            if student_user:
                student_name = student_user.get_full_name().strip() or student_user.username

            receiver = payment.received_by
            receiver_name = ""
            if receiver:
                receiver_name = receiver.get_full_name().strip() or receiver.username

            amount_value = float(payment.amount)
            total_amount += amount_value

            row_values = [
                payment.id,
                student_name,
                student.matricule if student else "N/A",
                student.classroom.name if student and student.classroom else "N/A",
                payment.fee.get_fee_type_display() if payment.fee else "N/A",
                amount_value,
                payment.method,
                payment.reference or "-",
                payment.created_at.strftime("%d/%m/%Y %H:%M"),
                receiver_name or "N/A",
            ]

            for col_index, value in enumerate(row_values, start=1):
                cell = sheet.cell(row=row_index, column=col_index, value=value)
                cell.border = thin_border
                if col_index == 6:
                    cell.number_format = '#,##0.00'
                    cell.alignment = Alignment(horizontal="right", vertical="center")
                elif col_index in (1, 9):
                    cell.alignment = Alignment(horizontal="center", vertical="center")
                else:
                    cell.alignment = Alignment(horizontal="left", vertical="center")

            row_index += 1

        if row_index == header_row + 1:
            sheet.merge_cells(start_row=row_index, start_column=1, end_row=row_index, end_column=last_col)
            empty_cell = sheet.cell(row=row_index, column=1, value="Aucun paiement disponible.")
            empty_cell.alignment = Alignment(horizontal="center", vertical="center")
            empty_cell.font = Font(italic=True, color="6B7280")
            empty_cell.border = thin_border
            row_index += 1

        summary_row = row_index + 1
        sheet.merge_cells(start_row=summary_row, start_column=1, end_row=summary_row, end_column=5)
        summary_label_cell = sheet.cell(row=summary_row, column=1, value="TOTAL ENCAISSE")
        summary_label_cell.font = Font(bold=True, color="1F3B63")
        summary_label_cell.fill = PatternFill(fill_type="solid", fgColor="E8EEF7")
        summary_label_cell.alignment = Alignment(horizontal="center", vertical="center")
        summary_label_cell.border = thin_border

        summary_value_cell = sheet.cell(row=summary_row, column=6, value=total_amount)
        summary_value_cell.number_format = '#,##0.00'
        summary_value_cell.font = Font(bold=True, color="1F3B63")
        summary_value_cell.fill = PatternFill(fill_type="solid", fgColor="E8EEF7")
        summary_value_cell.alignment = Alignment(horizontal="right", vertical="center")
        summary_value_cell.border = thin_border

        for col_index in range(7, last_col + 1):
            empty = sheet.cell(row=summary_row, column=col_index, value="")
            empty.fill = PatternFill(fill_type="solid", fgColor="E8EEF7")
            empty.border = thin_border

        generated_row = summary_row + 2
        sheet.merge_cells(start_row=generated_row, start_column=1, end_row=generated_row, end_column=last_col)
        generated_by = request.user.get_full_name().strip() or request.user.username
        generated_at = timezone.localtime().strftime("%d/%m/%Y %H:%M")
        generated_cell = sheet.cell(
            row=generated_row,
            column=1,
            value=f"Genere le {generated_at} par {generated_by}",
        )
        generated_cell.font = Font(italic=True, color="6B7280")
        generated_cell.alignment = Alignment(horizontal="left", vertical="center")

        column_widths = [10, 28, 16, 18, 18, 16, 16, 18, 20, 22]
        for col_index, width in enumerate(column_widths, start=1):
            sheet.column_dimensions[get_column_letter(col_index)].width = width

        sheet.freeze_panes = "A6"

        response = HttpResponse(content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        response["Content-Disposition"] = 'attachment; filename="payments_export.xlsx"'
        workbook.save(response)
        return response


class StudentCardPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, student_id: int):
        student = get_object_or_404(
            Student.objects.select_related("user", "classroom", "parent", "parent__user"),
            id=student_id,
        )
        _ensure_student_access(request.user, student)

        school = _school_identity()
        logo_path = _school_logo_path()

        pdf = FPDF(format=(105, 148))
        _add_student_card_page(pdf, student, school=school, logo_path=logo_path)

        return pdf_output_response(pdf, f"carte_eleve_{student.matricule}.pdf")


class ClassStudentCardsPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, classroom_id: int):
        if getattr(request.user, "role", "") in {UserRole.PARENT, UserRole.STUDENT}:
            raise PermissionDenied("Accès refusé aux cartes de classe.")

        classroom = get_object_or_404(ClassRoom, id=classroom_id)
        include_archived = (
            str(request.query_params.get("include_archived", "false")).strip().lower()
            in {"1", "true", "yes"}
        )
        layout_mode = str(request.query_params.get("layout_mode", "standard")).strip().lower()
        if layout_mode not in {"standard", "a4_6up", "a4_9up"}:
            return Response(
                {"detail": "layout_mode invalide. Valeurs: standard, a4_6up, a4_9up."},
                status=400,
            )

        queryset = Student.objects.select_related(
            "user", "classroom", "parent", "parent__user"
        ).filter(classroom_id=classroom.id)
        if not include_archived:
            queryset = queryset.filter(is_archived=False)

        students = list(queryset.order_by("user__last_name", "user__first_name", "matricule"))
        if not students:
            return Response(
                {"detail": "Aucun élève trouvé pour cette classe."},
                status=404,
            )

        school = _school_identity()
        logo_path = _school_logo_path()
        pdf = _build_student_cards_pdf(
            students,
            school=school,
            logo_path=logo_path,
            layout_mode=layout_mode,
        )

        class_slug = classroom.name.replace(" ", "_")
        suffix = (
            "_6parA4"
            if layout_mode == "a4_6up"
            else "_9parA4"
            if layout_mode == "a4_9up"
            else ""
        )
        return pdf_output_response(pdf, f"cartes_{class_slug}{suffix}.pdf")
