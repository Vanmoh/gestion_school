from __future__ import annotations

import os
import sys
from collections import defaultdict

sys.path.insert(0, "/app")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django  # noqa: E402


django.setup()

from django.db import transaction  # noqa: E402
from django.db.models import Count  # noqa: E402
from apps.school.models import ExamPlanning, ExamResult, Grade, Subject, TeacherAssignment  # noqa: E402


def name_key(name: str) -> str:
    return " ".join(str(name or "").strip().lower().split())


def pick_canonical(classroom_id: int, subject_ids: list[int]) -> int:
    best_id = subject_ids[0]
    best_count = -1
    for sid in subject_ids:
        count = Grade.objects.filter(classroom_id=classroom_id, subject_id=sid).count()
        if count > best_count:
            best_count = count
            best_id = sid
    return best_id


def merge_grade(existing: Grade, incoming: Grade) -> None:
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


def merge_exam_result(existing: ExamResult, incoming: ExamResult) -> None:
    if incoming.score is not None and (existing.score is None or incoming.score > existing.score):
        existing.score = incoming.score
        existing.save()


def dedupe_exam_planning(classroom_id: int, subject_id: int) -> int:
    deleted = 0
    seen = set()
    rows = ExamPlanning.objects.filter(classroom_id=classroom_id, subject_id=subject_id).order_by("id")
    for row in rows:
        key = (row.session_id, row.exam_date, row.start_time, row.end_time)
        if key in seen:
            row.delete()
            deleted += 1
        else:
            seen.add(key)
    return deleted


def main() -> None:
    summary = defaultdict(int)

    dup_groups = list(
        Grade.objects.values("classroom_id", "subject__name")
        .annotate(subject_count=Count("subject_id", distinct=True), grade_count=Count("id"))
        .filter(subject_count__gt=1)
        .order_by("classroom_id", "subject__name")
    )

    summary["duplicate_groups_before"] = len(dup_groups)

    with transaction.atomic():
        for group in dup_groups:
            classroom_id = int(group["classroom_id"])
            subject_name = str(group["subject__name"] or "")
            key = name_key(subject_name)

            subject_ids = list(
                Subject.objects.filter(id__in=Grade.objects.filter(classroom_id=classroom_id).values_list("subject_id", flat=True))
                .filter(name__isnull=False)
                .order_by("id")
                .values_list("id", "name")
            )
            candidate_ids = [sid for sid, sname in subject_ids if name_key(sname) == key]
            if len(candidate_ids) <= 1:
                continue

            canonical_id = pick_canonical(classroom_id, candidate_ids)
            summary["groups_processed"] += 1

            for sid in candidate_ids:
                if sid == canonical_id:
                    continue

                for row in TeacherAssignment.objects.filter(classroom_id=classroom_id, subject_id=sid).order_by("id"):
                    conflict = TeacherAssignment.objects.filter(
                        teacher_id=row.teacher_id,
                        classroom_id=classroom_id,
                        subject_id=canonical_id,
                    ).first()
                    if conflict:
                        row.delete()
                        summary["teacher_assignment_deleted_conflict"] += 1
                    else:
                        row.subject_id = canonical_id
                        row.save(update_fields=["subject", "updated_at"])
                        summary["teacher_assignment_remapped"] += 1

                for row in Grade.objects.filter(classroom_id=classroom_id, subject_id=sid).order_by("id"):
                    conflict = Grade.objects.filter(
                        student_id=row.student_id,
                        classroom_id=classroom_id,
                        academic_year_id=row.academic_year_id,
                        term=row.term,
                        subject_id=canonical_id,
                    ).first()
                    if conflict:
                        merge_grade(conflict, row)
                        row.delete()
                        summary["grade_deleted_conflict"] += 1
                    else:
                        row.subject_id = canonical_id
                        row.save(update_fields=["subject", "updated_at"])
                        summary["grade_remapped"] += 1

                for row in ExamPlanning.objects.filter(classroom_id=classroom_id, subject_id=sid).order_by("id"):
                    row.subject_id = canonical_id
                    row.save(update_fields=["subject", "updated_at"])
                    summary["exam_planning_remapped"] += 1
                summary["exam_planning_deleted_conflict"] += dedupe_exam_planning(classroom_id, canonical_id)

                for row in ExamResult.objects.filter(student__classroom_id=classroom_id, subject_id=sid).order_by("id"):
                    conflict = ExamResult.objects.filter(
                        session_id=row.session_id,
                        student_id=row.student_id,
                        subject_id=canonical_id,
                    ).first()
                    if conflict:
                        merge_exam_result(conflict, row)
                        row.delete()
                        summary["exam_result_deleted_conflict"] += 1
                    else:
                        row.subject_id = canonical_id
                        row.save(update_fields=["subject", "updated_at"])
                        summary["exam_result_remapped"] += 1

                has_refs = (
                    TeacherAssignment.objects.filter(subject_id=sid).exists()
                    or Grade.objects.filter(subject_id=sid).exists()
                    or ExamPlanning.objects.filter(subject_id=sid).exists()
                    or ExamResult.objects.filter(subject_id=sid).exists()
                )
                if not has_refs:
                    Subject.objects.filter(id=sid).delete()
                    summary["subject_deleted"] += 1

        after_groups = list(
            Grade.objects.values("classroom_id", "subject__name")
            .annotate(subject_count=Count("subject_id", distinct=True), grade_count=Count("id"))
            .filter(subject_count__gt=1)
        )
        summary["duplicate_groups_after"] = len(after_groups)

    print("[APPLY] classroom-based subject deduplication")
    for key in sorted(summary.keys()):
        print(f"{key}: {summary[key]}")


if __name__ == "__main__":
    main()
