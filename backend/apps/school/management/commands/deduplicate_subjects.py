from __future__ import annotations

from collections import defaultdict

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.school.models import ExamPlanning, ExamResult, Grade, Subject, TeacherAssignment


class Command(BaseCommand):
    help = (
        "Deduplicate Subject rows and remap dependent records "
        "(teacher assignments, grades, exam planning, exam results)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--apply",
            action="store_true",
            help="Persist changes. Without this flag, runs as dry-run.",
        )

    @staticmethod
    def _name_key(name: str) -> str:
        return " ".join(str(name or "").strip().lower().split())

    @staticmethod
    def _infer_subject_etab_ids(subject: Subject) -> set[int]:
        etab_ids = set(
            TeacherAssignment.objects.filter(
                subject_id=subject.id,
                classroom__etablissement_id__isnull=False,
            ).values_list("classroom__etablissement_id", flat=True)
        )
        etab_ids.update(
            Grade.objects.filter(
                subject_id=subject.id,
                classroom__etablissement_id__isnull=False,
            ).values_list("classroom__etablissement_id", flat=True)
        )
        etab_ids.update(
            ExamPlanning.objects.filter(
                subject_id=subject.id,
                classroom__etablissement_id__isnull=False,
            ).values_list("classroom__etablissement_id", flat=True)
        )
        etab_ids.update(
            ExamResult.objects.filter(
                subject_id=subject.id,
                student__etablissement_id__isnull=False,
            ).values_list("student__etablissement_id", flat=True)
        )
        etab_ids.update(
            ExamResult.objects.filter(
                subject_id=subject.id,
                student__classroom__etablissement_id__isnull=False,
            ).values_list("student__classroom__etablissement_id", flat=True)
        )
        return {int(v) for v in etab_ids if v is not None}

    @staticmethod
    def _subject_ref_count(subject: Subject) -> int:
        return (
            TeacherAssignment.objects.filter(subject_id=subject.id).count()
            + Grade.objects.filter(subject_id=subject.id).count()
            + ExamPlanning.objects.filter(subject_id=subject.id).count()
            + ExamResult.objects.filter(subject_id=subject.id).count()
        )

    @staticmethod
    def _choose_canonical(subjects: list[Subject]) -> Subject:
        ranked = sorted(
            subjects,
            key=lambda s: (
                0 if s.classroom_id is None else 1,
                Command._subject_ref_count(s),
                -s.id,
            ),
            reverse=True,
        )
        return ranked[0]

    @staticmethod
    def _merge_grade(existing: Grade, incoming: Grade) -> None:
        changed = False
        if incoming.value is not None and (existing.value is None or incoming.value > existing.value):
            existing.value = incoming.value
            changed = True

        incoming_hw = incoming.homework_scores if isinstance(incoming.homework_scores, list) else []
        existing_hw = existing.homework_scores if isinstance(existing.homework_scores, list) else []
        if len(incoming_hw) > len(existing_hw):
            existing.homework_scores = incoming_hw
            changed = True

        if changed:
            existing.save()

    @staticmethod
    def _merge_exam_result(existing: ExamResult, incoming: ExamResult) -> None:
        if incoming.score is not None and (existing.score is None or incoming.score > existing.score):
            existing.score = incoming.score
            existing.save()

    @staticmethod
    def _dedupe_exam_planning_on_subject(subject_id: int) -> int:
        deleted = 0
        seen = set()
        rows = ExamPlanning.objects.filter(subject_id=subject_id).order_by("id")
        for row in rows:
            key = (
                row.session_id,
                row.classroom_id,
                row.exam_date,
                row.start_time,
                row.end_time,
            )
            if key in seen:
                row.delete()
                deleted += 1
            else:
                seen.add(key)
        return deleted

    def _remap_subject(self, old_subject: Subject, new_subject: Subject, summary: dict[str, int]) -> None:
        assignment_rows = list(TeacherAssignment.objects.filter(subject_id=old_subject.id).order_by("id"))
        for row in assignment_rows:
            conflict = TeacherAssignment.objects.filter(
                teacher_id=row.teacher_id,
                classroom_id=row.classroom_id,
                subject_id=new_subject.id,
            ).first()
            if conflict:
                row.delete()
                summary["teacher_assignment_deleted_conflict"] += 1
            else:
                row.subject_id = new_subject.id
                row.save(update_fields=["subject", "updated_at"])
                summary["teacher_assignment_remapped"] += 1

        grade_rows = list(Grade.objects.filter(subject_id=old_subject.id).order_by("id"))
        for row in grade_rows:
            conflict = Grade.objects.filter(
                student_id=row.student_id,
                classroom_id=row.classroom_id,
                academic_year_id=row.academic_year_id,
                term=row.term,
                subject_id=new_subject.id,
            ).first()
            if conflict:
                self._merge_grade(conflict, row)
                row.delete()
                summary["grade_deleted_conflict"] += 1
            else:
                row.subject_id = new_subject.id
                row.save(update_fields=["subject", "updated_at"])
                summary["grade_remapped"] += 1

        planning_rows = list(ExamPlanning.objects.filter(subject_id=old_subject.id).order_by("id"))
        for row in planning_rows:
            row.subject_id = new_subject.id
            row.save(update_fields=["subject", "updated_at"])
            summary["exam_planning_remapped"] += 1

        summary["exam_planning_deleted_conflict"] += self._dedupe_exam_planning_on_subject(new_subject.id)

        result_rows = list(ExamResult.objects.filter(subject_id=old_subject.id).order_by("id"))
        for row in result_rows:
            conflict = ExamResult.objects.filter(
                session_id=row.session_id,
                student_id=row.student_id,
                subject_id=new_subject.id,
            ).first()
            if conflict:
                self._merge_exam_result(conflict, row)
                row.delete()
                summary["exam_result_deleted_conflict"] += 1
            else:
                row.subject_id = new_subject.id
                row.save(update_fields=["subject", "updated_at"])
                summary["exam_result_remapped"] += 1

        old_subject.delete()
        summary["subject_deleted"] += 1

    @transaction.atomic
    def handle(self, *args, **options):
        apply_changes = bool(options.get("apply"))
        dry_run = not apply_changes

        summary = defaultdict(int)
        grouped: dict[tuple, list[Subject]] = defaultdict(list)
        ambiguous_subject_ids: list[int] = []

        subjects = list(Subject.objects.select_related("classroom", "classroom__etablissement").order_by("id"))
        for subject in subjects:
            key_name = self._name_key(subject.name)
            if not key_name:
                continue

            if subject.classroom_id is not None:
                key = ("classroom", subject.classroom_id, key_name)
            else:
                etab_ids = self._infer_subject_etab_ids(subject)
                if len(etab_ids) == 1:
                    etab_id = list(etab_ids)[0]
                    key = ("etab", etab_id, key_name)
                elif len(etab_ids) == 0:
                    key = ("legacy_orphan", key_name)
                else:
                    ambiguous_subject_ids.append(subject.id)
                    continue

            grouped[key].append(subject)

        duplicate_groups = [rows for rows in grouped.values() if len(rows) > 1]
        summary["subject_total"] = len(subjects)
        summary["duplicate_groups"] = len(duplicate_groups)
        summary["ambiguous_subjects_skipped"] = len(ambiguous_subject_ids)

        for group in duplicate_groups:
            canonical = self._choose_canonical(group)
            for subject in group:
                if subject.id == canonical.id:
                    continue
                summary["subject_to_merge"] += 1
                self._remap_subject(subject, canonical, summary)

        if dry_run:
            transaction.set_rollback(True)
            self.stdout.write(self.style.WARNING("Dry-run: rollback applied, no data changed."))
        else:
            self.stdout.write(self.style.SUCCESS("Deduplication applied."))

        for key in sorted(summary.keys()):
            self.stdout.write(f"{key}: {summary[key]}")

        if ambiguous_subject_ids:
            sample = ", ".join(str(v) for v in ambiguous_subject_ids[:20])
            suffix = " ..." if len(ambiguous_subject_ids) > 20 else ""
            self.stdout.write(
                self.style.WARNING(
                    f"Ambiguous subject IDs skipped ({len(ambiguous_subject_ids)}): {sample}{suffix}"
                )
            )
