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
        "city": getattr(settings, "SCHOOL_CITY", "DAKAR"),
    }


def _active_academic_year_label() -> str:
    year = AcademicYear.objects.filter(is_active=True).order_by("-start_date", "-id").first()
    if year is None:
        year = AcademicYear.objects.order_by("-start_date", "-id").first()

    if year is None:
        current_year = timezone.localdate().year
        return f"{current_year} - {current_year + 1}"

    year_name = str(getattr(year, "name", "") or "").strip()
    if year_name:
        return year_name

    if year.start_date and year.end_date:
        return f"{year.start_date.year} - {year.end_date.year}"

    return f"Annee {year.id}"


def _student_name_parts(student: Student) -> tuple[str, str, str]:
    student_user = student.user
    if not student_user:
        return "-", "-", "-"

    first_name = (student_user.first_name or "").strip()
    last_name = (student_user.last_name or "").strip()
    full_name = (student_user.get_full_name() or "").strip() or student_user.username

    if not first_name and full_name:
        first_name = full_name.split(" ", 1)[0]
    if not last_name and full_name and " " in full_name:
        last_name = full_name.split(" ", 1)[1]

    return first_name or "-", last_name or "-", full_name or "-"


def _student_card_number(student: Student) -> str:
    digits = "".join(ch for ch in str(student.matricule or "") if ch.isdigit())
    if digits:
        return digits[-5:].zfill(5)
    return str(student.id).zfill(5)


def _format_fcfa(value) -> str:
    raw = str(value or "0").strip()
    if not raw:
        raw = "0"

    if "FCFA" in raw.upper():
        return raw

    normalized = raw.replace(" ", "").replace(",", ".")
    try:
        parsed = int(round(float(normalized)))
        return f"{parsed:,}".replace(",", " ") + " FCFA"
    except Exception:
        return f"{raw} FCFA"


def _draw_card_separator_line(pdf: FPDF, x1: float, y: float, x2: float) -> None:
    if x2 <= x1:
        return

    pdf.set_draw_color(165, 181, 205)
    try:
        pdf.dashed_line(x1, y, x2, y, dash_length=0.9, space_length=0.8)
    except Exception:
        pdf.line(x1, y, x2, y)


def _draw_student_card_template(
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
    if width <= 0 or height <= 0:
        return

    compact = width < 72
    outer_line_w = max(0.14, min(0.55, width * 0.004))
    inset = max(0.45, min(1.2, min(width, height) * 0.02))
    content_pad_x = max(0.55, min(1.3, width * 0.016))
    content_pad_y = max(0.45, min(1.1, height * 0.014))

    pdf.set_fill_color(245, 247, 251)
    pdf.set_draw_color(71, 92, 124)
    pdf.set_line_width(outer_line_w)
    pdf.rect(x, y, width, height, style="DF")

    pdf.set_draw_color(141, 156, 179)
    pdf.set_line_width(max(0.1, outer_line_w * 0.45))
    pdf.rect(x + inset, y + inset, width - (2 * inset), height - (2 * inset))

    content_x = x + inset + content_pad_x
    content_y = y + inset + content_pad_y
    content_w = width - (2 * (inset + content_pad_x))
    content_h = height - (2 * (inset + content_pad_y))
    if content_w <= 0 or content_h <= 0:
        return

    school_name = _pdf_text(school["name"]).upper()[:64]
    subtitle = _pdf_text(f"{school['short']} ({school['level']})").upper()[:56]
    phone_line = _pdf_text(f"Tel : {school['phone']}")[:56] if school["phone"] else ""

    title_font = 11.6 if width >= 130 else 9.6 if width >= 92 else 7.1 if width >= 72 else 5.8
    subtitle_font = title_font * 0.77
    phone_font = title_font * 0.7

    if logo_path and width >= 68:
        try:
            logo_w = min(10.5, max(4.8, content_w * 0.12))
            pdf.image(logo_path, x=content_x + 0.25, y=content_y + 0.2, w=logo_w)
        except Exception:
            pass

    pdf.set_text_color(23, 69, 137)
    pdf.set_xy(content_x, content_y)
    pdf.set_font("Helvetica", "B", title_font)
    pdf.cell(content_w, 4.8, school_name, align="C")

    pdf.set_text_color(30, 35, 43)
    pdf.set_xy(content_x, content_y + 4.5)
    pdf.set_font("Helvetica", "B", subtitle_font)
    pdf.cell(content_w, 3.9, subtitle, align="C")

    if phone_line:
        pdf.set_text_color(182, 53, 59)
        pdf.set_xy(content_x, content_y + 7.8)
        pdf.set_font("Helvetica", "B", phone_font)
        pdf.cell(content_w, 3.4, phone_line, align="C")

    title_band_y = content_y + (10.8 if width >= 72 else 9.2)
    title_band_h = max(2.8, min(6.1, content_h * 0.086))
    pdf.set_fill_color(24, 93, 168)
    pdf.rect(content_x, title_band_y, content_w, title_band_h, style="F")
    pdf.set_text_color(255, 255, 255)
    pdf.set_xy(content_x, title_band_y + 0.1)
    pdf.set_font(
        "Helvetica",
        "B",
        12.0 if width >= 130 else 9.0 if width >= 92 else 6.9 if width >= 72 else 5.5,
    )
    pdf.cell(content_w, title_band_h - 0.2, _pdf_text("CARTE SCOLAIRE"), align="C")

    footer_h = max(5.8, min(15.5, content_h * 0.19))
    body_top = title_band_y + title_band_h + max(0.8, min(2.1, content_h * 0.022))
    body_bottom = content_y + content_h - footer_h
    if body_bottom <= body_top:
        body_bottom = body_top + max(12.0, content_h * 0.35)

    photo_x = content_x + max(0.2, min(1.2, content_w * 0.012))
    photo_w = max(13.0, min(34.0, content_w * (0.31 if not compact else 0.34)))
    max_photo_h = max(18.0, body_bottom - body_top)
    photo_h = min(47.0, max_photo_h)
    photo_y = body_top

    pdf.set_fill_color(255, 255, 255)
    pdf.set_draw_color(36, 104, 172)
    pdf.set_line_width(max(0.1, outer_line_w * 0.55))
    pdf.rect(photo_x, photo_y, photo_w, photo_h, style="DF")

    # Keep the card layout and photo frame style, but never render student photos.
    pdf.set_fill_color(240, 244, 250)
    pdf.rect(photo_x + 0.5, photo_y + 0.5, photo_w - 1.0, photo_h - 1.0, style="F")
    pdf.set_text_color(82, 92, 108)
    pdf.set_xy(photo_x, photo_y + (photo_h / 2.0) - 2.3)
    pdf.set_font("Helvetica", "B", 7.0 if width >= 92 else 5.3)
    pdf.cell(photo_w, 2.8, _pdf_text("PROFIL"), align="C")
    pdf.set_xy(photo_x, photo_y + (photo_h / 2.0) + 0.1)
    pdf.set_font("Helvetica", "", 6.3 if width >= 92 else 4.8)
    pdf.cell(photo_w, 2.4, _pdf_text("SANS PHOTO"), align="C")

    first_name, last_name, _ = _student_name_parts(student)
    class_name = student.classroom.name if student.classroom else "Non attribuee"
    birth_date = student.birth_date.strftime("%d/%m/%Y") if student.birth_date else "-"
    year_label = _active_academic_year_label()
    card_number = _student_card_number(student)

    info_x = photo_x + photo_w + max(1.0, min(4.0, content_w * 0.03))
    info_right = content_x + content_w - max(0.2, min(1.4, content_w * 0.012))
    if info_right <= info_x:
        info_right = info_x + 8.0

    rows = [
        ("Nom" if not compact else "Nom", last_name),
        ("Prenom" if not compact else "Pre", first_name),
        ("Classe" if not compact else "Cls", class_name),
        ("Annee Scolaire" if not compact else "Annee", year_label),
        ("Matricule" if not compact else "Mat", student.matricule),
        ("Ne(e) le" if not compact else "Ne", birth_date),
    ]

    info_h = max(16.0, photo_h)
    row_step = info_h / len(rows)
    label_font = 8.6 if width >= 130 else 7.2 if width >= 92 else 5.7 if width >= 72 else 4.7
    value_font = label_font + (0.2 if width >= 92 else 0.1)
    label_w = min(max(7.4, (info_right - info_x) * 0.42), 27.0)
    value_limit = 35 if width >= 130 else 28 if width >= 92 else 20 if width >= 72 else 14

    row_y = photo_y + 0.3
    for label, value in rows:
        pdf.set_xy(info_x, row_y)
        pdf.set_text_color(45, 51, 62)
        pdf.set_font("Helvetica", "B", label_font)
        pdf.cell(label_w, max(2.4, row_step * 0.52), _pdf_text(f"{label} :"))

        pdf.set_text_color(28, 72, 136)
        pdf.set_font("Helvetica", "B", value_font)
        pdf.cell(max(4.0, info_right - info_x - label_w), max(2.4, row_step * 0.52), _pdf_text(value)[:value_limit])

        _draw_card_separator_line(pdf, info_x, row_y + (row_step * 0.76), info_right)
        row_y += row_step

    card_num_y = body_bottom + max(0.7, footer_h * 0.13)
    card_num_font = 9.3 if width >= 130 else 7.7 if width >= 92 else 5.9 if width >= 72 else 4.9
    pdf.set_xy(photo_x, card_num_y)
    pdf.set_text_color(44, 49, 58)
    pdf.set_font("Helvetica", "B", card_num_font)
    pdf.cell(24, max(2.8, footer_h * 0.35), _pdf_text("N° de Carte :"))
    pdf.set_text_color(27, 71, 134)
    pdf.cell(20, max(2.8, footer_h * 0.35), _pdf_text(card_number))
    _draw_card_separator_line(pdf, photo_x, card_num_y + max(2.9, footer_h * 0.36), photo_x + min(47.0, content_w * 0.36))

    stamp_d = max(8.0, min(26.5, min(content_w * 0.29, content_h * 0.31)))
    stamp_x = content_x + content_w - stamp_d - max(0.6, min(1.4, content_w * 0.018))
    stamp_y = content_y + content_h - stamp_d - max(0.5, min(1.3, content_h * 0.018))

    pdf.set_draw_color(31, 90, 161)
    pdf.set_line_width(max(0.12, outer_line_w * 0.6))
    try:
        pdf.ellipse(stamp_x, stamp_y, stamp_d, stamp_d)
        pdf.ellipse(
            stamp_x + (stamp_d * 0.17),
            stamp_y + (stamp_d * 0.17),
            stamp_d * 0.66,
            stamp_d * 0.66,
        )
    except Exception:
        pdf.rect(stamp_x, stamp_y, stamp_d, stamp_d)
        pdf.rect(
            stamp_x + (stamp_d * 0.17),
            stamp_y + (stamp_d * 0.17),
            stamp_d * 0.66,
            stamp_d * 0.66,
        )

    if stamp_d >= 16.5:
        outer_stamp_font = 4.3 if width >= 92 else 3.6
        stamp_top = _pdf_text(school["name"])[:30]
        stamp_bottom = _pdf_text(f"{school['short']} - {school['city']}")[:24]
        pdf.set_text_color(31, 90, 161)
        pdf.set_xy(stamp_x - 0.4, stamp_y + 0.6)
        pdf.set_font("Helvetica", "B", outer_stamp_font)
        pdf.cell(stamp_d + 0.8, 2.3, stamp_top, align="C")
        pdf.set_xy(stamp_x - 0.4, stamp_y + stamp_d - 2.9)
        pdf.cell(stamp_d + 0.8, 2.3, stamp_bottom, align="C")

    center_font = 9.2 if width >= 130 else 7.5 if width >= 92 else 5.8 if width >= 72 else 4.6
    city_font = center_font * 0.86
    pdf.set_text_color(31, 90, 161)
    pdf.set_xy(stamp_x, stamp_y + (stamp_d * 0.36))
    pdf.set_font("Helvetica", "B", center_font)
    pdf.cell(stamp_d, stamp_d * 0.2, _pdf_text(school["short"])[:10], align="C")
    pdf.set_xy(stamp_x, stamp_y + (stamp_d * 0.56))
    pdf.set_font("Helvetica", "B", city_font)
    pdf.cell(stamp_d, stamp_d * 0.18, _pdf_text(school["city"])[:12], align="C")

    signature_x = max(info_x, stamp_x - max(12.0, content_w * 0.24))
    signature_y = content_y + content_h - max(4.6, footer_h * 0.34)
    signature_w = max(7.0, min(20.0, content_w * 0.16))

    pdf.set_draw_color(42, 87, 145)
    pdf.set_line_width(max(0.1, outer_line_w * 0.45))
    pdf.line(signature_x, signature_y, signature_x + (signature_w * 0.46), signature_y - (signature_w * 0.18))
    pdf.line(
        signature_x + (signature_w * 0.14),
        signature_y + (signature_w * 0.05),
        signature_x + (signature_w * 0.68),
        signature_y - (signature_w * 0.08),
    )
    pdf.line(
        signature_x + (signature_w * 0.28),
        signature_y + (signature_w * 0.08),
        signature_x + (signature_w * 0.82),
        signature_y - (signature_w * 0.03),
    )

    principal_font = 6.8 if width >= 130 else 5.8 if width >= 92 else 4.6 if width >= 72 else 3.8
    pdf.set_xy(signature_x + (signature_w * 0.25), signature_y + 1.0)
    pdf.set_text_color(45, 50, 60)
    pdf.set_font("Helvetica", "B", principal_font)
    pdf.cell(max(10.0, stamp_x - signature_x), 2.8, _pdf_text("Le Principal"), align="C")


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
    _draw_student_card_template(
        pdf,
        student,
        school=school,
        logo_path=logo_path,
        x=4,
        y=4,
        width=page_w - 8,
        height=page_h - 8,
    )


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
    _draw_student_card_template(
        pdf,
        student,
        school=school,
        logo_path=logo_path,
        x=x,
        y=y,
        width=width,
        height=height,
    )


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

    pdf = FPDF(format=(148, 105))
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

        school = _school_identity()
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

        payer_name = ""
        if student and student.parent and student.parent.user:
            parent_user = student.parent.user
            payer_name = parent_user.get_full_name().strip() or parent_user.username
        if not payer_name:
            payer_name = student_name or "Parent / Eleve"

        payment_amount_label = _format_fcfa(payment.amount)
        remaining_balance_label = _format_fcfa(payment.fee.balance if payment.fee else 0)
        receipt_no = f"RC-{timezone.localtime(payment.created_at).strftime('%Y%m%d')}-{payment.id:05d}"
        issue_date = timezone.localtime(payment.created_at).strftime("%d/%m/%Y %H:%M")
        fee_type = payment.fee.get_fee_type_display() if payment.fee else "N/A"
        method = payment.method or "N/A"
        reference = payment.reference or "-"

        pdf = FPDF(format="A5")
        pdf.add_page()
        pdf.set_auto_page_break(auto=False)

        page_x = 7
        page_y = 7
        page_w = pdf.w - 14
        page_h = pdf.h - 14

        pdf.set_fill_color(245, 247, 251)
        pdf.set_draw_color(71, 92, 124)
        pdf.set_line_width(0.45)
        pdf.rect(page_x, page_y, page_w, page_h, style="DF")

        pdf.set_draw_color(141, 156, 179)
        pdf.set_line_width(0.18)
        pdf.rect(page_x + 0.8, page_y + 0.8, page_w - 1.6, page_h - 1.6)

        content_x = page_x + 3.4
        content_y = page_y + 3.0
        content_w = page_w - 6.8

        if logo_path:
            try:
                pdf.image(logo_path, x=content_x, y=content_y + 0.2, w=12)
            except Exception:
                pass

        header_x = content_x + (14 if logo_path else 0)
        header_w = content_w - (14 if logo_path else 0)

        pdf.set_text_color(23, 69, 137)
        pdf.set_xy(header_x, content_y)
        pdf.set_font("Helvetica", "B", 12)
        pdf.cell(header_w, 5.8, _pdf_text(school["name"]).upper()[:62], align="C")

        pdf.set_text_color(33, 38, 46)
        pdf.set_xy(header_x, content_y + 5.0)
        pdf.set_font("Helvetica", "B", 9)
        pdf.cell(
            header_w,
            4,
            _pdf_text(f"{school['short']} ({school['level']})").upper()[:60],
            align="C",
        )

        if school["phone"]:
            pdf.set_text_color(182, 53, 59)
            pdf.set_xy(header_x, content_y + 8.6)
            pdf.set_font("Helvetica", "B", 8)
            pdf.cell(header_w, 3.6, _pdf_text(f"Tel : {school['phone']}"), align="C")

        title_y = content_y + 13.2
        pdf.set_fill_color(24, 93, 168)
        pdf.rect(content_x, title_y, content_w, 7.1, style="F")
        pdf.set_text_color(255, 255, 255)
        pdf.set_xy(content_x, title_y + 0.4)
        pdf.set_font("Helvetica", "B", 13)
        pdf.cell(content_w, 5.8, _pdf_text("RECU DE PAIEMENT"), align="C")

        meta_y = title_y + 8.8
        meta_h = 5.8
        left_meta_w = content_w * 0.52
        center_meta_w = content_w * 0.27
        right_meta_w = content_w - left_meta_w - center_meta_w

        pdf.set_fill_color(235, 241, 250)
        pdf.set_draw_color(157, 173, 197)
        pdf.set_line_width(0.16)
        pdf.rect(content_x, meta_y, left_meta_w, meta_h, style="DF")
        pdf.rect(content_x + left_meta_w, meta_y, center_meta_w, meta_h, style="DF")
        pdf.rect(content_x + left_meta_w + center_meta_w, meta_y, right_meta_w, meta_h, style="DF")

        pdf.set_text_color(45, 50, 60)
        pdf.set_xy(content_x + 1, meta_y + 1.3)
        pdf.set_font("Helvetica", "B", 8)
        pdf.cell(left_meta_w - 2, 3.1, _pdf_text(f"Recu N° : {receipt_no}")[:42])

        pdf.set_xy(content_x + left_meta_w + 1, meta_y + 1.3)
        pdf.cell(center_meta_w - 2, 3.1, _pdf_text(f"Date : {issue_date}")[:28])

        pdf.set_xy(content_x + left_meta_w + center_meta_w + 1, meta_y + 1.3)
        pdf.cell(right_meta_w - 2, 3.1, _pdf_text(f"Annee : {academic_year}")[:20])

        section_gap = 2.6
        student_box_y = meta_y + meta_h + section_gap
        student_box_h = 28
        payment_box_y = student_box_y + student_box_h + section_gap
        payment_box_h = 35

        pdf.set_fill_color(252, 253, 255)
        pdf.set_draw_color(168, 181, 202)
        pdf.rect(content_x, student_box_y, content_w, student_box_h, style="DF")

        pdf.set_fill_color(237, 243, 251)
        pdf.rect(content_x, student_box_y, content_w, 5.6, style="F")
        pdf.set_text_color(28, 72, 136)
        pdf.set_xy(content_x + 1.2, student_box_y + 1.2)
        pdf.set_font("Helvetica", "B", 8.5)
        pdf.cell(content_w - 2.4, 3.2, _pdf_text("INFORMATIONS ELEVE"))

        info_x = content_x + 1.4
        info_y = student_box_y + 7.4
        info_rows = [
            ("Nom complet", student_name or "N/A"),
            ("Matricule", student.matricule if student else "N/A"),
            ("Classe", class_name),
            ("Payeur", payer_name),
        ]

        for index, (label, value) in enumerate(info_rows):
            row_y = info_y + (index * 4.9)
            pdf.set_xy(info_x, row_y)
            pdf.set_text_color(48, 55, 65)
            pdf.set_font("Helvetica", "B", 8)
            pdf.cell(27, 3.4, _pdf_text(f"{label} :"))
            pdf.set_text_color(28, 72, 136)
            pdf.set_font("Helvetica", "B", 8)
            pdf.cell(content_w - 31, 3.4, _pdf_text(str(value))[:56])
            pdf.set_draw_color(189, 200, 217)
            pdf.line(info_x, row_y + 3.7, content_x + content_w - 1.2, row_y + 3.7)

        pdf.set_fill_color(252, 253, 255)
        pdf.set_draw_color(168, 181, 202)
        pdf.rect(content_x, payment_box_y, content_w, payment_box_h, style="DF")

        pdf.set_fill_color(237, 243, 251)
        pdf.rect(content_x, payment_box_y, content_w, 5.6, style="F")
        pdf.set_text_color(28, 72, 136)
        pdf.set_xy(content_x + 1.2, payment_box_y + 1.2)
        pdf.set_font("Helvetica", "B", 8.5)
        pdf.cell(content_w - 2.4, 3.2, _pdf_text("DETAIL DU PAIEMENT"))

        details_x = content_x + 1.4
        details_y = payment_box_y + 7.4
        details_rows = [
            ("Type de frais", fee_type),
            ("Methode", method),
            ("Reference", reference),
            ("Encaisse par", receiver_name or "N/A"),
            ("Solde restant", remaining_balance_label),
        ]

        for index, (label, value) in enumerate(details_rows):
            row_y = details_y + (index * 4.3)
            pdf.set_xy(details_x, row_y)
            pdf.set_text_color(48, 55, 65)
            pdf.set_font("Helvetica", "B", 7.8)
            pdf.cell(25, 3.1, _pdf_text(f"{label} :"))
            pdf.set_text_color(28, 72, 136)
            pdf.set_font("Helvetica", "B", 7.8)
            pdf.cell((content_w * 0.56) - 2, 3.1, _pdf_text(str(value))[:34])

        amount_box_w = content_w * 0.36
        amount_box_x = content_x + content_w - amount_box_w - 1.2
        amount_box_y = payment_box_y + 10.4
        amount_box_h = 18.6
        pdf.set_fill_color(24, 93, 168)
        pdf.set_draw_color(18, 72, 133)
        pdf.rect(amount_box_x, amount_box_y, amount_box_w, amount_box_h, style="DF")

        pdf.set_text_color(255, 255, 255)
        pdf.set_xy(amount_box_x, amount_box_y + 2.0)
        pdf.set_font("Helvetica", "B", 8)
        pdf.cell(amount_box_w, 3.2, _pdf_text("MONTANT VERSE"), align="C")

        pdf.set_xy(amount_box_x, amount_box_y + 7.6)
        pdf.set_font("Helvetica", "B", 11.2)
        pdf.cell(amount_box_w, 5, _pdf_text(payment_amount_label)[:24], align="C")

        pdf.set_text_color(66, 72, 84)
        pdf.set_xy(content_x, payment_box_y + payment_box_h + 2.6)
        pdf.set_font("Helvetica", size=7.6)
        pdf.multi_cell(
            content_w,
            3.4,
            _pdf_text(
                f"Merci pour votre paiement. Ce recu certifie l'encaissement effectif de {payment_amount_label} au profit de {school['short']}."
            ),
        )

        signature_y = page_y + page_h - 9.5
        left_sign_x1 = content_x + 2
        left_sign_x2 = left_sign_x1 + 42
        right_sign_x2 = content_x + content_w - 2
        right_sign_x1 = right_sign_x2 - 42

        pdf.set_draw_color(115, 130, 154)
        pdf.set_line_width(0.2)
        pdf.line(left_sign_x1, signature_y, left_sign_x2, signature_y)
        pdf.line(right_sign_x1, signature_y, right_sign_x2, signature_y)

        pdf.set_xy(left_sign_x1, signature_y + 0.6)
        pdf.set_font("Helvetica", "B", 7.3)
        pdf.set_text_color(66, 72, 84)
        pdf.cell(left_sign_x2 - left_sign_x1, 3.4, _pdf_text("Signature caissier"), align="C")

        pdf.set_xy(right_sign_x1, signature_y + 0.6)
        pdf.cell(right_sign_x2 - right_sign_x1, 3.4, _pdf_text("Signature parent / eleve"), align="C")

        stamp_size = 18
        stamp_x = content_x + content_w - stamp_size - 1.4
        stamp_y = page_y + page_h - stamp_size - 13.0
        pdf.set_draw_color(31, 90, 161)
        pdf.set_line_width(0.24)
        try:
            pdf.ellipse(stamp_x, stamp_y, stamp_size, stamp_size)
            pdf.ellipse(stamp_x + 2.8, stamp_y + 2.8, stamp_size - 5.6, stamp_size - 5.6)
        except Exception:
            pdf.rect(stamp_x, stamp_y, stamp_size, stamp_size)
            pdf.rect(stamp_x + 2.8, stamp_y + 2.8, stamp_size - 5.6, stamp_size - 5.6)

        pdf.set_text_color(31, 90, 161)
        pdf.set_xy(stamp_x, stamp_y + 6.0)
        pdf.set_font("Helvetica", "B", 7.8)
        pdf.cell(stamp_size, 3.2, _pdf_text(school["short"])[:12], align="C")
        pdf.set_xy(stamp_x, stamp_y + 9.6)
        pdf.set_font("Helvetica", "B", 6.5)
        pdf.cell(stamp_size, 2.8, _pdf_text(school["city"])[:12], align="C")

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

        pdf = FPDF(format=(148, 105))
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
