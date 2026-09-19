from datetime import datetime, timedelta
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import zipfile
from pathlib import Path

from django.conf import settings
from django.apps import apps
from django.core import serializers
from django.core.files.uploadedfile import UploadedFile
from django.db import close_old_connections, connection, transaction
from django.db import models
from django.db.models import Q
from django.db.models.deletion import ProtectedError
from django.http import FileResponse, HttpResponse
from django.utils import timezone
from rest_framework import permissions, status, viewsets
from rest_framework.permissions import AllowAny
from rest_framework.views import APIView
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from apps.accounts.permissions import HasModuleAccess
from apps.common.pagination import AuditLogPagination
from .sauvegarde import fichiers_a_archiver, poids_total, volume_de_la_bibliotheque
from .models import ActivityLog, BackupArchive, PersonnalisationPlateforme
from .serializers import ActivityLogSerializer, BackupArchiveSerializer, PersonnalisationSerializer


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
    access_module = "activity_logs"
    queryset = ActivityLog.objects.select_related("user").all()
    serializer_class = ActivityLogSerializer
    pagination_class = AuditLogPagination
    permission_classes = [permissions.IsAuthenticated, HasModuleAccess]
    filterset_fields = ["user", "etablissement", "role", "action", "method", "module", "success", "status_code"]
    search_fields = [
        "action",
        "path",
        "target",
        "details",
        "user__username",
        "user__first_name",
        "user__last_name",
        "etablissement__name",
    ]
    ordering_fields = ["created_at", "action", "status_code", "success", "method", "module"]
    # "-id" en second: sur des lignes creees dans la meme seconde,
    # "-created_at" seul laisse l_ordre indefini et une meme ligne peut
    # apparaitre sur deux pages, ou sur aucune.
    ordering = ["-created_at", "-id"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        from apps.school.models import Etablissement

        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def get_queryset(self):
        queryset = super().get_queryset()
        user = self.request.user
        role = getattr(user, "role", "")

        requested_etablissement = self._requested_etablissement()
        if requested_etablissement is not None:
            queryset = queryset.filter(
                Q(etablissement=requested_etablissement)
                | Q(etablissement__isnull=True, user__etablissement=requested_etablissement)
            )
        elif self._has_requested_scope():
            return queryset.none()
        elif role != "super_admin":
            user_etablissement = getattr(user, "etablissement", None)
            if user_etablissement is None:
                return queryset.none()
            queryset = queryset.filter(
                Q(etablissement=user_etablissement)
                | Q(etablissement__isnull=True, user__etablissement=user_etablissement)
            )

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


class BackupArchiveViewSet(viewsets.ModelViewSet):
    access_module = "backup_restore"
    queryset = BackupArchive.objects.select_related("created_by", "restored_by", "etablissement").all()
    serializer_class = BackupArchiveSerializer
    permission_classes = [permissions.IsAuthenticated, HasModuleAccess]
    parser_classes = [JSONParser, MultiPartParser, FormParser]
    # "delete" ouvert pour le menage: une archive de plusieurs centaines de
    # mega-octets par semaine remplit le disque, et rien ne permettait d'en
    # retirer une autrement qu'en passant sur le serveur.
    http_method_names = ["get", "post", "delete"]
    filterset_fields = ["scope", "status", "etablissement", "created_by", "restored_by"]
    search_fields = ["filename", "notes", "etablissement__name", "created_by__username"]
    ordering_fields = ["created_at", "status", "scope", "file_size_bytes"]
    # "-id" en second: sur des lignes creees dans la meme seconde,
    # "-created_at" seul laisse l_ordre indefini et une meme ligne peut
    # apparaitre sur deux pages, ou sur aucune.
    ordering = ["-created_at", "-id"]

    def _is_super_admin(self):
        return getattr(self.request.user, "role", "") == "super_admin"

    @staticmethod
    def _drapeau(valeur, *, defaut: bool) -> bool:
        """Lit un booleen envoye en JSON comme en formulaire multipart.

        Le formulaire n'a pas de type: il transmet « false », « 0 » ou
        « no » sous forme de chaine, et toute chaine non vide est vraie en
        Python -- une case decochee arrivait donc cochee.
        """
        if valeur is None:
            return defaut
        if isinstance(valeur, bool):
            return valeur
        texte = str(valeur).strip().lower()
        if texte in {"0", "false", "no", "non", ""}:
            return False
        if texte in {"1", "true", "yes", "oui"}:
            return True
        return defaut

    def _require_super_admin_restore(self):
        if not self._is_super_admin():
            return Response(
                {"detail": "Seul un super admin peut lancer une restauration."},
                status=status.HTTP_403_FORBIDDEN,
            )
        return None

    def _resolve_etablissement(self):
        from apps.school.models import Etablissement

        etablissement_id = self.request.data.get("etablissement") or self.request.data.get("etablissement_id")
        if etablissement_id in (None, ""):
            return getattr(self.request.user, "etablissement", None)
        try:
            parsed = int(etablissement_id)
        except (TypeError, ValueError):
            return None
        return Etablissement.objects.filter(id=parsed).first()

    def _backups_root(self) -> Path:
        root = Path(settings.BACKUP_ROOT) / "archives"
        root.mkdir(parents=True, exist_ok=True)
        return root

    def _sha256_file(self, file_path: Path) -> str:
        digest = hashlib.sha256()
        with file_path.open("rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()

    # Combien de lignes on serialise d'un coup. Assez pour que le cout par
    # lot reste negligeable, assez peu pour qu'un lot tienne dans la memoire
    # d'un conteneur a 512 Mo -- meme sur une table large.
    TAILLE_DE_LOT = 500

    # Des tables d'etat instantane, sans rien a proteger. Elles ne partent
    # pas dans une archive et une restauration n'y touche pas.
    #
    # La presence du chat dit qui est connecte a la seconde meme. La
    # restaurer depuis une archive d'hier n'aurait aucun sens -- et surtout,
    # chaque utilisateur connecte la met a jour toutes les dix secondes. Tant
    # que la restauration la tenait verrouillee dans sa transaction, ces
    # mises a jour s'empilaient: trente-trois requetes bloquees constatees
    # dans Postgres, soit toute l'application gelee. En production, avec
    # deux workers seulement, cela les sature, le controle de sante echoue,
    # Render redemarre le conteneur -- et tue la restauration.
    TABLES_EPHEMERES = frozenset({"chat.chatpresence"})

    # L'historique des sauvegardes ne voyage pas non plus. Il decrit les
    # archives, il n'est pas une donnee de l'ecole: l'emporter dans une
    # archive puis le restaurer ecrasait l'historique actuel avec celui du
    # jour de la sauvegarde. Une ligne recevait alors le nom de fichier
    # d'une autre, et le vrai fichier restait sur le disque sans rien qui le
    # reference -- neuf archives orphelines constatees en local.
    TABLES_HORS_ARCHIVE = TABLES_EPHEMERES | frozenset({"common.backuparchive"})

    def _est_ephemere(self, model) -> bool:
        return model._meta.label_lower in self.TABLES_HORS_ARCHIVE

    def _modeles_a_sauvegarder(self):
        """Les tables qu'une archive emporte, dans l'ordre de leurs dependances.

        Trois tables techniques de Django restent dehors: elles se
        reconstituent seules et n'ont aucune valeur metier.
        """
        for model in apps.get_models():
            opts = model._meta
            if opts.proxy or not opts.managed:
                continue
            if opts.app_label in {"contenttypes", "sessions", "admin"}:
                continue
            if self._est_ephemere(model):
                continue
            yield model

    def _ecrire_les_donnees(self, flux, querysets) -> int:
        """Ecrit un tableau JSON dans `flux`, lot par lot. Rend le nombre de lignes.

        La serialisation tenait la base entiere en memoire quatre fois: une
        chaine JSON par table, les memes donnees reconverties en objets
        Python, la concatenation de tout cela en une seule chaine, puis cette
        chaine gardee pendant la compression. Sur un conteneur a 512 Mo, le
        systeme tuait le processus -- et comme il ecrivait dans le vide,
        l'ecran restait fige sur « Lecture de la base ».

        Ici rien ne depasse un lot: on ecrit au fil de l'eau, et la memoire
        ne depend plus de la taille de la base.
        """
        flux.write("[")
        premier = True
        total = 0

        for queryset in querysets:
            lot = []
            for objet in queryset.iterator(chunk_size=self.TAILLE_DE_LOT):
                lot.append(objet)
                if len(lot) < self.TAILLE_DE_LOT:
                    continue
                premier = self._ecrire_un_lot(flux, lot, premier)
                total += len(lot)
                lot = []
            if lot:
                premier = self._ecrire_un_lot(flux, lot, premier)
                total += len(lot)

        flux.write("]")
        return total

    def _ecrire_un_lot(self, flux, lot, premier: bool) -> bool:
        """Ajoute un lot au tableau deja ouvert, sans ses crochets."""
        fragment = serializers.serialize("json", lot, ensure_ascii=False)
        # `serialize` rend un tableau complet: on retire ses crochets pour
        # coudre les lots bout a bout dans un seul tableau.
        interieur = fragment.strip()[1:-1].strip()
        if not interieur:
            return premier
        if not premier:
            flux.write(",")
        flux.write(interieur)
        return False

    def _serialize_global_vers(self, chemin: Path, backup=None) -> int:
        """Ecrit toute la base dans `chemin`, table par table."""
        modeles = list(self._modeles_a_sauvegarder())
        total = 0
        with chemin.open("w", encoding="utf-8") as flux:
            flux.write("[")
            premier = True
            for rang, model in enumerate(modeles, start=1):
                if backup is not None:
                    # Dans les champs de la sauvegarde, pas de la
                    # restauration: l'ecran et la detection de blocage
                    # distinguent les deux gestes a la phase de restauration.
                    # Ecrite ici, elle faisait passer chaque sauvegarde pour
                    # une restauration.
                    self._set_build_progress(
                        backup,
                        phase=f"Lecture : {model._meta.label} ({rang}/{len(modeles)})",
                    )
                lot = []
                for objet in model.objects.all().order_by("pk").iterator(
                    chunk_size=self.TAILLE_DE_LOT
                ):
                    lot.append(objet)
                    if len(lot) < self.TAILLE_DE_LOT:
                        continue
                    premier = self._ecrire_un_lot(flux, lot, premier)
                    total += len(lot)
                    lot = []
                if lot:
                    premier = self._ecrire_un_lot(flux, lot, premier)
                    total += len(lot)
            flux.write("]")
        return total

    def _serialize_etablissement(self, etablissement):
        """Les requetes a sauvegarder pour un etablissement, sans les executer.

        Elle rendait une chaine JSON portant toute la selection. Elle rend
        desormais les requetes elles-memes: l'appelant les parcourt en flux,
        et la memoire cesse de dependre de la taille de l'ecole.
        """
        from apps.accounts.models import User

        scoped_user_ids = set(
            User.objects.filter(etablissement=etablissement).values_list("pk", flat=True)
        )

        # Include users referenced by establishment-scoped rows even if those
        # users are not attached to the same establishment.
        referenced_user_ids = set()
        serialized_payload = []
        for model in apps.get_models():
            opts = model._meta
            if opts.proxy or not opts.managed:
                continue
            if opts.app_label in {"contenttypes", "sessions", "admin"}:
                continue

            field_names = {field.name for field in opts.fields}
            queryset = None

            if self._est_ephemere(model):
                continue

            if model.__name__ == "Etablissement":
                queryset = model.objects.filter(pk=etablissement.pk)
            elif opts.app_label == "accounts" and model.__name__ == "User":
                queryset = model.objects.filter(Q(etablissement=etablissement) | Q(pk__in=scoped_user_ids))
            elif "etablissement" in field_names:
                queryset = model.objects.filter(etablissement=etablissement)

                user_field = next(
                    (
                        field
                        for field in opts.fields
                        if field.name == "user"
                        and isinstance(field, (models.ForeignKey, models.OneToOneField))
                        and getattr(getattr(field, "remote_field", None), "model", None) is User
                    ),
                    None,
                )
                if user_field is not None:
                    referenced_user_ids.update(
                        queryset.exclude(user_id__isnull=True).values_list("user_id", flat=True)
                    )

            if queryset is None:
                continue

            # `exists()` retire: c'etait une requete de plus par table, et le
            # parcours en flux ne coute rien sur une table vide.
            serialized_payload.append(queryset.order_by("pk"))

        missing_referenced_user_ids = referenced_user_ids - scoped_user_ids
        if missing_referenced_user_ids:
            serialized_payload.append(
                User.objects.filter(pk__in=missing_referenced_user_ids).order_by("pk")
            )

        return serialized_payload

    def _serialize_etablissement_vers(self, etablissement, chemin: Path) -> int:
        """Ecrit les donnees d'un etablissement dans `chemin`, lot par lot."""
        with chemin.open("w", encoding="utf-8") as flux:
            return self._ecrire_les_donnees(
                flux, self._serialize_etablissement(etablissement)
            )

    # L'ecriture des medias occupe la tranche 5 %-95 % de la barre: avant, on
    # lit la base; apres, on calcule l'empreinte du fichier. Annoncer 100 %
    # des le dernier fichier ecrit laisserait l'ecran fige sur « termine »
    # pendant tout le hachage d'une archive de plusieurs giga-octets.
    _PART_MEDIAS = (5, 95)
    # Un signal par seconde au plus. Sur des milliers de fichiers, ecrire
    # l'avancement a chaque entree couterait plus de requetes que
    # l'archivage lui-meme.
    _INTERVALLE_DE_SIGNAL = 1.0

    def _set_build_progress(
        self,
        backup_ref,
        *,
        progress=None,
        phase=None,
        bytes_done=None,
        bytes_total=None,
    ):
        """Ecrit l'avancement sans relire ni reecrire le reste de la ligne.

        `update()` plutot que `save()`: le processus qui archive ne doit pas
        reposer par-dessus des champs qu'un autre aurait modifies entre
        temps, et l'objet en memoire n'a pas a rester a jour pour cela.
        """
        backup_id = backup_ref.id if isinstance(backup_ref, BackupArchive) else int(backup_ref)
        update_kwargs = {}

        if progress is not None:
            update_kwargs["build_progress"] = max(0, min(100, int(progress)))
        if phase is not None:
            update_kwargs["build_phase"] = str(phase or "")[:120]
        if bytes_done is not None:
            update_kwargs["bytes_done"] = max(0, int(bytes_done))
        if bytes_total is not None:
            update_kwargs["bytes_total"] = max(0, int(bytes_total))

        if not update_kwargs:
            return

        update_kwargs["updated_at"] = timezone.now()
        self._ecrire_l_avancement(backup_id, update_kwargs)

    def _pourcentage_des_medias(self, ecrits: int, total: int) -> int:
        """Position dans la barre pour `ecrits` octets deja archives."""
        debut, fin = self._PART_MEDIAS
        if total <= 0:
            return fin
        part = min(1.0, max(0.0, ecrits / total))
        return int(debut + (fin - debut) * part)

    def _mark_build_failed(self, backup_id: int, exc: Exception):
        """Une sauvegarde interrompue doit se voir, et dire pourquoi.

        Sans cela, le processus detache mourait en silence et la ligne
        restait « en cours » indefiniment: l'ecran affichait une barre qui
        n'avancait plus, sans jamais rien expliquer.
        """
        try:
            self._fichier_d_avancement(backup_id).unlink(missing_ok=True)
        except OSError:
            pass
        try:
            BackupArchive.objects.filter(pk=backup_id).update(
                status=BackupArchive.Status.FAILED,
                build_phase="Echec",
                restore_log=f"{exc}\n\n{traceback.format_exc()}",
                updated_at=timezone.now(),
            )
        except Exception:
            pass

    def _build_archive(self, backup: BackupArchive) -> BackupArchive:
        stamp = timezone.localtime().strftime("%Y%m%d_%H%M%S")
        suffix = "global" if backup.scope == BackupArchive.Scope.GLOBAL else f"etab_{backup.etablissement_id}"
        backup_name = f"backup_{suffix}_{stamp}.zip"
        backup_dir = self._backups_root()
        archive_path = backup_dir / backup_name

        backup.status = BackupArchive.Status.RUNNING
        backup.filename = backup_name
        backup.file_path = str(archive_path)
        backup.build_started_at = timezone.now()
        backup.build_phase = "Lecture de la base"
        backup.build_progress = 1
        backup.bytes_done = 0
        backup.bytes_total = 0
        backup.save(
            update_fields=[
                "status",
                "filename",
                "file_path",
                "build_started_at",
                "build_phase",
                "build_progress",
                "bytes_done",
                "bytes_total",
                "updated_at",
            ]
        )

        # Les donnees partent dans un fichier temporaire, et non dans une
        # chaine: la base entiere tenait en memoire quatre fois, ce que les
        # 512 Mo du conteneur ne supportent pas. Le systeme tuait alors le
        # processus, et l'ecran restait fige sur « Lecture de la base ».
        dossier_temporaire = tempfile.TemporaryDirectory(prefix="backup_data_")
        donnees = Path(dossier_temporaire.name) / "data.json"
        try:
            if backup.scope == BackupArchive.Scope.ETABLISSEMENT:
                self._serialize_etablissement_vers(backup.etablissement, donnees)
            else:
                self._serialize_global_vers(donnees, backup=backup)
            octets_des_donnees = donnees.stat().st_size

            # Le listage precede l'ecriture pour connaitre le volume total: sans
            # denominateur, il n'y a ni pourcentage ni reste a annoncer.
            fichiers = []
            if backup.include_media:
                fichiers = fichiers_a_archiver(
                    settings.MEDIA_ROOT,
                    avec_bibliotheque=backup.include_library_documents,
                )
            octets_des_medias = poids_total(fichiers)
            octets_a_ecrire = octets_des_donnees + octets_des_medias

            manifest = {
                "version": 1,
                "kind": backup.kind,
                "scope": backup.scope,
                "created_at": timezone.localtime().isoformat(),
                "created_by": getattr(backup.created_by, "username", ""),
                "etablissement_id": backup.etablissement_id,
                "include_media": bool(backup.include_media),
                "include_library_documents": bool(backup.include_library_documents),
                "media_files": len(fichiers),
                "bytes_source": octets_a_ecrire,
            }

            debut, _ = self._PART_MEDIAS
            self._set_build_progress(
                backup,
                progress=debut,
                phase="Ecriture des donnees",
                bytes_done=0,
                bytes_total=octets_a_ecrire,
            )

            with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
                # `write` et non `writestr`: la seconde relit tout le contenu en
                # memoire avant de le compresser, ce qu'on vient precisement
                # d'eviter en ecrivant les donnees dans un fichier.
                zf.write(donnees, arcname="data.json")

                ecrits = octets_des_donnees
                total_fichiers = len(fichiers)
                dernier_signal = time.monotonic()
                self._set_build_progress(
                    backup,
                    bytes_done=ecrits,
                    progress=self._pourcentage_des_medias(ecrits, octets_a_ecrire),
                    phase=(
                        f"Medias (0/{total_fichiers})" if total_fichiers else "Donnees archivees"
                    ),
                )

                for rang, fichier in enumerate(fichiers, start=1):
                    try:
                        zf.write(fichier.chemin, arcname=fichier.nom_dans_l_archive)
                    except OSError:
                        # Un fichier efface ou illisible entre le listage et
                        # l'ecriture ne doit pas faire perdre toute l'archive.
                        continue

                    ecrits += fichier.octets
                    maintenant = time.monotonic()
                    if maintenant - dernier_signal < self._INTERVALLE_DE_SIGNAL and rang != total_fichiers:
                        continue
                    dernier_signal = maintenant
                    self._set_build_progress(
                        backup,
                        bytes_done=ecrits,
                        progress=self._pourcentage_des_medias(ecrits, octets_a_ecrire),
                        phase=f"Medias ({rang}/{total_fichiers})",
                    )

            self._set_build_progress(
                backup,
                progress=self._PART_MEDIAS[1] + 2,
                phase="Empreinte de controle",
                bytes_done=octets_a_ecrire,
                bytes_total=octets_a_ecrire,
            )

        finally:
            dossier_temporaire.cleanup()

        backup.file_size_bytes = archive_path.stat().st_size
        backup.sha256 = self._sha256_file(archive_path)
        backup.manifest = manifest
        backup.status = BackupArchive.Status.COMPLETED
        backup.build_phase = "Terminee"
        backup.build_progress = 100
        backup.bytes_done = octets_a_ecrire
        backup.bytes_total = octets_a_ecrire
        backup.save(
            update_fields=[
                "file_size_bytes",
                "sha256",
                "manifest",
                "status",
                "build_phase",
                "build_progress",
                "bytes_done",
                "bytes_total",
                "updated_at",
            ]
        )
        return backup

    def _ecrire_l_avancement(self, backup_id: int, champs: dict) -> None:
        """Rend l'avancement visible, sans jamais attendre la base.

        Deux essais ont precede celui-ci, et chacun a sa lecon.

        Ecrit dans la transaction de la restauration, l'avancement restait
        invisible: l'ecran lisait sur sa propre connexion la derniere valeur
        commitee -- 28 -- pendant toute la duree du travail.

        Ecrit sur une seconde connexion, il se bloquait: le nettoyage met a
        NULL l'auteur des archives en supprimant les comptes, ce qui verrouille
        la ligne meme dont on voulait ecrire l'avancement. La seconde
        connexion attendait ce verrou, la restauration attendait en Python
        que l'ecriture revienne -- chacune attendant l'autre, pour toujours.
        Constate dans Postgres, restauration figee a 40 %.

        Pendant la transaction, l'avancement part donc dans un fichier: le
        processus detache et l'API partagent le disque du conteneur, et un
        fichier ne prend aucun verrou en base. Hors transaction, il reprend
        sa place dans la ligne.
        """
        if transaction.get_connection().in_atomic_block:
            self._ecrire_l_avancement_sur_disque(backup_id, champs)
            return

        BackupArchive.objects.filter(pk=backup_id).update(**champs)
        # Revenu en base: le fichier ne dirait plus rien de plus juste.
        try:
            self._fichier_d_avancement(backup_id).unlink(missing_ok=True)
        except OSError:
            pass

    def _est_silencieuse(self, archive) -> bool:
        """Vrai si l'operation ne donne plus signe de vie depuis trop longtemps.

        Le dernier signe est le plus recent des deux: la ligne en base, ou
        le fichier d'avancement que la restauration ecrit pendant sa
        transaction. Ne regarder que la base ferait passer pour morte une
        restauration saine -- et la rendrait supprimable pendant qu'elle lit
        encore son archive.
        """
        limite = timezone.now() - self.SILENCE_AVANT_ABANDON
        if archive.updated_at and archive.updated_at >= limite:
            return False
        try:
            mtime = self._fichier_d_avancement(archive.id).stat().st_mtime
        except OSError:
            return True
        dernier = datetime.fromtimestamp(mtime, tz=timezone.get_current_timezone())
        # Un fichier plus ancien que la ligne appartient a une archive
        # precedente qui portait le meme numero -- une base restauree
        # recommence ses numeros. Le prendre pour un signe de vie ferait
        # passer une operation morte pour vivante, indefiniment.
        if archive.created_at and dernier < archive.created_at:
            return True
        return dernier < limite

    @staticmethod
    def _fichier_d_avancement(backup_id: int) -> Path:
        dossier = Path(settings.BACKUP_ROOT) / "journaux"
        dossier.mkdir(parents=True, exist_ok=True)
        return dossier / f"avancement_{backup_id}.json"

    def _ecrire_l_avancement_sur_disque(self, backup_id: int, champs: dict) -> None:
        donnees = {
            cle: (valeur.isoformat() if hasattr(valeur, "isoformat") else valeur)
            for cle, valeur in champs.items()
        }
        fichier = self._fichier_d_avancement(backup_id)
        provisoire = fichier.with_suffix(".tmp")
        try:
            provisoire.write_text(json.dumps(donnees), encoding="utf-8")
            # Remplacement atomique: l'API ne lit jamais un fichier a moitie
            # ecrit, qui la ferait echouer au decodage.
            os.replace(provisoire, fichier)
        except OSError:
            pass

    @classmethod
    def avancement_sur_disque(cls, backup_id: int) -> dict:
        """L'avancement que le processus a ecrit hors base, s'il y en a un."""
        try:
            return json.loads(
                cls._fichier_d_avancement(backup_id).read_text(encoding="utf-8")
            )
        except (OSError, ValueError):
            return {}

    def _set_restore_progress(self, backup_ref, *, progress=None, phase=None):
        backup_id = backup_ref.id if isinstance(backup_ref, BackupArchive) else int(backup_ref)
        update_kwargs = {}

        if progress is not None:
            update_kwargs["restore_progress"] = max(0, min(100, int(progress)))

        if phase is not None:
            update_kwargs["restore_phase"] = str(phase or "")[:120]

        if not update_kwargs:
            return

        update_kwargs["updated_at"] = timezone.now()
        self._ecrire_l_avancement(backup_id, update_kwargs)

    def _mark_restore_failed(self, backup_id: int, exc: Exception):
        try:
            self._fichier_d_avancement(backup_id).unlink(missing_ok=True)
        except OSError:
            pass
        try:
            backup = BackupArchive.objects.get(pk=backup_id)
            backup.status = BackupArchive.Status.FAILED
            backup.restore_phase = "Echec"
            backup.restore_progress = max(int(backup.restore_progress or 0), 100)
            backup.restore_log = f"{exc}\n\n{traceback.format_exc()}"
            backup.save(
                update_fields=[
                    "status",
                    "restore_phase",
                    "restore_progress",
                    "restore_log",
                    "updated_at",
                ]
            )
        except Exception:
            pass

    def _refuser_si_une_operation_tourne(self):
        """Une seule sauvegarde ou restauration a la fois.

        Rien ne l'empechait. Chaque operation charge des tables entieres en
        memoire, et le conteneur n'a que 512 Mo: deux a la fois, c'est le
        systeme qui tue l'une des deux -- ou les deux. Une restauration lancee
        pendant une sauvegarde pouvait aussi archiver une base a moitie
        videe.

        Une operation silencieuse depuis trop longtemps ne compte pas: elle
        est morte, et la tenir pour active bloquerait tout indefiniment.
        """
        for archive in BackupArchive.objects.filter(
            status__in=[BackupArchive.Status.RUNNING, BackupArchive.Status.PENDING]
        ):
            if not self._est_silencieuse(archive):
                geste = (
                    "une restauration"
                    if (archive.restore_phase or "").strip()
                    else "une sauvegarde"
                )
                raise ValidationError(
                    {
                        "detail": (
                            f"{geste[0].upper()}{geste[1:]} est déjà en cours "
                            f"({archive.filename or f'archive n° {archive.id}'}). "
                            "Attendez qu'elle se termine: deux opérations à la "
                            "fois épuiseraient la mémoire du serveur."
                        )
                    }
                )

    def _verifier_la_portee(self, archive_path: Path, scope: str, etablissement_id) -> None:
        """Refuse de restaurer une archive dans une portee qui n'est pas la sienne.

        La portee venait du menu deroulant et l'archive n'etait jamais
        consultee. Choisir « Restauration globale plateforme » avec l'archive
        d'un seul etablissement effacait donc toutes les autres ecoles, puis
        n'en rechargeait qu'une. Et l'archive de l'ecole A restauree « dans »
        l'ecole B videait B, puis ecrasait A avec ses anciennes donnees.

        Le manifeste de l'archive dit ce qu'elle contient: c'est lui qui
        tranche, pas le choix fait dans l'ecran.
        """
        try:
            with zipfile.ZipFile(archive_path, "r") as zf:
                noms = set(zf.namelist())
                if "data.json" not in noms:
                    raise ValidationError(
                        {"file": "Archive invalide: elle ne contient pas de données."}
                    )
                if "manifest.json" not in noms:
                    raise ValidationError(
                        {
                            "file": (
                                "Archive sans manifeste: impossible de savoir ce "
                                "qu'elle contient, elle n'est donc pas restaurée."
                            )
                        }
                    )
                manifeste = json.loads(zf.read("manifest.json").decode("utf-8"))
        except zipfile.BadZipFile:
            raise ValidationError({"file": "Le fichier envoyé n'est pas une archive ZIP."})
        except (ValueError, UnicodeDecodeError):
            raise ValidationError({"file": "Manifeste d'archive illisible."})

        portee_archive = str(manifeste.get("scope") or "").strip()
        if portee_archive != scope:
            libelles = {
                BackupArchive.Scope.GLOBAL: "toute la plateforme",
                BackupArchive.Scope.ETABLISSEMENT: "un seul établissement",
            }
            raise ValidationError(
                {
                    "scope": (
                        f"Cette archive couvre {libelles.get(portee_archive, portee_archive or 'une portée inconnue')}, "
                        f"et la restauration demandée vise {libelles.get(scope, scope)}. "
                        "Choisissez le mode qui correspond à l'archive."
                    )
                }
            )

        if scope == BackupArchive.Scope.ETABLISSEMENT:
            source = manifeste.get("etablissement_id")
            if source is not None and etablissement_id is not None and int(source) != int(etablissement_id):
                raise ValidationError(
                    {
                        "scope": (
                            "Cette archive appartient à un autre établissement. La "
                            "restaurer ici viderait celui-ci puis écraserait "
                            "l'autre avec ses anciennes données."
                        )
                    }
                )

    def _restore_from_archive(self, backup: BackupArchive, archive_path: Path, actor=None):
        self._set_restore_progress(backup, progress=3, phase="Preparation de l'archive")
        # Verifiee a la reception, verifiee encore ici: c'est le dernier
        # instant avant que le nettoyage efface quoi que ce soit.
        self._verifier_la_portee(archive_path, backup.scope, backup.etablissement_id)
        restore_notes = []
        is_global_restore = backup.scope == BackupArchive.Scope.GLOBAL
        with tempfile.TemporaryDirectory(prefix="restore_backup_") as tmp:
            tmp_path = Path(tmp)
            with zipfile.ZipFile(archive_path, "r") as zf:
                zf.extractall(tmp_path)
            self._set_restore_progress(backup, progress=15, phase="Archive extraite")

            data_json = tmp_path / "data.json"
            if not data_json.exists():
                raise ValueError("Archive invalide: data.json manquant.")

            # `json.load` sur le fichier ouvert plutot que `loads` sur son
            # contenu: la seconde forme tient la chaine entiere et le graphe
            # d'objets en meme temps, soit deux fois la base en memoire.
            with data_json.open("r", encoding="utf-8") as flux:
                payload = json.load(flux)
            self._set_restore_progress(backup, progress=20, phase="Verification integrite")
            payload, orphan_stats = self._drop_orphan_foreign_key_relations(
                payload,
                check_db=not is_global_restore,
            )
            if orphan_stats:
                orphan_details = ", ".join(f"{k}: {v}" for k, v in orphan_stats.items())
                restore_notes.append(f"Lignes orphelines ignorees ({orphan_details}).")

            if is_global_restore:
                restore_notes.append("Preparation globale optimisee (verification DB ignoree).")
            else:
                self._set_restore_progress(backup, progress=24, phase="Adaptation des identifiants")
                payload, rewrite_stats = self._resolve_unique_field_conflicts(payload)
                if rewrite_stats:
                    details = ", ".join(f"{k}: {v}" for k, v in rewrite_stats.items())
                    restore_notes.append(f"Identifiants uniques adaptes ({details}).")

            # Le fichier n'est pas reecrit: le chargement lit desormais
            # `payload` directement. Le recopier en JSON refabriquait une
            # chaine de la taille de la base, pour personne.
            self._set_restore_progress(backup, progress=28, phase="Donnees preparees")

            media_dir = tmp_path / "media"

            with transaction.atomic():
                from django.core.management import call_command

                # For establishment restores, remove current scoped data first to
                # avoid duplicate PK / unique constraint conflicts on loaddata.
                if backup.scope == BackupArchive.Scope.ETABLISSEMENT and backup.etablissement_id:
                    self._set_restore_progress(backup, progress=40, phase="Nettoyage etablissement")
                    self._clear_establishment_scope_data(backup.etablissement)
                    restore_notes.append("Donnees existantes de l'etablissement nettoyees.")
                elif backup.scope == BackupArchive.Scope.GLOBAL:
                    self._set_restore_progress(backup, progress=40, phase="Nettoyage plateforme")
                    self._clear_global_scope_data()
                    restore_notes.append("Donnees existantes de la plateforme nettoyees.")

                self._set_restore_progress(backup, progress=62, phase="Chargement des donnees")
                with connection.constraint_checks_disabled():
                    self._charger_les_donnees(backup, payload)
                connection.check_constraints()
                self._set_restore_progress(backup, progress=82, phase="Donnees restaurees")

            if media_dir.exists() and media_dir.is_dir():
                media_root = Path(settings.MEDIA_ROOT)
                media_root.mkdir(parents=True, exist_ok=True)
                for src in media_dir.rglob("*"):
                    if not src.is_file():
                        continue
                    dst = media_root / src.relative_to(media_dir)
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dst)
                restore_notes.append("Medias restaures.")
            self._set_restore_progress(backup, progress=94, phase="Finalisation")

        # Le compte qui a lance la restauration peut ne plus exister: une
        # restauration globale remplace tous les comptes par ceux de
        # l'archive. Le noter tel quel faisait echouer cet enregistrement
        # final sur une cle etrangere -- apres que toutes les donnees etaient
        # chargees, si bien qu'une restauration reussie s'affichait en echec.
        from apps.accounts.models import User

        acteur_id = getattr(actor, "pk", None)
        backup.restored_by = (
            User.objects.filter(pk=acteur_id).first() if acteur_id else None
        )
        backup.restored_at = timezone.now()
        backup.restore_log = "\n".join(restore_notes) if restore_notes else "Restauration terminee."
        backup.restore_phase = "Terminee"
        backup.restore_progress = 100
        backup.status = BackupArchive.Status.COMPLETED
        backup.save(
            update_fields=[
                "restored_by",
                "restored_at",
                "restore_log",
                "restore_phase",
                "restore_progress",
                "status",
                "updated_at",
            ]
        )

    # La tranche de la barre occupee par le chargement des donnees.
    _PART_CHARGEMENT = (62, 82)

    # Combien de lignes partent en un seul aller-retour vers la base.
    TAILLE_DE_LOT_DE_CHARGEMENT = 500

    def _charger_les_donnees(self, backup, payload) -> None:
        """Recharge les lignes table par table, par lots, puis realigne les compteurs.

        Trois etapes, et chacune repare un defaut constate.

        Par lots. Chaque ligne partait seule, un aller-retour vers la base par
        ligne. En local, 58 719 lignes passaient en 1 min 35; en production,
        base distante et 0,1 processeur, l'ecran annoncait « reste ~12 min »
        apres 3 912 lignes. Pendant ce quart d'heure, une mise en veille ou
        un redemarrage de Render suffisait a tuer la restauration. Cinq cents
        lignes par aller-retour divisent d'autant le nombre de trajets.

        En ecrasant les lignes deja presentes plutot qu'en echouant. C'est ce
        que faisait l'enregistrement ligne a ligne: une restauration
        d'etablissement recharge aussi les comptes d'autres ecoles que ses
        enseignants referencent, et ceux-la n'ont pas ete supprimes.

        Puis en realignant les compteurs d'identifiants. `loaddata` le faisait,
        et l'avoir remplace l'avait perdu: apres une restauration, la
        prochaine saisie recevait un identifiant deja pris par une ligne
        restauree. Prouve: un compte restaure sous le numero 900 000, la
        saisie suivante recevait le numero 1.
        """
        if not isinstance(payload, list) or not payload:
            return

        # Les archives faites avant ce correctif emportaient encore
        # l'historique des sauvegardes et la presence: on les ecarte ici
        # plutot que de laisser un vieux fichier reecrire le present.
        payload = [
            ligne
            for ligne in payload
            if str(ligne.get("model") or "").lower() not in self.TABLES_HORS_ARCHIVE
        ]
        if not payload:
            return

        debut, fin = self._PART_CHARGEMENT
        total = len(payload)
        charges = 0

        # Par table, dans l'ordre d'apparition: c'est celui de la
        # serialisation, qui suit les dependances.
        par_modele: dict = {}
        for objet in serializers.deserialize("python", payload):
            par_modele.setdefault(type(objet.object), []).append(objet)

        for modele, objets in par_modele.items():
            for depart in range(0, len(objets), self.TAILLE_DE_LOT_DE_CHARGEMENT):
                lot = objets[depart : depart + self.TAILLE_DE_LOT_DE_CHARGEMENT]
                self._ecrire_un_lot_en_base(modele, lot)
                charges += len(lot)
                self._set_restore_progress(
                    backup,
                    progress=min(fin, debut + int((fin - debut) * (charges / total))),
                    phase=f"Chargement : {modele._meta.label} ({charges}/{total})",
                )

        self._realigner_les_compteurs(list(par_modele))

    def _ecrire_un_lot_en_base(self, modele, lot) -> None:
        """Insere un lot, en ecrasant les lignes dont l'identifiant existe deja."""
        instances = [objet.object for objet in lot]
        cle = modele._meta.pk
        a_mettre_a_jour = [
            champ.attname
            for champ in modele._meta.concrete_fields
            if not champ.primary_key
        ]

        if a_mettre_a_jour:
            modele.objects.bulk_create(
                instances,
                update_conflicts=True,
                unique_fields=[cle.name],
                update_fields=a_mettre_a_jour,
            )
        else:
            # Une table qui ne porte que sa cle: rien a mettre a jour.
            modele.objects.bulk_create(instances, ignore_conflicts=True)

        # Les liens multiples ne passent pas par `bulk_create`. On ne les
        # pose que s'ils existent: la table de liaison vient d'etre videe
        # avec les comptes, et un `set([])` par compte couterait un
        # aller-retour pour rien.
        for objet in lot:
            for champ, identifiants in (objet.m2m_data or {}).items():
                if identifiants:
                    getattr(objet.object, champ).set(identifiants)

    def _realigner_les_compteurs(self, modeles) -> None:
        """Place chaque compteur d'identifiants apres la plus grande valeur restauree."""
        from django.core.management.color import no_style

        if not modeles:
            return
        requetes = connection.ops.sequence_reset_sql(no_style(), modeles)
        if not requetes:
            return
        with connection.cursor() as curseur:
            for requete in requetes:
                curseur.execute(requete)

    def _resolve_unique_field_conflicts(self, payload):
        if not isinstance(payload, list):
            return payload, {}

        string_unique_fields = (
            models.CharField,
            models.EmailField,
            models.SlugField,
            models.TextField,
        )

        model_specs = {}
        for model in apps.get_models():
            opts = model._meta
            if opts.proxy or not opts.managed:
                continue

            unique_fields = []
            deja_vus = set()
            for field in opts.fields:
                if field.primary_key or not getattr(field, "unique", False):
                    continue
                if not isinstance(field, string_unique_fields):
                    continue
                max_length = getattr(field, "max_length", None) or 255
                unique_fields.append(
                    {
                        "name": field.name,
                        "max_length": max_length,
                        # Unique pour toute la table: rien ne borne la
                        # recherche de collision.
                        "scope": (),
                        # Une valeur vide viole la contrainte comme une
                        # autre: on lui en fabrique une.
                        "remplir_si_vide": True,
                    }
                )
                deja_vus.add(field.name)

            # Les memes garde-fous pour l'unicite portee par une contrainte
            # plutot que par le champ. Sans cela, passer `Book.isbn` d'un
            # `unique=True` global a une unicite par etablissement le faisait
            # sortir de ce mecanisme, et la restauration echouait sur une
            # erreur d'integrite au lieu de renommer le doublon.
            portees_par_champ = {}
            for constraint in getattr(opts, "constraints", ()):
                if not isinstance(constraint, models.UniqueConstraint):
                    continue
                champs = tuple(getattr(constraint, "fields", ()) or ())
                if not champs:
                    # Contrainte sur expressions: hors de portee de cette
                    # reecriture, qui ne sait comparer que des valeurs.
                    continue

                textuels = [
                    nom
                    for nom in champs
                    if isinstance(opts.get_field(nom), string_unique_fields)
                ]
                # Une seule colonne texte a reecrire: avec deux, il faudrait
                # choisir laquelle deplacer, et ce choix n'appartient pas a
                # une restauration.
                if len(textuels) != 1:
                    continue

                nom = textuels[0]
                if nom in deja_vus:
                    continue

                portee = tuple(c for c in champs if c != nom)
                # Un meme champ est souvent couvert par deux contraintes
                # complementaires -- l'une pour les lignes rattachees a un
                # etablissement, l'autre pour les orphelines. On retient la
                # portee la plus fine: la recherche « meme ISBN, meme
                # etablissement » couvre aussi les orphelins entre eux
                # (etablissement vide des deux cotes), tandis que la portee
                # large renommerait le livre de la voisine sans raison.
                ancienne = portees_par_champ.get(nom)
                if ancienne is None or len(portee) > len(ancienne):
                    portees_par_champ[nom] = portee

            for nom, portee in portees_par_champ.items():
                champ = opts.get_field(nom)
                unique_fields.append(
                    {
                        "name": nom,
                        "max_length": getattr(champ, "max_length", None) or 255,
                        "scope": portee,
                        # Ces contraintes portent souvent une condition qui
                        # exclut le vide (`~Q(source_url="")`): remplir un
                        # champ laisse vide inventerait une donnee la ou la
                        # contrainte ne s'applique meme pas.
                        "remplir_si_vide": False,
                    }
                )
                deja_vus.add(nom)

            if unique_fields:
                model_specs[opts.label_lower] = {
                    "model": model,
                    "fields": unique_fields,
                }

        seen_by_spec = {}
        rewrite_stats = {}

        def _normalize_model_label(value: str) -> str:
            normalized_label = str(value or "").strip().lower()
            parts = [part for part in normalized_label.split(".") if part]
            if len(parts) >= 2:
                return ".".join(parts[-2:])
            return normalized_label

        def _unique_prefix(model_label: str, field_name: str) -> str:
            model_name = model_label.split(".")[-1] if "." in model_label else model_label
            model_name = (model_name or "value").replace("_", "")
            field_bits = "".join(part[:2] for part in field_name.split("_")) or field_name[:3]
            return f"{model_name[:6]}{field_bits[:4]}".lower()

        def _matches_spec(entry_model_label: str, spec_model_label: str) -> bool:
            normalized_label = str(entry_model_label or "").strip().lower()
            normalized_spec = str(spec_model_label or "").strip().lower()
            if normalized_label == normalized_spec:
                return True
            parts = [part for part in normalized_label.split(".") if part]
            if len(parts) >= 2:
                tail2 = ".".join(parts[-2:])
                if tail2 == normalized_spec:
                    return True
            return False

        for entry in payload:
            if not isinstance(entry, dict):
                continue
            model_label = str(entry.get("model") or "").strip().lower()
            fields = entry.get("fields")
            if not isinstance(fields, dict):
                continue
            pk_value = entry.get("pk")

            normalized_model_label = _normalize_model_label(model_label)
            spec = model_specs.get(normalized_model_label)
            if spec is None:
                for spec_model_label in model_specs.keys():
                    if _matches_spec(model_label, spec_model_label):
                        normalized_model_label = spec_model_label
                        spec = model_specs[spec_model_label]
                        break

            if spec is None:
                continue

            model_cls = spec["model"]
            for champ_spec in spec["fields"]:
                field_name = champ_spec["name"]
                max_length = champ_spec["max_length"]
                portee = champ_spec["scope"]

                original_value = str(fields.get(field_name) or "").strip()
                if not original_value:
                    if not champ_spec["remplir_si_vide"]:
                        continue
                    original_value = f"{_unique_prefix(normalized_model_label, field_name)}_{pk_value or 'restored'}"

                # La portee entre dans la cle: deux etablissements ont le
                # droit de porter le meme ISBN, et les compter ensemble
                # renommerait le second sans raison.
                valeurs_de_portee = tuple(fields.get(nom) for nom in portee)
                cle = (normalized_model_label, field_name, valeurs_de_portee)
                seen_values = seen_by_spec.setdefault(cle, set())
                filtre_de_portee = {
                    nom: fields.get(nom) for nom in portee
                }

                new_value = original_value
                suffix = 0

                while True:
                    normalized_candidate = new_value.strip().lower()
                    collision_in_payload = normalized_candidate in seen_values
                    collision_in_db = (
                        model_cls.objects.filter(
                            **{f"{field_name}__iexact": new_value},
                            **filtre_de_portee,
                        )
                        .exclude(pk=pk_value)
                        .exists()
                    )
                    if not collision_in_payload and not collision_in_db:
                        break

                    suffix += 1
                    base_max = max(4, max_length - 18)
                    base = original_value[:base_max]
                    new_value = f"{base}_r{pk_value}_{suffix}"[:max_length]

                if new_value != original_value:
                    fields[field_name] = new_value
                    key = f"{normalized_model_label}.{field_name}"
                    rewrite_stats[key] = rewrite_stats.get(key, 0) + 1

                seen_values.add(new_value.strip().lower())

        return payload, rewrite_stats

    def _drop_orphan_foreign_key_relations(self, payload, *, check_db=True):
        if not isinstance(payload, list):
            return payload, {}

        model_map = {}
        fk_specs = {}
        for model in apps.get_models():
            opts = model._meta
            if opts.proxy or not opts.managed:
                continue
            model_map[opts.label_lower] = model

            specs = []
            for field in opts.fields:
                if not isinstance(field, (models.ForeignKey, models.OneToOneField)):
                    continue
                remote_model = getattr(getattr(field, "remote_field", None), "model", None)
                if remote_model is None:
                    continue
                specs.append(
                    {
                        "field_name": field.name,
                        "target_label": remote_model._meta.label_lower,
                        "nullable": bool(getattr(field, "null", False)),
                    }
                )
            fk_specs[opts.label_lower] = specs

        def _normalize_model_label(value: str) -> str:
            normalized = str(value or "").strip().lower()
            parts = [part for part in normalized.split(".") if part]
            if len(parts) >= 2:
                return ".".join(parts[-2:])
            return normalized


        def _payload_pk_index(rows):
            index = {}
            for item in rows:
                if not isinstance(item, dict):
                    continue
                label = _normalize_model_label(item.get("model"))
                pk_value = item.get("pk")
                if label and pk_value not in (None, ""):
                    index.setdefault(label, set()).add(str(pk_value))
            return index

        db_fk_cache = {}

        def _exists_in_db(target_label: str, pk_value: str) -> bool:
            if not check_db:
                return False

            cache_key = (target_label, pk_value)
            if cache_key in db_fk_cache:
                return db_fk_cache[cache_key]

            model_cls = model_map.get(target_label)
            if model_cls is None:
                db_fk_cache[cache_key] = True
                return True

            exists = model_cls.objects.filter(pk=pk_value).exists()
            db_fk_cache[cache_key] = exists
            return exists

        cleaned_payload = list(payload)
        dropped_stats = {}

        while True:
            removed_in_pass = 0
            payload_pk_index = _payload_pk_index(cleaned_payload)
            next_payload = []

            for entry in cleaned_payload:
                if not isinstance(entry, dict):
                    next_payload.append(entry)
                    continue

                model_label = _normalize_model_label(entry.get("model"))
                fields = entry.get("fields")
                if not isinstance(fields, dict):
                    next_payload.append(entry)
                    continue

                entry_invalid = False
                for spec in fk_specs.get(model_label, []):
                    field_name = spec["field_name"]
                    target_label = spec["target_label"]
                    nullable = spec["nullable"]
                    fk_value = fields.get(field_name)

                    if fk_value in (None, ""):
                        if nullable:
                            continue
                        entry_invalid = True
                        break

                    fk_key = str(fk_value)
                    if fk_key in payload_pk_index.get(target_label, set()):
                        continue

                    if _exists_in_db(target_label, fk_key):
                        continue

                    entry_invalid = True
                    break

                if entry_invalid:
                    dropped_stats[model_label] = dropped_stats.get(model_label, 0) + 1
                    removed_in_pass += 1
                    continue

                next_payload.append(entry)

            cleaned_payload = next_payload
            if removed_in_pass == 0:
                break

        return cleaned_payload, dropped_stats

    def _clear_global_scope_data(self):
        # Preserve backup history rows while cleaning platform data.
        global_models = []
        for model in apps.get_models():
            opts = model._meta
            if opts.proxy or not opts.managed:
                continue
            if opts.app_label in {"contenttypes", "sessions", "admin", "auth"}:
                continue
            if model.__name__ in {"BackupArchive"}:
                continue
            if self._est_ephemere(model):
                continue
            global_models.append(model)

        retry_models = []
        for model in reversed(global_models):
            try:
                model.objects.all().delete()
            except ProtectedError:
                retry_models.append(model)

        for model in retry_models:
            model.objects.all().delete()

    def _clear_establishment_scope_data(self, etablissement):
        if etablissement is None:
            return

        from apps.accounts.models import User

        # Delete remaining establishment-scoped rows in reverse model order to
        # reduce protected relation conflicts between dependent tables.
        scoped_models = []
        for model in apps.get_models():
            opts = model._meta
            if opts.proxy or not opts.managed:
                continue
            if opts.app_label in {"contenttypes", "sessions", "admin", "auth"}:
                continue

            field_names = {field.name for field in opts.fields}
            if model.__name__ in {"Etablissement", "BackupArchive"}:
                continue
            if "etablissement" not in field_names:
                continue

            scoped_models.append(model)

        retry_models = []
        for model in reversed(scoped_models):
            try:
                model.objects.filter(etablissement=etablissement).delete()
            except ProtectedError:
                retry_models.append(model)

        # Some models (ex: PromotionDecision) do not carry etablissement but
        # protect Student deletion. Remove those references before retrying.
        self._clear_protected_student_dependencies(etablissement)

        # Second pass once most child rows are gone.
        for model in retry_models:
            model.objects.filter(etablissement=etablissement).delete()

        # Delete users of the establishment last, once protected student
        # dependencies have been removed.
        User.objects.filter(etablissement=etablissement).delete()

    def _clear_protected_student_dependencies(self, etablissement):
        from apps.school.models import Student

        student_ids = list(
            Student.objects.filter(etablissement=etablissement).values_list("pk", flat=True)
        )
        if not student_ids:
            return

        for model in apps.get_models():
            opts = model._meta
            if opts.proxy or not opts.managed:
                continue
            if opts.app_label in {"contenttypes", "sessions", "admin", "auth"}:
                continue

            for field in opts.fields:
                if not isinstance(field, (models.ForeignKey, models.OneToOneField)):
                    continue
                remote_model = getattr(getattr(field, "remote_field", None), "model", None)
                on_delete = getattr(getattr(field, "remote_field", None), "on_delete", None)
                if remote_model is not Student or on_delete is not models.PROTECT:
                    continue

                lookup = {f"{field.name}_id__in": student_ids}
                model.objects.filter(**lookup).delete()

    def _run_build_in_background(self, backup_id: int):
        """Ecrit l'archive dans un processus detache.

        Elle etait construite pendant la requete POST. Sur un etablissement
        charge en documents, la reponse arrivait apres plusieurs minutes --
        quand la passerelle ne coupait pas avant -- et rien ne pouvait etre
        affiche pendant ce temps. Detachee, la requete rend la main tout de
        suite et l'ecran suit l'avancement en interrogeant la ligne.
        """
        manage_py = Path(settings.BASE_DIR) / "manage.py"
        command = [
            sys.executable,
            str(manage_py),
            "run_backup_create",
            f"--backup-id={backup_id}",
        ]

        env = os.environ.copy()
        env.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

        # La sortie partait dans le vide, comme celle de la restauration avant
        # elle: une sauvegarde tuee par la memoire restait figee sur
        # « Lecture de la base » sans que rien dise pourquoi.
        try:
            sortie = self._journal_de_sauvegarde(backup_id).open("wb")
        except OSError:
            sortie = subprocess.DEVNULL

        subprocess.Popen(
            command,
            cwd=str(settings.BASE_DIR),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=sortie,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

    def _run_restore_in_background(self, backup_id: int, archive_path: str, actor_id: int | None):
        manage_py = Path(settings.BASE_DIR) / "manage.py"
        command = [
            sys.executable,
            str(manage_py),
            "run_backup_restore",
            f"--backup-id={backup_id}",
            f"--archive-path={archive_path}",
        ]
        if actor_id:
            command.append(f"--actor-id={actor_id}")

        env = os.environ.copy()
        env.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

        # La sortie du processus partait dans le vide. Quand il mourait --
        # memoire epuisee sur une grosse base, erreur d'import, conteneur
        # recycle -- la ligne restait « en cours » a son dernier pourcentage,
        # indefiniment, et rien ne disait pourquoi. Elle est desormais
        # gardee: `_verifier_les_restaurations_bloquees` la recopie dans le
        # journal de l'archive.
        journal = self._journal_de_restauration(backup_id)
        try:
            sortie = journal.open("wb")
        except OSError:
            sortie = subprocess.DEVNULL

        try:
            subprocess.Popen(
                command,
                cwd=str(settings.BASE_DIR),
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=sortie,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
        except Exception as exc:
            self._mark_restore_failed(backup_id, exc)
            raise

    # Au-dela de ce silence, une restauration est tenue pour morte.
    #
    # Le processus ecrit son avancement au fil de l'eau -- au plus quelques
    # secondes entre deux signaux, meme sur une grosse base. Un quart d'heure
    # sans rien n'est plus de la lenteur: le processus a ete tue, et personne
    # ne l'apprendra jamais si l'ecran continue d'afficher sa barre.
    SILENCE_AVANT_ABANDON = timedelta(minutes=15)

    def _journal_de_sauvegarde(self, backup_id: int) -> Path:
        dossier = Path(settings.BACKUP_ROOT) / "journaux"
        dossier.mkdir(parents=True, exist_ok=True)
        return dossier / f"sauvegarde_{backup_id}.log"

    def _journal_de_restauration(self, backup_id: int) -> Path:
        dossier = Path(settings.BACKUP_ROOT) / "journaux"
        dossier.mkdir(parents=True, exist_ok=True)
        return dossier / f"restauration_{backup_id}.log"

    def _verifier_les_restaurations_bloquees(self, queryset):
        """Marque en echec ce qui ne repond plus, et dit pourquoi.

        Une operation qui meurt laissait sa ligne « en cours » a son dernier
        pourcentage, indefiniment. L'ecran affichait une barre qui n'avancait
        plus et personne ne pouvait ni relancer ni comprendre. Les deux sens
        sont concernes: une sauvegarde reste figee sur « Lecture de la base »
        exactement comme une restauration reste figee sur son chargement.
        """
        limite = timezone.now() - self.SILENCE_AVANT_ABANDON
        minutes = int(self.SILENCE_AVANT_ABANDON.total_seconds() // 60)

        for archive in queryset.filter(
            status=BackupArchive.Status.RUNNING, updated_at__lt=limite
        ):
            if not self._est_silencieuse(archive):
                continue

            restauration = bool((archive.restore_phase or "").strip()) or bool(
                self.avancement_sur_disque(archive.id).get("restore_phase")
            )
            geste = "restauration" if restauration else "sauvegarde"

            journal = (
                self._journal_de_restauration(archive.id)
                if restauration
                else self._journal_de_sauvegarde(archive.id)
            )
            try:
                trace = journal.read_text(encoding="utf-8", errors="replace")[-4000:]
            except OSError:
                trace = ""

            message = (
                f"La {geste} ne repond plus depuis {minutes} minutes: "
                "le traitement a ete interrompu. Relancez-la, et si "
                "l'interruption se repete, la base est probablement trop "
                f"volumineuse pour la memoire du serveur.\n\n{trace}"
            ).strip()

            champs = {
                "status": BackupArchive.Status.FAILED,
                "restore_log": message,
                "updated_at": timezone.now(),
            }
            if restauration:
                champs["restore_phase"] = "Interrompue"
            else:
                champs["build_phase"] = "Interrompue"
            BackupArchive.objects.filter(pk=archive.id).update(**champs)

    def get_queryset(self):
        queryset = super().get_queryset()
        if self._is_super_admin():
            portee = queryset
        else:
            user_etablissement = getattr(self.request.user, "etablissement", None)
            if user_etablissement is None:
                return queryset.none()
            portee = queryset.filter(
                scope=BackupArchive.Scope.ETABLISSEMENT,
                etablissement=user_etablissement,
            )

        # L'ecran interroge cette liste toutes les quatre secondes pendant
        # une restauration: c'est donc ici qu'on remarque qu'elle ne repond
        # plus, sans tache planifiee ni minuteur.
        self._verifier_les_restaurations_bloquees(portee)
        return portee

    def create(self, request, *args, **kwargs):
        scope = str(request.data.get("scope") or BackupArchive.Scope.ETABLISSEMENT).strip()
        include_media = self._drapeau(request.data.get("include_media", True), defaut=True)
        # Hors bibliotheque par defaut: c'est le choix qui rend la sauvegarde
        # legere, donc frequente. Qui veut le fonds complet le demande.
        include_library = self._drapeau(
            request.data.get("include_library_documents", False), defaut=False
        )
        notes = str(request.data.get("notes") or "").strip()

        if scope not in {BackupArchive.Scope.GLOBAL, BackupArchive.Scope.ETABLISSEMENT}:
            return Response({"detail": "Scope invalide."}, status=status.HTTP_400_BAD_REQUEST)

        if scope == BackupArchive.Scope.GLOBAL and not self._is_super_admin():
            return Response(
                {"detail": "Seul un super admin peut creer une sauvegarde globale."},
                status=status.HTTP_403_FORBIDDEN,
            )

        etablissement = None
        if scope == BackupArchive.Scope.ETABLISSEMENT:
            etablissement = self._resolve_etablissement()
            if etablissement is None:
                return Response(
                    {"detail": "Etablissement introuvable pour la sauvegarde."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if not self._is_super_admin() and getattr(request.user, "etablissement_id", None) != etablissement.id:
                return Response(
                    {"detail": "Vous ne pouvez sauvegarder que votre etablissement."},
                    status=status.HTTP_403_FORBIDDEN,
                )

        self._refuser_si_une_operation_tourne()

        backup = BackupArchive.objects.create(
            scope=scope,
            etablissement=etablissement,
            created_by=request.user,
            include_media=include_media,
            include_library_documents=include_library and include_media,
            notes=notes,
            status=BackupArchive.Status.PENDING,
            build_phase="En attente du traitement",
            build_progress=1,
        )

        try:
            self._run_build_in_background(backup.id)
        except Exception as exc:
            self._mark_build_failed(backup.id, exc)
            backup.refresh_from_db()
            return Response(
                {"detail": f"Echec sauvegarde: {exc}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        # 202 et non 201: la ligne existe, l'archive pas encore. L'ecran suit
        # `build_progress` jusqu'au statut « terminee ».
        return Response(self.get_serializer(backup).data, status=status.HTTP_202_ACCEPTED)

    # --- Volume, suppression, menage -------------------------------------

    @action(detail=False, methods=["get"], url_path="volumes")
    def volumes(self, request):
        """Ce qu'une sauvegarde pesera, avant de la lancer.

        L'ecran proposait « inclure les medias » sans dire ce que cela
        represente. Le fonds d'annales pese a lui seul plusieurs
        giga-octets: la case se cochait a l'aveugle, et la sauvegarde
        devenait interminable sans qu'on comprenne pourquoi.
        """
        media_root = Path(settings.MEDIA_ROOT)
        sans_bibliotheque = poids_total(
            fichiers_a_archiver(media_root, avec_bibliotheque=False)
        )
        bibliotheque = volume_de_la_bibliotheque(media_root)
        archives = BackupArchive.objects.aggregate(
            nombre=models.Count("id"),
            octets=models.Sum("file_size_bytes"),
        )
        return Response(
            {
                "media_hors_bibliotheque_octets": sans_bibliotheque,
                "bibliotheque_octets": bibliotheque,
                "media_total_octets": sans_bibliotheque + bibliotheque,
                "archives_nombre": archives["nombre"] or 0,
                "archives_octets": archives["octets"] or 0,
            }
        )

    def _supprimer_le_fichier(self, backup: BackupArchive) -> None:
        """Retire l'archive du disque. La ligne seule ne libere rien."""
        brut = str(backup.file_path or "").strip()
        if not brut:
            return
        chemin = Path(brut).expanduser()
        # Cantonne a l'entrepot d'archives: un `file_path` bricole en base ne
        # doit pas pouvoir faire effacer un fichier quelconque du serveur.
        racine = self._backups_root().resolve()
        try:
            resolu = chemin.resolve()
            resolu.relative_to(racine)
        except (OSError, ValueError):
            return
        try:
            resolu.unlink(missing_ok=True)
        except OSError:
            pass

    def destroy(self, request, *args, **kwargs):
        backup = self.get_object()

        if backup.scope == BackupArchive.Scope.GLOBAL and not self._is_super_admin():
            return Response(
                {"detail": "Seul un super admin peut supprimer une sauvegarde globale."},
                status=status.HTTP_403_FORBIDDEN,
            )
        if backup.status in {BackupArchive.Status.RUNNING, BackupArchive.Status.PENDING}:
            # Effacer le fichier qu'un processus est en train d'ecrire
            # laisserait une archive tronquee et une ligne qui la reclame.
            #
            # Encore faut-il qu'un processus l'ecrive vraiment. Une ligne
            # dont le traitement est mort restait « en cours » pour toujours,
            # donc impossible a supprimer: l'ecran refusait sans fin une
            # archive que plus personne ne touchait. On la laisse partir des
            # qu'elle s'est tue assez longtemps.
            if not self._est_silencieuse(backup):
                return Response(
                    {
                        "detail": (
                            "Opération en cours : attendez la fin avant de "
                            "supprimer."
                        )
                    },
                    status=status.HTTP_409_CONFLICT,
                )

        self._supprimer_le_fichier(backup)
        backup.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)

    @action(detail=False, methods=["post"], url_path="purge")
    def purge(self, request):
        """Efface les anciennes archives, en gardant les plus recentes.

        `conserver` fixe combien d'archives terminees survivent (la plus
        recente au minimum: un historique vide n'est pas un menage, c'est
        une perte). `avant_jours`, s'il est donne, restreint la coupe aux
        archives plus vieilles que ce nombre de jours.
        """
        try:
            conserver = max(1, int(request.data.get("conserver", 3)))
        except (TypeError, ValueError):
            return Response(
                {"detail": "Nombre d'archives a conserver invalide."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        avant_jours = request.data.get("avant_jours")
        limite = None
        if avant_jours not in (None, ""):
            try:
                limite = timezone.now() - timedelta(days=max(0, int(avant_jours)))
            except (TypeError, ValueError):
                return Response(
                    {"detail": "Anciennete invalide."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        # `get_queryset` cantonne deja la direction a son etablissement: le
        # menage ne peut pas atteindre les archives d'une autre ecole.
        # Une operation vraiment en cours est epargnee; une ligne dont le
        # traitement est mort, non. Sans cette nuance, une archive figee
        # survivait a tous les nettoyages et encombrait l'historique pour
        # toujours.
        candidates = [
            archive
            for archive in self.filter_queryset(self.get_queryset())
            if archive.status
            not in {BackupArchive.Status.RUNNING, BackupArchive.Status.PENDING}
            or self._est_silencieuse(archive)
        ]
        candidates.sort(key=lambda row: (row.created_at, row.id), reverse=True)

        supprimees = 0
        octets_liberes = 0
        for backup in candidates[conserver:]:
            if limite is not None and backup.created_at >= limite:
                continue
            if backup.scope == BackupArchive.Scope.GLOBAL and not self._is_super_admin():
                continue
            octets_liberes += int(backup.file_size_bytes or 0)
            self._supprimer_le_fichier(backup)
            backup.delete()
            supprimees += 1

        return Response(
            {
                "supprimees": supprimees,
                "octets_liberes": octets_liberes,
                "conservees": min(len(candidates), conserver),
            }
        )

    @action(detail=True, methods=["get"], url_path="download")
    def download(self, request, pk=None):
        backup = self.get_object()
        archive_path = Path(str(backup.file_path or "")).expanduser()
        if not archive_path.exists() or not archive_path.is_file():
            return Response({"detail": "Fichier backup introuvable."}, status=status.HTTP_404_NOT_FOUND)

        response = FileResponse(archive_path.open("rb"), as_attachment=True, filename=backup.filename or archive_path.name)
        return response

    @action(detail=True, methods=["post"], url_path="restore")
    def restore(self, request, pk=None):
        denied = self._require_super_admin_restore()
        if denied is not None:
            return denied

        backup = self.get_object()
        if backup.scope == BackupArchive.Scope.GLOBAL and not self._is_super_admin():
            return Response(
                {"detail": "Seul un super admin peut restaurer une sauvegarde globale."},
                status=status.HTTP_403_FORBIDDEN,
            )

        archive_path = Path(str(backup.file_path or "")).expanduser()
        if not archive_path.exists() or not archive_path.is_file():
            return Response({"detail": "Fichier backup introuvable."}, status=status.HTTP_404_NOT_FOUND)

        self._refuser_si_une_operation_tourne()
        self._verifier_la_portee(archive_path, backup.scope, backup.etablissement_id)

        backup.status = BackupArchive.Status.RUNNING
        backup.restore_log = "Restauration lancee en arriere-plan."
        backup.restore_phase = "En attente du traitement"
        backup.restore_progress = 1
        backup.restore_started_at = timezone.now()
        backup.save(
            update_fields=[
                "status",
                "restore_log",
                "restore_phase",
                "restore_progress",
                "restore_started_at",
                "updated_at",
            ]
        )
        self._run_restore_in_background(backup.id, str(archive_path), getattr(request.user, "id", None))
        return Response(
            {
                "detail": "Restauration lancee en arriere-plan.",
                "backup": self.get_serializer(backup).data,
            },
            status=status.HTTP_202_ACCEPTED,
        )

    @action(detail=False, methods=["post"], url_path="upload-restore")
    def upload_restore(self, request):
        denied = self._require_super_admin_restore()
        if denied is not None:
            return denied

        # Avant meme de recevoir le fichier: inutile de televerser plusieurs
        # centaines de mega-octets pour se les voir refuser a l'arrivee.
        self._refuser_si_une_operation_tourne()
        uploaded = request.FILES.get("file")
        if not isinstance(uploaded, UploadedFile):
            return Response({"detail": "Fichier requis."}, status=status.HTTP_400_BAD_REQUEST)

        scope = str(request.data.get("scope") or BackupArchive.Scope.ETABLISSEMENT).strip()
        if scope not in {BackupArchive.Scope.GLOBAL, BackupArchive.Scope.ETABLISSEMENT}:
            return Response({"detail": "Scope invalide."}, status=status.HTTP_400_BAD_REQUEST)

        if scope == BackupArchive.Scope.GLOBAL and not self._is_super_admin():
            return Response(
                {"detail": "Seul un super admin peut restaurer globalement."},
                status=status.HTTP_403_FORBIDDEN,
            )

        etablissement = None
        if scope == BackupArchive.Scope.ETABLISSEMENT:
            etablissement = self._resolve_etablissement()
            if etablissement is None:
                return Response(
                    {"detail": "Etablissement introuvable pour la restauration."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if not self._is_super_admin() and getattr(request.user, "etablissement_id", None) != etablissement.id:
                return Response(
                    {"detail": "Vous ne pouvez restaurer que votre etablissement."},
                    status=status.HTTP_403_FORBIDDEN,
                )

        backup_dir = self._backups_root()
        stamp = timezone.localtime().strftime("%Y%m%d_%H%M%S")
        target = backup_dir / f"uploaded_restore_{scope}_{stamp}.zip"
        with target.open("wb") as out:
            for chunk in uploaded.chunks():
                out.write(chunk)

        # A la reception, avant toute ligne en base et tout processus: une
        # archive qui ne correspond pas au mode choisi est refusee sur le
        # champ, avec la raison, au lieu d'echouer plus tard en arriere-plan
        # -- ou pire, de reussir en effacant les autres ecoles.
        try:
            self._verifier_la_portee(
                target, scope, getattr(etablissement, "id", None)
            )
        except ValidationError:
            target.unlink(missing_ok=True)
            raise

        backup = BackupArchive.objects.create(
            scope=scope,
            etablissement=etablissement,
            created_by=request.user,
            filename=target.name,
            file_path=str(target),
            file_size_bytes=target.stat().st_size,
            sha256=self._sha256_file(target),
            notes=str(request.data.get("notes") or "").strip(),
            status=BackupArchive.Status.RUNNING,
            restore_phase="Archive recue",
            restore_progress=1,
            # Sans lui, l'ecran ne pouvait pas estimer la duree restante des
            # restaurations televersees -- celles-la memes qu'on fait pour
            # passer d'un serveur a l'autre.
            restore_started_at=timezone.now(),
        )
        backup.restore_log = "Archive recue. Restauration lancee en arriere-plan."
        backup.save(update_fields=["restore_log", "restore_phase", "restore_progress", "updated_at"])
        self._run_restore_in_background(backup.id, str(target), getattr(request.user, "id", None))
        return Response(
            {
                "detail": "Archive recue. Restauration lancee en arriere-plan.",
                "backup": self.get_serializer(backup).data,
            },
            status=status.HTTP_202_ACCEPTED,
        )


class PersonnalisationView(APIView):
    """L'identite de l'ecole: lisible par tous, modifiable par le seul super admin.

    La lecture est ouverte parce que les deux ecrans qui en ont le plus
    besoin -- la connexion et le portail de selection -- s'affichent avant
    qu'on soit authentifie. Ce qu'elle expose est de toute facon ce que
    n'importe quel visiteur lit sur la page d'accueil.

    L'ecriture passe par la matrice, sur un module « personnalisation »
    ouvert au seul super admin -- directeur compris: ces reglages valent pour
    tous les etablissements a la fois, et le directeur d'un site n'a pas a
    decider de ce que lisent les autres.
    """

    access_module = "personnalisation"
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get_permissions(self):
        # Meme partage que le portail de selection: on lit sans compte, on
        # ecrit avec les droits. La matrice garde la main sur l'ecriture.
        if self.request.method in permissions.SAFE_METHODS:
            return [AllowAny()]
        return [permissions.IsAuthenticated(), HasModuleAccess()]

    def get(self, request):
        personnalisation = PersonnalisationPlateforme.actuelle()
        return Response(
            PersonnalisationSerializer(
                personnalisation, context={"request": request}
            ).data
        )

    def patch(self, request):
        personnalisation = PersonnalisationPlateforme.actuelle()
        serializer = PersonnalisationSerializer(
            personnalisation,
            data=request.data,
            partial=True,
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
