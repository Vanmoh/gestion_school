import hashlib
import tempfile
from pathlib import Path

from django.conf import settings
from django.db.models import Avg, Q
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from fpdf import FPDF
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from PIL import Image
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from apps.accounts.models import UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamPlanning,
    ExamResult,
    Grade,
    Payment,
    Student,
    Subject,
    TeacherAssignment,
)
from apps.school.serializers import AcademicYearSerializer, PaymentSerializer, StudentSerializer
from apps.school.term_utils import normalize_term


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


def _etablissement_logo_path(student: Student) -> str | None:
    etablissement = getattr(student, "etablissement", None)
    if etablissement is None and getattr(student, "classroom", None) is not None:
        etablissement = getattr(student.classroom, "etablissement", None)
    if etablissement is None:
        return None

    logo_field = getattr(etablissement, "logo", None)
    if not logo_field:
        return None

    try:
        direct_path = Path(getattr(logo_field, "path", "") or "")
    except Exception:
        direct_path = None

    if direct_path and direct_path.exists():
        return str(direct_path)

    logo_name = str(getattr(logo_field, "name", "") or "").strip()
    media_root = str(getattr(settings, "MEDIA_ROOT", "") or "").strip()
    if logo_name and media_root:
        candidate = Path(media_root) / logo_name
        if candidate.exists():
            return str(candidate)

    return None


def _school_signature_asset_path() -> str | None:
    candidates = [
        Path(settings.BASE_DIR) / "assets" / "images" / "str_signature.png",
        Path(settings.BASE_DIR).parent / "frontend" / "gestion_school_app" / "assets" / "images" / "str_signature.png",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return None


def _school_stamp_asset_path() -> str | None:
    candidates = [
        Path(settings.BASE_DIR) / "assets" / "images" / "str_cachet_signature.png",
        Path(settings.BASE_DIR).parent / "frontend" / "gestion_school_app" / "assets" / "images" / "str_cachet_signature.png",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return None


def _pdf_compatible_image_path(source_path: str | None, *, cache_prefix: str) -> str | None:
    if not source_path:
        return None

    source = Path(source_path)
    if not source.exists():
        return None

    if source.suffix.lower() in {".jpg", ".jpeg"}:
        return str(source)

    try:
        cache_dir = Path(tempfile.gettempdir()) / "gestion_school_pdf_assets"
        cache_dir.mkdir(parents=True, exist_ok=True)

        stat = source.stat()
        cache_key = f"{source.resolve()}::{stat.st_mtime_ns}::{stat.st_size}"
        cache_hash = hashlib.sha1(cache_key.encode("utf-8")).hexdigest()[:12]
        cached_file = cache_dir / f"{cache_prefix}_{cache_hash}.jpg"

        if cached_file.exists():
            return str(cached_file)

        with Image.open(source) as image:
            if image.mode in {"RGBA", "LA"}:
                rgb = Image.new("RGB", image.size, (255, 255, 255))
                rgb.paste(image.convert("RGB"), mask=image.getchannel("A"))
            elif image.mode == "P":
                rgba = image.convert("RGBA")
                rgb = Image.new("RGB", rgba.size, (255, 255, 255))
                rgb.paste(rgba, mask=rgba.getchannel("A"))
            else:
                rgb = image.convert("RGB")

            rgb.save(cached_file, format="JPEG", quality=95, optimize=True)

        return str(cached_file)
    except Exception:
        # Last resort: return original path and let FPDF attempt loading it.
        return str(source)


def pdf_output_response(pdf: FPDF, filename: str) -> HttpResponse:
    data = bytes(pdf.output())
    response = HttpResponse(data, content_type="application/pdf")
    response["Content-Disposition"] = f'attachment; filename="{filename}"'
    # Prevent stale browser/proxy cache for dynamically generated PDFs.
    response["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
    response["Pragma"] = "no-cache"
    response["Expires"] = "0"
    response["X-Card-Template-Version"] = "2026-03-14-2"
    return response


def _school_identity() -> dict[str, str]:
    return {
        "name": getattr(settings, "SCHOOL_NAME", "LYCEE TECHNIQUE OUMAR BAH"),
        "short": getattr(settings, "SCHOOL_SHORT", "LTOB"),
        "level": getattr(settings, "SCHOOL_LEVEL", "1er etage"),
        "phone": getattr(settings, "SCHOOL_PHONE", ""),
        "city": getattr(settings, "SCHOOL_CITY", "DAKAR"),
    }


def _school_identity_for_student(student: Student) -> dict[str, str]:
    school = _school_identity()

    etablissement = getattr(student, "etablissement", None)
    if etablissement is None and getattr(student, "classroom", None) is not None:
        etablissement = getattr(student.classroom, "etablissement", None)

    if etablissement is None:
        return school

    etablissement_name = str(getattr(etablissement, "name", "") or "").strip()
    etablissement_phone = str(getattr(etablissement, "phone", "") or "").strip()
    etablissement_address = str(getattr(etablissement, "address", "") or "").strip()

    if etablissement_name:
        school["name"] = etablissement_name
        school["short"] = etablissement_name[:16].upper()
    if etablissement_phone:
        school["phone"] = etablissement_phone
    if etablissement_address:
        school["level"] = etablissement_address

    return school


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


def _student_photo_path(student: Student) -> str | None:
    photo_field = getattr(student, "photo", None)
    if not photo_field:
        return None

    try:
        direct_path = Path(getattr(photo_field, "path", "") or "")
    except Exception:
        direct_path = None

    if direct_path and direct_path.exists():
        return str(direct_path)

    photo_name = str(getattr(photo_field, "name", "") or "").strip()
    media_root = str(getattr(settings, "MEDIA_ROOT", "") or "").strip()
    if photo_name and media_root:
        candidate = Path(media_root) / photo_name
        if candidate.exists():
            return str(candidate)

    return None


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
    outer_line_w = max(0.12, min(0.44, width * 0.0034))
    inset = max(0.36, min(1.16, min(width, height) * 0.016))
    pad_x = max(0.55, min(1.9, width * 0.014))
    pad_y = max(0.45, min(1.45, height * 0.014))

    pdf.set_fill_color(246, 248, 252)
    pdf.set_draw_color(90, 99, 114)
    pdf.set_line_width(outer_line_w)
    pdf.rect(x, y, width, height, style="DF")

    pdf.set_draw_color(160, 169, 184)
    pdf.set_line_width(max(0.08, outer_line_w * 0.62))
    pdf.rect(x + inset, y + inset, width - (2 * inset), height - (2 * inset))

    content_x = x + inset + pad_x
    content_y = y + inset + pad_y
    content_w = width - (2 * (inset + pad_x))
    content_h = height - (2 * (inset + pad_y))
    if content_w <= 0 or content_h <= 0:
        return

    school_name_raw = (school.get("name") or "LYCEE TECHNIQUE OUMAR BAH").strip().upper()
    school_short_raw = (school.get("short") or "LTOB").strip().upper()
    school_level_raw = (school.get("level") or "1er ETAGE").strip().upper()
    school_phone_raw = (school.get("phone") or "78 78 59 13 / 66 74 22 32").strip()

    school_name = _pdf_text(school_name_raw)
    school_subtitle = _pdf_text(f"{school_short_raw} ({school_level_raw})")
    school_phone = _pdf_text(f"Tel : {school_phone_raw}")

    header_h = max(8.7, min(16.2, content_h * 0.22))
    header_name_font = 11.0 if width >= 120 else 8.8 if width >= 85 else 6.8 if width >= 72 else 5.8
    header_sub_font = header_name_font * 0.86
    header_phone_font = header_name_font * 0.66

    pdf.set_text_color(20, 70, 136)
    pdf.set_xy(content_x, content_y)
    pdf.set_font("Helvetica", "B", header_name_font)
    pdf.cell(content_w, max(2.7, header_h * 0.34), school_name, align="C")

    pdf.set_text_color(44, 45, 59)
    pdf.set_xy(content_x, content_y + max(2.5, header_h * 0.31))
    pdf.set_font("Helvetica", "B", header_sub_font)
    pdf.cell(content_w, max(2.3, header_h * 0.25), school_subtitle, align="C")

    pdf.set_text_color(177, 59, 67)
    pdf.set_xy(content_x, content_y + max(4.8, header_h * 0.56))
    pdf.set_font("Helvetica", "B", header_phone_font)
    pdf.cell(content_w, max(2.0, header_h * 0.18), school_phone, align="C")

    title_y = content_y + header_h + max(0.45, content_h * 0.008)
    title_h = max(3.1, min(5.9, content_h * 0.088))
    pdf.set_fill_color(27, 93, 168)
    pdf.rect(content_x, title_y, content_w, title_h, style="F")
    pdf.set_text_color(255, 255, 255)
    pdf.set_xy(content_x, title_y + 0.05)
    pdf.set_font(
        "Helvetica",
        "B",
        10.6 if width >= 120 else 8.6 if width >= 85 else 6.8 if width >= 72 else 5.5,
    )
    pdf.cell(content_w, max(2.0, title_h - 0.1), _pdf_text("CARTE SCOLAIRE"), align="C")

    footer_h = max(10.2, min(17.6, content_h * 0.24))
    body_top = title_y + title_h + max(0.62, content_h * 0.01)
    body_bottom = content_y + content_h - footer_h - max(0.32, content_h * 0.006)
    if body_bottom <= body_top:
        body_bottom = body_top + max(9.5, content_h * 0.28)

    photo_x = content_x
    photo_y = body_top
    photo_w = max(13.0, min(34.0, content_w * (0.30 if not compact else 0.34)))
    photo_h = max(15.0, body_bottom - body_top)

    pdf.set_fill_color(255, 255, 255)
    pdf.set_draw_color(50, 106, 176)
    pdf.set_line_width(max(0.09, outer_line_w * 0.57))
    pdf.rect(photo_x, photo_y, photo_w, photo_h, style="DF")

    photo_path = _student_photo_path(student)
    if photo_path:
        try:
            pdf.image(
                photo_path,
                x=photo_x + 0.5,
                y=photo_y + 0.5,
                w=max(1.0, photo_w - 1.0),
                h=max(1.0, photo_h - 1.0),
            )
        except Exception:
            photo_path = None

    if not photo_path:
        pdf.set_fill_color(232, 238, 248)
        pdf.rect(photo_x + 0.5, photo_y + 0.5, photo_w - 1.0, photo_h - 1.0, style="F")
        pdf.set_text_color(95, 108, 128)
        pdf.set_xy(photo_x, photo_y + (photo_h / 2.0) - 1.4)
        pdf.set_font("Helvetica", "B", 6.1 if width >= 85 else 4.9)
        pdf.cell(photo_w, 2.6, _pdf_text("PHOTO"), align="C")

    first_name, last_name, _ = _student_name_parts(student)
    class_name = student.classroom.name if student.classroom else "Non attribuee"
    birth_date = student.birth_date.strftime("%d/%m/%Y") if student.birth_date else "-"
    year_label = _active_academic_year_label()

    info_x = photo_x + photo_w + max(1.0, min(3.4, content_w * 0.024))
    info_w = max(8.0, (content_x + content_w) - info_x)
    label_w = max(6.5, min(info_w * 0.42, info_w - 4.0))
    row_h = max(2.1, min(4.0, (body_bottom - body_top) * 0.135))
    row_gap = max(0.45, min(1.25, row_h * 0.42))
    label_font = 8.2 if width >= 120 else 6.7 if width >= 85 else 5.4 if width >= 72 else 4.7
    value_font = label_font * 1.02
    value_limit = 40 if width >= 120 else 31 if width >= 85 else 24 if width >= 72 else 17

    def _draw_info_row(row_y: float, label: str, value: str) -> None:
        pdf.set_xy(info_x, row_y)
        pdf.set_text_color(44, 48, 59)
        pdf.set_font("Helvetica", "B", label_font)
        pdf.cell(label_w, row_h, _pdf_text(f"{label} :"), align="L")

        pdf.set_xy(info_x + label_w, row_y)
        pdf.set_text_color(25, 72, 138)
        pdf.set_font("Helvetica", "B", value_font)
        pdf.cell(info_w - label_w, row_h, _pdf_text(value or "-")[:value_limit], align="L")

        _draw_card_separator_line(
            pdf,
            info_x,
            row_y + row_h + 0.05,
            info_x + info_w,
        )

    row_y = body_top + max(0.1, row_h * 0.05)
    for label, value in [
        ("Nom", last_name),
        ("Prenom", first_name),
        ("Classe", class_name),
        ("Annee scolaire", year_label),
        ("Matricule", student.matricule or "-"),
    ]:
        _draw_info_row(row_y, label, value)
        row_y += row_h + row_gap

    row_y += max(0.25, row_gap * 0.4)
    _draw_info_row(row_y, "Ne(e) le", birth_date)

    footer_y = content_y + content_h - footer_h

    card_digits = ""
    if int(getattr(student, "id", 0) or 0) > 0:
        card_digits = str(student.id).zfill(5)
    if not card_digits:
        raw_digits = "".join(ch for ch in str(student.matricule or "") if ch.isdigit())
        card_digits = (raw_digits[-5:] if raw_digits else "00000").zfill(5)

    number_x = content_x + max(0.15, content_w * 0.004)
    number_y = footer_y + max(0.46, footer_h * 0.11)
    number_label_font = 8.8 if width >= 120 else 6.9 if width >= 85 else 5.6 if width >= 72 else 4.8
    number_value_font = number_label_font * 1.02

    signature_asset_path = _pdf_compatible_image_path(
        _school_signature_asset_path(),
        cache_prefix="signature",
    )
    stamp_asset_path = _pdf_compatible_image_path(
        _school_stamp_asset_path(),
        cache_prefix="stamp",
    )

    stamp_d = max(9.5, min(22.0, footer_h * 1.02))
    stamp_x = content_x + content_w - stamp_d - max(0.25, content_w * 0.002)
    stamp_y = footer_y + max(0.2, (footer_h - stamp_d) * 0.54)

    signature_w = max(13.0, min(34.0, content_w * 0.30))
    signature_h = max(4.3, min(9.0, footer_h * 0.48))
    signature_x = stamp_x - signature_w - max(0.9, content_w * 0.015)
    signature_y = footer_y + max(0.18, footer_h * 0.30)

    number_max_x = max(number_x + 12.0, signature_x - max(0.8, content_w * 0.01))
    number_line_w = max(8.0, number_max_x - number_x)

    pdf.set_xy(number_x, number_y)
    pdf.set_text_color(44, 48, 59)
    pdf.set_font("Helvetica", "B", number_label_font)
    label_text = _pdf_text("No de Carte :")
    label_draw_w = min(number_line_w * 0.62, max(10.0, number_line_w - 8.0))
    pdf.cell(label_draw_w, max(2.1, footer_h * 0.26), label_text, align="L")

    pdf.set_xy(number_x + label_draw_w, number_y)
    pdf.set_text_color(25, 72, 138)
    pdf.set_font("Helvetica", "B", number_value_font)
    pdf.cell(
        max(2.0, number_line_w - label_draw_w),
        max(2.1, footer_h * 0.26),
        _pdf_text(card_digits),
        align="L",
    )
    _draw_card_separator_line(
        pdf,
        number_x,
        number_y + max(1.9, footer_h * 0.26),
        number_x + number_line_w,
    )

    if signature_asset_path:
        try:
            pdf.image(
                signature_asset_path,
                x=signature_x,
                y=signature_y,
                w=signature_w,
                h=signature_h,
            )
        except Exception:
            signature_asset_path = None

    if not signature_asset_path:
        line_y = signature_y + (signature_h * 0.58)
        pdf.set_draw_color(55, 98, 156)
        pdf.set_line_width(max(0.08, outer_line_w * 0.5))
        pdf.line(signature_x + 0.4, line_y, signature_x + signature_w - 0.4, line_y)

    pdf.set_xy(signature_x, signature_y + signature_h + max(0.18, footer_h * 0.02))
    pdf.set_text_color(44, 48, 59)
    pdf.set_font("Helvetica", "B", 5.9 if width >= 85 else 4.8)
    pdf.cell(signature_w, max(1.8, footer_h * 0.2), _pdf_text("Le Principal"), align="C")

    if stamp_asset_path:
        try:
            pdf.image(stamp_asset_path, x=stamp_x, y=stamp_y, w=stamp_d, h=stamp_d)
        except Exception:
            stamp_asset_path = None

    if not stamp_asset_path:
        pdf.set_draw_color(31, 92, 158)
        pdf.set_line_width(max(0.08, outer_line_w * 0.52))
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
        pdf.set_xy(stamp_x, stamp_y + (stamp_d * 0.48))
        pdf.set_text_color(31, 92, 158)
        pdf.set_font("Helvetica", "B", 4.2 if width >= 85 else 3.5)
        pdf.cell(stamp_d, stamp_d * 0.16, _pdf_text("Cachet"), align="C")


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


def _requested_etablissement_id(request):
    raw_value = request.headers.get("X-Etablissement-Id") or request.query_params.get("etablissement")
    if raw_value in (None, ""):
        return None
    try:
        parsed = int(raw_value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def _requested_etablissement_name(request):
    raw_name = request.headers.get("X-Etablissement-Name") or request.query_params.get("etablissement_name")
    if raw_name is None:
        return None
    cleaned = str(raw_name).strip()
    return cleaned or None


def _requested_etablissement(request):
    requested_id = _requested_etablissement_id(request)
    if requested_id:
        etablissement = Etablissement.objects.filter(id=requested_id).first()
        if etablissement:
            return etablissement

    requested_name = _requested_etablissement_name(request)
    if not requested_name:
        return None

    etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
    if etablissement:
        return etablissement

    return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()


def _effective_etablissement_id(request):
    user = request.user
    role = getattr(user, "role", "")

    if role == UserRole.SUPER_ADMIN:
        requested = _requested_etablissement(request)
        return requested.id if requested else None

    return getattr(user, "etablissement_id", None)


def _allowed_students_queryset(request):
    user = request.user
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

    target_etablissement_id = _effective_etablissement_id(request)
    if target_etablissement_id:
        return queryset.filter(
            Q(etablissement_id=target_etablissement_id)
            | Q(etablissement__isnull=True, classroom__etablissement_id=target_etablissement_id)
        )
    return queryset.none()


def _allowed_payments_queryset(request):
    user = request.user
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

    target_etablissement_id = _effective_etablissement_id(request)
    if target_etablissement_id:
        return queryset.filter(
            Q(fee__student__etablissement_id=target_etablissement_id)
            | Q(
                fee__student__etablissement__isnull=True,
                fee__student__classroom__etablissement_id=target_etablissement_id,
            )
        )
    return queryset.none()


def _ensure_student_access(request, student: Student) -> None:
    user = request.user
    role = getattr(user, "role", "")
    if role == UserRole.STUDENT and student.user_id != user.id:
        raise PermissionDenied("Accès refusé à ce bulletin.")

    if role == UserRole.PARENT:
        parent_user_id = student.parent.user_id if student.parent else None
        if parent_user_id != user.id:
            raise PermissionDenied("Accès refusé à ce bulletin.")

    target_etablissement_id = _effective_etablissement_id(request)
    student_etablissement_id = getattr(student, "etablissement_id", None)
    if student_etablissement_id is None and getattr(student, "classroom", None) is not None:
        student_etablissement_id = getattr(student.classroom, "etablissement_id", None)

    if target_etablissement_id and student_etablissement_id and target_etablissement_id != student_etablissement_id:
        raise PermissionDenied("Accès refusé à ce bulletin.")

    if target_etablissement_id is None and role == UserRole.SUPER_ADMIN:
        raise PermissionDenied("Selectionnez un etablissement actif.")


def _ensure_payment_access(request, payment: Payment) -> None:
    user = request.user
    role = getattr(user, "role", "")
    student = payment.fee.student if payment.fee else None

    if role == UserRole.STUDENT:
        if not student or student.user_id != user.id:
            raise PermissionDenied("Accès refusé à ce reçu de paiement.")

    if role == UserRole.PARENT:
        parent_user_id = student.parent.user_id if student and student.parent else None
        if parent_user_id != user.id:
            raise PermissionDenied("Accès refusé à ce reçu de paiement.")

    if student is not None:
        student_etablissement_id = getattr(student, "etablissement_id", None)
        if student_etablissement_id is None and getattr(student, "classroom", None) is not None:
            student_etablissement_id = getattr(student.classroom, "etablissement_id", None)
        target_etablissement_id = _effective_etablissement_id(request)
        if target_etablissement_id and student_etablissement_id and target_etablissement_id != student_etablissement_id:
            raise PermissionDenied("Accès refusé à ce reçu de paiement.")
        if target_etablissement_id is None and role == UserRole.SUPER_ADMIN:
            raise PermissionDenied("Selectionnez un etablissement actif.")


def _term_variants(term: str) -> list[str]:
    raw = str(term or "").strip().upper()
    if not raw:
        return []

    variants = {raw}
    digits = "".join(ch for ch in raw if ch.isdigit())
    if raw.isdigit():
        digits = raw

    if digits:
        variants.update(
            {
                digits,
                f"T{digits}",
                f"TRIMESTRE{digits}",
                f"TRIMESTRE {digits}",
            }
        )

    return sorted(value for value in variants if value)


def _exam_term_title_tokens(term: str) -> list[str]:
    raw = str(term or "").strip().upper()
    if not raw:
        return []

    tokens = {raw}
    digits = "".join(ch for ch in raw if ch.isdigit())
    if digits:
        tokens.update(
            {
                digits,
                f"T{digits}",
                f"TRIMESTRE{digits}",
                f"TRIMESTRE {digits}",
                f"TERM{digits}",
                f"TERM {digits}",
            }
        )

    return sorted(token for token in tokens if token)


def _term_display_label(term: str) -> str:
    raw = str(term or "").strip().upper()
    if not raw:
        return "-"

    if raw.isdigit():
        return f"T{raw}"

    digits = "".join(ch for ch in raw if ch.isdigit())
    if raw.startswith("TRIMESTRE") and digits:
        return f"T{digits}"

    return raw


def _format_cell_value(value: float | None) -> str:
    if value is None:
        return "-"
    return f"{value:.2f}"


def _format_coef_value(value: float | None) -> str:
    if value is None:
        return "-"

    text = f"{value:.2f}"
    if text.endswith(".00"):
        return text[:-3]
    if text.endswith("0"):
        return text[:-1]
    return text


def _appreciation_from_score(value: float | None) -> str:
    if value is None:
        return "-"
    if value >= 16:
        return "Tres bien"
    if value >= 14:
        return "Bien"
    if value >= 12:
        return "Assez bien"
    if value >= 10:
        return "Passable"
    return "Insuffisant"


def _build_bulletin_rows(
    *,
    subjects,
    student_note_by_subject: dict[int, float],
    exam_note_by_subject: dict[int, float],
    class_average_by_subject: dict[int, float],
    conduite_note: float,
    conduite_coef: float = 2.0,
    conduite_moyenne_classe: float | None = None,
):
    weighted_sum = 0.0
    coef_sum = 0.0
    rows = [
        {
            "index": 1,
            "subject": "Conduite",
            "coef": conduite_coef,
            "note_classe": conduite_note,
            "note_examen": None,
            "note_finale": conduite_note,
            "appreciation": _appreciation_from_score(conduite_note),
            "moyenne_classe": conduite_moyenne_classe,
            "points": round(conduite_note * conduite_coef, 2),
        }
    ]

    weighted_sum += conduite_note * conduite_coef
    coef_sum += conduite_coef

    for index, subject in enumerate(subjects, start=2):
        coef = float(subject.coefficient)
        note_classe = student_note_by_subject.get(subject.id)
        note_examen = exam_note_by_subject.get(subject.id)

        if note_classe is not None and note_examen is not None:
            note_finale = round((note_classe * coef) + (note_examen * coef), 2)
            effective_coef = coef * 2
        elif note_classe is not None:
            note_finale = round(note_classe * coef, 2)
            effective_coef = coef
        elif note_examen is not None:
            note_finale = round(note_examen * coef, 2)
            effective_coef = coef
        else:
            note_finale = None
            effective_coef = 0.0

        appreciation_score = (
            (note_finale / effective_coef)
            if (note_finale is not None and effective_coef > 0)
            else None
        )

        note_moyenne_classe = class_average_by_subject.get(subject.id)
        points = note_finale

        if note_finale is not None and effective_coef > 0:
            weighted_sum += note_finale
            coef_sum += effective_coef

        rows.append(
            {
                "index": index,
                "subject": subject.name,
                "coef": coef,
                "note_classe": note_classe,
                "note_examen": note_examen,
                "note_finale": note_finale,
                "appreciation": _appreciation_from_score(appreciation_score),
                "moyenne_classe": note_moyenne_classe,
                "points": points,
            }
        )

    average = round(weighted_sum / coef_sum, 2) if coef_sum else 0.0
    return rows, average, coef_sum


class ReportsContextView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        students = _allowed_students_queryset(request).order_by(
            "user__last_name",
            "user__first_name",
            "matricule",
        )
        payments = _allowed_payments_queryset(request).order_by("-created_at")
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
        normalized_term = normalize_term(term)
        if not normalized_term:
            return Response(
                {"detail": "Période invalide. Utilisez uniquement T1, T2 ou T3."},
                status=400,
            )

        student = get_object_or_404(
            Student.objects.select_related(
                "user",
                "classroom",
                "parent",
                "parent__user",
            ),
            id=student_id,
        )
        _ensure_student_access(request, student)

        payload = _build_bulletin_payload(
            student=student,
            academic_year_id=academic_year_id,
            normalized_term=normalized_term,
        )

        pdf = FPDF(orientation="L", format="A4")
        pdf.set_auto_page_break(auto=False)
        pdf.add_page()
        _render_bulletin_page(pdf, payload)

        safe_term = str(payload["period_label"] or term or "periode").replace("/", "-")
        return pdf_output_response(pdf, f"bulletin_{student.matricule}_{safe_term}.pdf")


def _build_bulletin_payload(*, student: Student, academic_year_id: int, normalized_term: str) -> dict:
    school = _school_identity_for_student(student)
    school_name = school["name"]
    school_short = school["short"]
    school_level = school["level"]
    school_phone = school["phone"]
    logo_path = _etablissement_logo_path(student) or _school_logo_path()

    student_name = student.user.get_full_name().strip() or student.user.username
    class_name = student.classroom.name if student.classroom else "N/A"
    period_label = normalized_term
    academic_year_name = (
        AcademicYear.objects.filter(id=academic_year_id)
        .values_list("name", flat=True)
        .first()
        or str(academic_year_id)
    )

    student_grades_qs = Grade.objects.filter(
        student_id=student.id,
        academic_year_id=academic_year_id,
        term=normalized_term,
    ).select_related("subject")

    student_note_by_subject: dict[int, float] = {}
    for grade in student_grades_qs.order_by("subject_id", "-created_at", "-id"):
        student_note_by_subject.setdefault(grade.subject_id, float(grade.value))

    classroom_id = student.classroom_id
    subject_ids: set[int] = set(student_note_by_subject.keys())
    class_average_by_subject: dict[int, float] = {}

    if classroom_id:
        class_grades_qs = Grade.objects.filter(
            classroom_id=classroom_id,
            academic_year_id=academic_year_id,
            term=normalized_term,
        )
        subject_ids.update(class_grades_qs.values_list("subject_id", flat=True))

        class_avg_rows = class_grades_qs.values("subject_id").annotate(avg_note=Avg("value"))
        class_average_by_subject = {
            int(row["subject_id"]): float(row["avg_note"])
            for row in class_avg_rows
            if row.get("avg_note") is not None
        }

        subject_ids.update(
            TeacherAssignment.objects.filter(classroom_id=classroom_id).values_list("subject_id", flat=True)
        )
        subject_ids.update(
            ExamPlanning.objects.filter(
                classroom_id=classroom_id,
                session__academic_year_id=academic_year_id,
            ).values_list("subject_id", flat=True)
        )

    student_exam_results_qs = ExamResult.objects.filter(
        student_id=student.id,
        session__academic_year_id=academic_year_id,
        session__term=normalized_term,
    )
    subject_ids.update(student_exam_results_qs.values_list("subject_id", flat=True))

    exam_note_by_subject: dict[int, float] = {}
    for exam_result in student_exam_results_qs.order_by(
        "subject_id",
        "-session__end_date",
        "-session__start_date",
        "-created_at",
        "-id",
    ):
        exam_note_by_subject.setdefault(exam_result.subject_id, float(exam_result.score))

    subjects = Subject.objects.filter(id__in=subject_ids).order_by("name", "id")

    conduite_note = float(student.conduite if student.conduite is not None else 18)
    conduite_coef = 2.0
    conduite_moyenne_classe = None
    if classroom_id:
        conduite_moyenne_classe = (
            Student.objects.filter(classroom_id=classroom_id)
            .aggregate(avg_conduite=Avg("conduite"))
            .get("avg_conduite")
        )
        if conduite_moyenne_classe is not None:
            conduite_moyenne_classe = float(conduite_moyenne_classe)

    rows, average, coef_sum = _build_bulletin_rows(
        subjects=subjects,
        student_note_by_subject=student_note_by_subject,
        exam_note_by_subject=exam_note_by_subject,
        class_average_by_subject=class_average_by_subject,
        conduite_note=conduite_note,
        conduite_coef=conduite_coef,
        conduite_moyenne_classe=conduite_moyenne_classe,
    )

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

    return {
        "logo_path": logo_path,
        "school_name": school_name,
        "school_short": school_short,
        "school_level": school_level,
        "school_phone": school_phone,
        "student_name": student_name,
        "student_matricule": student.matricule,
        "class_name": class_name,
        "academic_year_name": academic_year_name,
        "period_label": period_label,
        "rows": rows,
        "average": average,
        "coef_sum": coef_sum,
        "mention": mention,
    }


def _render_bulletin_page(pdf: FPDF, payload: dict) -> None:
    left_margin = 8
    right_margin = pdf.w - 8

    logo_path = payload["logo_path"]
    if logo_path:
        try:
            pdf.image(logo_path, x=left_margin, y=6, w=17)
        except Exception:
            pass

    title_x = 28 if logo_path else left_margin
    pdf.set_xy(title_x, 6)
    pdf.set_font("Helvetica", "B", 12.5)
    pdf.cell(0, 5.5, _pdf_text(payload["school_name"]), ln=True)

    pdf.set_x(title_x)
    pdf.set_font("Helvetica", size=8.8)
    header_line = (
        f"{payload['school_level']} | Tel: {payload['school_phone']}"
        if payload["school_phone"]
        else payload["school_level"]
    )
    pdf.cell(0, 4.4, _pdf_text(header_line), ln=True)

    pdf.set_x(title_x)
    pdf.set_font("Helvetica", "B", 8.5)
    pdf.cell(
        0,
        4.4,
        _pdf_text(f"Application: {payload['school_short']} - GESTION SCHOOL"),
        ln=True,
    )

    top_line_y = max(pdf.get_y() + 1.5, 20)
    pdf.set_draw_color(60, 60, 60)
    pdf.line(left_margin, top_line_y, right_margin, top_line_y)
    pdf.set_y(top_line_y + 1.8)

    pdf.set_font("Helvetica", "B", 13.2)
    pdf.cell(0, 6.0, _pdf_text("BULLETIN SCOLAIRE"), ln=True, align="C")

    info_label_w = 22
    info_value_w = 48
    info_h = 5.6
    info_rows = [
        ("Eleve", payload["student_name"]),
        ("Matricule", payload["student_matricule"]),
        ("Classe", payload["class_name"]),
        ("Etablissement", payload["school_name"]),
        ("Annee", payload["academic_year_name"]),
        ("Periode", payload["period_label"]),
    ]

    for index, (label, value) in enumerate(info_rows):
        if index % 2 == 0:
            pdf.set_x(left_margin)
        pdf.set_font("Helvetica", "B", 8.6)
        pdf.cell(info_label_w, info_h, _pdf_text(label), border=1)
        pdf.set_font("Helvetica", size=8.3)
        pdf.cell(info_value_w, info_h, _pdf_text(value)[:32], border=1)
        if index % 2 == 1:
            pdf.ln(info_h)

    rows = payload["rows"]
    table_columns = [
        ("N", 10, "index"),
        ("Matiere", 96, "subject"),
        ("Coef", 16, "coef"),
        ("Note classe", 27, "note_classe"),
        ("Note examen", 27, "note_examen"),
        ("Note finale", 27, "note_finale"),
        ("Appreciation", 42, "appreciation"),
    ]
    table_width = sum(column[1] for column in table_columns)
    table_x = max(left_margin, (pdf.w - table_width) / 2)

    table_y = pdf.get_y() + 2.4
    summary_start_y = 172
    header_h = 5.6
    available_for_rows = max(26.0, summary_start_y - table_y - header_h)
    row_count = max(len(rows), 1)
    row_h = max(2.5, min(5.4, available_for_rows / row_count))
    body_font_size = max(6.1, min(8.2, row_h + 2.0))
    subject_max_len = max(24, min(78, int(78 * (row_h / 5.4))))

    pdf.set_y(table_y)
    pdf.set_x(table_x)
    pdf.set_font("Helvetica", "B", 8.1)
    pdf.set_fill_color(228, 234, 244)
    for title, width, key in table_columns:
        align = "L" if key == "subject" else "C"
        pdf.cell(width, header_h, _pdf_text(title), border=1, fill=True, align=align)
    pdf.ln(header_h)

    pdf.set_font("Helvetica", size=body_font_size)
    if not rows:
        pdf.set_x(table_x)
        pdf.cell(
            table_width,
            row_h,
            _pdf_text("Aucune note disponible pour cette periode."),
            border=1,
            align="C",
        )
        pdf.ln(row_h)
    else:
        for row in rows:
            fill_row = row["index"] % 2 == 0
            if fill_row:
                pdf.set_fill_color(248, 250, 253)
            pdf.set_x(table_x)
            pdf.cell(10, row_h, _pdf_text(str(row["index"])), border=1, align="C", fill=fill_row)
            pdf.cell(96, row_h, _pdf_text(str(row["subject"])[:subject_max_len]), border=1, fill=fill_row)
            pdf.cell(16, row_h, _pdf_text(_format_coef_value(row["coef"])), border=1, align="C", fill=fill_row)
            pdf.cell(27, row_h, _pdf_text(_format_cell_value(row["note_classe"])), border=1, align="C", fill=fill_row)
            pdf.cell(27, row_h, _pdf_text(_format_cell_value(row["note_examen"])), border=1, align="C", fill=fill_row)
            pdf.cell(27, row_h, _pdf_text(_format_cell_value(row["note_finale"])), border=1, align="C", fill=fill_row)
            pdf.cell(42, row_h, _pdf_text(str(row.get("appreciation") or "-")[:20]), border=1, align="C", fill=fill_row)
            pdf.ln(row_h)

    pdf.set_y(summary_start_y)
    pdf.set_font("Helvetica", "B", 9.2)
    pdf.cell(0, 4.3, _pdf_text(f"Moyenne generale ponderee: {payload['average']:.2f}/20"), ln=True)
    pdf.cell(0, 4.3, _pdf_text(f"Total coefficients utilises: {_format_coef_value(payload['coef_sum'])}"), ln=True)
    pdf.cell(0, 4.3, _pdf_text(f"Mention: {payload['mention']}"), ln=True)

    pdf.set_font("Helvetica", size=7.2)
    pdf.set_text_color(70, 70, 70)
    pdf.multi_cell(
        0,
        3.8,
        _pdf_text(
            "Formule: Note finale = (Note classe x Coef classe) + (Note examen x Coef examen). "
            "Coef classe et coef examen sont egaux au coefficient de la matiere."
        ),
    )
    pdf.set_text_color(0, 0, 0)

    signature_y = 198
    left_sig_x1 = left_margin + 12
    left_sig_x2 = left_sig_x1 + 62
    right_sig_x2 = right_margin - 12
    right_sig_x1 = right_sig_x2 - 62

    pdf.line(left_sig_x1, signature_y, left_sig_x2, signature_y)
    pdf.line(right_sig_x1, signature_y, right_sig_x2, signature_y)
    pdf.set_y(signature_y + 1.2)
    pdf.set_font("Helvetica", size=7.8)
    pdf.set_x(left_sig_x1)
    pdf.cell(left_sig_x2 - left_sig_x1, 3.8, _pdf_text("Titulaire / Enseignant"), align="C")
    pdf.set_x(right_sig_x1)
    pdf.cell(right_sig_x2 - right_sig_x1, 3.8, _pdf_text("Direction"), align="C")


class ClassBulletinsPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, classroom_id: int, academic_year_id: int, term: str):
        normalized_term = normalize_term(term)
        if not normalized_term:
            return Response(
                {"detail": "Période invalide. Utilisez uniquement T1, T2 ou T3."},
                status=400,
            )

        if getattr(request.user, "role", "") in {UserRole.PARENT, UserRole.STUDENT}:
            raise PermissionDenied("Accès refusé aux bulletins de classe.")

        classroom = get_object_or_404(ClassRoom, id=classroom_id)
        target_etablissement_id = _effective_etablissement_id(request)
        if getattr(request.user, "role", "") == UserRole.SUPER_ADMIN and target_etablissement_id is None:
            raise PermissionDenied("Selectionnez un etablissement actif.")
        if target_etablissement_id and classroom.etablissement_id != target_etablissement_id:
            raise PermissionDenied("Accès refusé aux bulletins de cette classe.")

        students = list(
            _allowed_students_queryset(request)
            .filter(classroom_id=classroom.id, is_archived=False)
            .order_by("user__last_name", "user__first_name", "matricule")
        )

        if not students:
            return Response({"detail": "Aucun élève trouvé pour cette classe."}, status=404)

        pdf = FPDF(orientation="L", format="A4")
        pdf.set_auto_page_break(auto=False)

        for student in students:
            payload = _build_bulletin_payload(
                student=student,
                academic_year_id=academic_year_id,
                normalized_term=normalized_term,
            )
            pdf.add_page()
            _render_bulletin_page(pdf, payload)

        safe_term = str(normalized_term or term or "periode").replace("/", "-")
        class_slug = str(classroom.name or f"classe_{classroom.id}").strip().replace(" ", "_")
        return pdf_output_response(pdf, f"bulletins_{class_slug}_{safe_term}.pdf")


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
        _ensure_payment_access(request, payment)

        student = payment.fee.student
        school = _school_identity_for_student(student) if student else _school_identity()
        logo_path = (_etablissement_logo_path(student) if student else None) or _school_logo_path()

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

        payments = _allowed_payments_queryset(request).order_by("-created_at")

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
        _ensure_student_access(request, student)

        school = _school_identity_for_student(student)
        logo_path = _etablissement_logo_path(student) or _school_logo_path()

        pdf = FPDF(format=(148, 105))
        _add_student_card_page(pdf, student, school=school, logo_path=logo_path)

        return pdf_output_response(pdf, f"carte_eleve_{student.matricule}.pdf")


class ClassStudentCardsPdfView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, classroom_id: int):
        if getattr(request.user, "role", "") in {UserRole.PARENT, UserRole.STUDENT}:
            raise PermissionDenied("Accès refusé aux cartes de classe.")

        classroom = get_object_or_404(ClassRoom, id=classroom_id)
        target_etablissement_id = _effective_etablissement_id(request)
        if getattr(request.user, "role", "") == UserRole.SUPER_ADMIN and target_etablissement_id is None:
            raise PermissionDenied("Selectionnez un etablissement actif.")
        if target_etablissement_id and classroom.etablissement_id != target_etablissement_id:
            raise PermissionDenied("Accès refusé aux cartes de cette classe.")

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

        school = _school_identity_for_student(students[0])
        logo_path = _etablissement_logo_path(students[0]) or _school_logo_path()
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
