from datetime import datetime
from pathlib import Path

from django.conf import settings
from django.http import HttpResponse
from django.utils import timezone
from rest_framework import permissions, viewsets
from rest_framework.decorators import action

from apps.accounts.permissions import IsAdminOrDirector
from .models import ActivityLog
from .serializers import ActivityLogSerializer


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


class ActivityLogViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = ActivityLog.objects.select_related("user").all()
    serializer_class = ActivityLogSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrDirector]
    filterset_fields = ["user", "role", "action", "method", "module", "success", "status_code"]
    search_fields = ["action", "path", "target", "details", "user__username", "user__first_name", "user__last_name"]
    ordering_fields = ["created_at", "action", "status_code", "success", "method", "module"]
    ordering = ["-created_at"]

    def get_queryset(self):
        queryset = super().get_queryset()
        date_from = self.request.query_params.get("date_from")
        date_to = self.request.query_params.get("date_to")

        if date_from:
            try:
                parsed_from = datetime.strptime(date_from, "%Y-%m-%d").date()
                queryset = queryset.filter(created_at__date__gte=parsed_from)
            except ValueError:
                pass

        if date_to:
            try:
                parsed_to = datetime.strptime(date_to, "%Y-%m-%d").date()
                queryset = queryset.filter(created_at__date__lte=parsed_to)
            except ValueError:
                pass

        return queryset

    @action(detail=False, methods=["get"], url_path="export-excel")
    def export_excel(self, request):
        from openpyxl import Workbook
        from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
        from openpyxl.utils import get_column_letter
        queryset = self.filter_queryset(self.get_queryset())[:5000]

        workbook = Workbook()
        sheet = workbook.active
        sheet.title = "JournalActivites"

        school_name = getattr(settings, "SCHOOL_NAME", "LYCEE TECHNIQUE OUMAR BAH")
        school_short = getattr(settings, "SCHOOL_SHORT", "LTOB")
        school_level = getattr(settings, "SCHOOL_LEVEL", "1er etage")
        school_phone = getattr(settings, "SCHOOL_PHONE", "")
        logo_path = _school_logo_path()

        columns = [
            "Date",
            "Utilisateur",
            "Role",
            "Action",
            "Methode",
            "Module",
            "Path",
            "Status HTTP",
            "Succes",
            "IP",
        ]
        last_col = len(columns)
        last_col_letter = get_column_letter(last_col)

        sheet.merge_cells(f"A1:{last_col_letter}1")
        sheet.merge_cells(f"A2:{last_col_letter}2")
        sheet.merge_cells(f"A3:{last_col_letter}3")

        sheet["A1"] = school_name
        sheet["A2"] = f"{school_level} | Tel: {school_phone}" if school_phone else school_level
        sheet["A3"] = f"JOURNAL DES ACTIVITES - {school_short}"

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

        row_index = header_row + 1
        success_total = 0
        failure_total = 0

        for row in queryset:
            user_display = "Anonyme"
            if row.user:
                full_name = row.user.get_full_name().strip()
                user_display = full_name or row.user.username

            if row.success:
                success_total += 1
            else:
                failure_total += 1

            values = [
                row.created_at.strftime("%d/%m/%Y %H:%M:%S"),
                user_display,
                row.role,
                row.action,
                row.method,
                row.module,
                row.path,
                row.status_code,
                "Oui" if row.success else "Non",
                row.ip_address,
            ]

            for col_index, value in enumerate(values, start=1):
                cell = sheet.cell(row=row_index, column=col_index, value=value)
                cell.border = thin_border
                if col_index in (8, 9):
                    cell.alignment = Alignment(horizontal="center", vertical="center")
                else:
                    cell.alignment = Alignment(horizontal="left", vertical="center")
            row_index += 1

        if row_index == header_row + 1:
            sheet.merge_cells(start_row=row_index, start_column=1, end_row=row_index, end_column=last_col)
            empty_cell = sheet.cell(row=row_index, column=1, value="Aucune activite disponible.")
            empty_cell.alignment = Alignment(horizontal="center", vertical="center")
            empty_cell.font = Font(italic=True, color="6B7280")
            empty_cell.border = thin_border
            row_index += 1

        summary_row = row_index + 1
        sheet.merge_cells(start_row=summary_row, start_column=1, end_row=summary_row, end_column=5)
        summary_label = sheet.cell(row=summary_row, column=1, value="SYNTHESE")
        summary_label.font = Font(bold=True, color="1F3B63")
        summary_label.fill = PatternFill(fill_type="solid", fgColor="E8EEF7")
        summary_label.alignment = Alignment(horizontal="center", vertical="center")
        summary_label.border = thin_border

        success_cell = sheet.cell(row=summary_row, column=6, value=f"Succes: {success_total}")
        success_cell.font = Font(bold=True, color="0F5132")
        success_cell.fill = PatternFill(fill_type="solid", fgColor="D1E7DD")
        success_cell.alignment = Alignment(horizontal="center", vertical="center")
        success_cell.border = thin_border

        failure_cell = sheet.cell(row=summary_row, column=7, value=f"Echecs: {failure_total}")
        failure_cell.font = Font(bold=True, color="842029")
        failure_cell.fill = PatternFill(fill_type="solid", fgColor="F8D7DA")
        failure_cell.alignment = Alignment(horizontal="center", vertical="center")
        failure_cell.border = thin_border

        total_cell = sheet.cell(row=summary_row, column=8, value=f"Total: {success_total + failure_total}")
        total_cell.font = Font(bold=True, color="1F3B63")
        total_cell.fill = PatternFill(fill_type="solid", fgColor="E8EEF7")
        total_cell.alignment = Alignment(horizontal="center", vertical="center")
        total_cell.border = thin_border

        for col_index in range(9, last_col + 1):
            empty = sheet.cell(row=summary_row, column=col_index, value="")
            empty.fill = PatternFill(fill_type="solid", fgColor="E8EEF7")
            empty.border = thin_border

        generated_row = summary_row + 2
        generated_by = request.user.get_full_name().strip() or request.user.username
        generated_at = timezone.localtime().strftime("%d/%m/%Y %H:%M")
        sheet.merge_cells(start_row=generated_row, start_column=1, end_row=generated_row, end_column=last_col)
        generated_cell = sheet.cell(
            row=generated_row,
            column=1,
            value=f"Genere le {generated_at} par {generated_by}",
        )
        generated_cell.font = Font(italic=True, color="6B7280")
        generated_cell.alignment = Alignment(horizontal="left", vertical="center")

        widths = [22, 24, 14, 28, 12, 14, 40, 12, 10, 16]
        for index, width in enumerate(widths, start=1):
            sheet.column_dimensions[get_column_letter(index)].width = width

        sheet.freeze_panes = "A6"

        response = HttpResponse(content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        response["Content-Disposition"] = 'attachment; filename="activity_logs.xlsx"'
        workbook.save(response)
        return response

    @action(detail=False, methods=["get"], url_path="export-pdf")
    def export_pdf(self, request):
        from fpdf import FPDF
        queryset = self.filter_queryset(self.get_queryset())[:1000]

        school_name = getattr(settings, "SCHOOL_NAME", "LYCEE TECHNIQUE OUMAR BAH")
        school_short = getattr(settings, "SCHOOL_SHORT", "LTOB")
        school_level = getattr(settings, "SCHOOL_LEVEL", "1er etage")
        school_phone = getattr(settings, "SCHOOL_PHONE", "")
        logo_path = _school_logo_path()

        pdf = FPDF(orientation="L")
        pdf.add_page()
        pdf.set_auto_page_break(auto=True, margin=10)

        if logo_path:
            try:
                pdf.image(logo_path, x=10, y=8, w=18)
            except Exception:
                pass

        pdf.set_xy(32 if logo_path else 10, 8)
        pdf.set_font("Helvetica", "B", 12)
        pdf.cell(0, 6, _pdf_text(school_name), ln=True)

        pdf.set_x(32 if logo_path else 10)
        pdf.set_font("Helvetica", size=9)
        header_line = f"{school_level} | Tel: {school_phone}" if school_phone else school_level
        pdf.cell(0, 5, _pdf_text(header_line), ln=True)

        pdf.set_x(32 if logo_path else 10)
        pdf.set_font("Helvetica", "B", 9)
        pdf.cell(0, 5, _pdf_text(f"Application: {school_short} - GESTION SCHOOL"), ln=True)

        top_line_y = max(pdf.get_y() + 2, 26)
        pdf.set_draw_color(60, 60, 60)
        pdf.line(10, top_line_y, 287, top_line_y)
        pdf.set_y(top_line_y + 3)

        pdf.set_font("Helvetica", "B", 14)
        pdf.cell(0, 8, _pdf_text("JOURNAL DES ACTIVITES"), ln=True, align="C")
        pdf.ln(1)
        pdf.set_font("Helvetica", size=8)

        headers = ["Date", "Utilisateur", "Role", "Action", "Method", "Module", "Status", "IP"]
        widths = [34, 34, 20, 70, 18, 30, 20, 30]

        pdf.set_fill_color(230, 235, 245)
        pdf.set_font("Helvetica", "B", 8)
        for idx, header in enumerate(headers):
            pdf.cell(widths[idx], 7, _pdf_text(header), border=1, fill=True)
        pdf.ln()

        pdf.set_font("Helvetica", size=8)

        for row in queryset:
            user_display = "Anonyme"
            if row.user:
                full_name = row.user.get_full_name().strip()
                user_display = full_name or row.user.username

            values = [
                row.created_at.strftime("%d/%m/%Y %H:%M"),
                user_display[:30],
                row.role[:18],
                row.action[:58],
                row.method,
                row.module[:28],
                str(row.status_code),
                row.ip_address[:20],
            ]

            for idx, value in enumerate(values):
                pdf.cell(widths[idx], 7, _pdf_text(value), border=1)
            pdf.ln()

        pdf.ln(2)
        pdf.set_font("Helvetica", size=8)
        generated_by = request.user.get_full_name().strip() or request.user.username
        generated_at = timezone.localtime().strftime("%d/%m/%Y %H:%M")
        pdf.cell(0, 5, _pdf_text(f"Genere le {generated_at} par {generated_by}"), ln=True)

        data = bytes(pdf.output())
        response = HttpResponse(data, content_type="application/pdf")
        response["Content-Disposition"] = 'attachment; filename="activity_logs.pdf"'
        return response
