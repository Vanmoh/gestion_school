import json
import os
import random
import sys
import unicodedata
from pathlib import Path

import django
from django.db.models import Count


os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))
django.setup()

from apps.school.models import ClassRoom, Grade, Subject  # noqa: E402


def normalize(text: str) -> str:
    text = text or ""
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    return "".join(text.lower().split())


def main() -> None:
    target_names = {"1ereanneeem1"}
    term = "T1"

    classes = list(
        ClassRoom.objects.select_related("academic_year")
        .annotate(
            student_count=Count("students", distinct=True),
            subject_count=Count("teacher_assignments__subject", distinct=True),
        )
        .order_by("id")
    )

    matched = [c for c in classes if normalize(c.name) in target_names]
    fallback_used = False

    if not any(c.student_count > 0 for c in matched):
        fallback_used = True
        matched = [
            c
            for c in classes
            if "em1" in normalize(c.name)
            and normalize(c.name).startswith("1")
            and c.student_count > 0
        ]

    summary = {
        "fallback_used": fallback_used,
        "target_classes": [],
        "grades_created": 0,
        "grades_updated": 0,
        "total_pairs": 0,
        "skipped": [],
        "samples": [],
    }

    for classroom in matched:
        students = list(classroom.students.all())
        if not students:
            summary["skipped"].append(
                {
                    "class_id": classroom.id,
                    "class_name": classroom.name,
                    "reason": "no_students",
                }
            )
            continue

        subjects = list(
            Subject.objects.filter(teacher_assignments__classroom=classroom)
            .distinct()
            .order_by("id")
        )

        if not subjects:
            subjects = list(Subject.objects.all().order_by("id"))

        if not subjects:
            summary["skipped"].append(
                {
                    "class_id": classroom.id,
                    "class_name": classroom.name,
                    "reason": "no_subjects",
                }
            )
            continue

        summary["target_classes"].append(
            {
                "class_id": classroom.id,
                "class_name": classroom.name,
                "academic_year": getattr(classroom.academic_year, "name", None),
                "student_count": len(students),
                "subject_count": len(subjects),
            }
        )

        for student in students:
            for subject in subjects:
                value = random.randint(10, 19)
                grade, created = Grade.objects.update_or_create(
                    student=student,
                    subject=subject,
                    classroom=classroom,
                    academic_year=classroom.academic_year,
                    term=term,
                    defaults={
                        "value": value,
                        "homework_scores": [value],
                    },
                )

                summary["total_pairs"] += 1
                if created:
                    summary["grades_created"] += 1
                else:
                    summary["grades_updated"] += 1

                if len(summary["samples"]) < 10:
                    summary["samples"].append(
                        {
                            "grade_id": grade.id,
                            "class_id": classroom.id,
                            "student_id": student.id,
                            "subject_id": subject.id,
                            "value": float(grade.value),
                        }
                    )

    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
