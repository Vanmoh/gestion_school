from __future__ import annotations

import argparse
import os
import sys
from collections import defaultdict

sys.path.insert(0, "/app")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

import django  # noqa: E402


django.setup()

from django.db import transaction  # noqa: E402
from apps.school.management.commands.deduplicate_subjects import Command  # noqa: E402
from apps.school.models import Subject  # noqa: E402


def run(apply_changes: bool) -> None:
    cmd = Command()
    summary = defaultdict(int)
    grouped = defaultdict(list)
    ambiguous_subject_ids = []

    subjects = list(Subject.objects.select_related("classroom", "classroom__etablissement").order_by("id"))
    for subject in subjects:
        key_name = cmd._name_key(subject.name)
        if not key_name:
            continue

        if subject.classroom_id is not None:
            key = ("classroom", subject.classroom_id, key_name)
        else:
            etab_ids = cmd._infer_subject_etab_ids(subject)
            if len(etab_ids) == 1:
                key = ("etab", list(etab_ids)[0], key_name)
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

    with transaction.atomic():
        for group in duplicate_groups:
            canonical = cmd._choose_canonical(group)
            for subject in group:
                if subject.id == canonical.id:
                    continue
                summary["subject_to_merge"] += 1
                cmd._remap_subject(subject, canonical, summary)

        if not apply_changes:
            transaction.set_rollback(True)

    mode = "APPLY" if apply_changes else "DRY-RUN"
    print(f"[{mode}] deduplicate_subjects")
    for key in sorted(summary.keys()):
        print(f"{key}: {summary[key]}")

    if ambiguous_subject_ids:
        sample = ", ".join(str(v) for v in ambiguous_subject_ids[:20])
        suffix = " ..." if len(ambiguous_subject_ids) > 20 else ""
        print(f"ambiguous_subject_ids({len(ambiguous_subject_ids)}): {sample}{suffix}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Persist deduplication")
    args = parser.parse_args()
    run(apply_changes=bool(args.apply))
