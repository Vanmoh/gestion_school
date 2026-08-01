from __future__ import annotations

import random
from decimal import Decimal

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from apps.school.models import (
    ClassRoom,
    ExamResult,
    ExamSession,
    Grade,
    GradeValidation,
    Student,
    Subject,
    recalculate_term_ranking,
)
from apps.school.term_utils import normalize_term


class Command(BaseCommand):
    help = (
        "Seed or refresh quarterly class scores (3 homeworks) and exam scores "
        "for all active students in an etablissement."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--etab-id",
            type=int,
            required=True,
            help="Target etablissement id.",
        )
        parser.add_argument(
            "--term",
            type=str,
            default="T1",
            help="Quarterly term to seed: T1, T2 or T3.",
        )
        parser.add_argument(
            "--seed",
            type=int,
            default=20260423,
            help="Deterministic random seed.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Compute what would be written without persisting changes.",
        )
        parser.add_argument(
            "--close-term",
            action="store_true",
            help="Validate and lock the term after ranking recalculation.",
        )
        parser.add_argument(
            "--close-notes",
            type=str,
            default="Cloture automatique apres injection des notes.",
            help="Notes metadata written on term closure when --close-term is enabled.",
        )

    def _load_scope(self, etab_id: int):
        classrooms = list(
            ClassRoom.objects.filter(etablissement_id=etab_id)
            .select_related("academic_year")
            .order_by("id")
        )
        if not classrooms:
            raise CommandError(f"Aucune classe trouvée pour l'etablissement {etab_id}.")

        subjects_by_classroom: dict[int, list[Subject]] = {}
        for subject in (
            Subject.objects.filter(classroom__etablissement_id=etab_id)
            .select_related("classroom")
            .order_by("classroom_id", "id")
        ):
            subjects_by_classroom.setdefault(subject.classroom_id, []).append(subject)

        students = list(
            Student.objects.filter(
                etablissement_id=etab_id,
                is_archived=False,
                classroom__isnull=False,
            )
            .select_related("classroom", "classroom__academic_year")
            .order_by("classroom_id", "id")
        )
        return classrooms, subjects_by_classroom, students

    def _session_for(self, classroom: ClassRoom, term: str, cache: dict[int, ExamSession]) -> ExamSession:
        year = classroom.academic_year
        existing = cache.get(year.id)
        if existing is not None:
            return existing

        session = (
            ExamSession.objects.filter(academic_year=year, term=term)
            .order_by("-end_date", "-start_date", "-id")
            .first()
        )
        if session is None:
            session = ExamSession.objects.create(
                title=f"Examen {term} - {year.name}",
                term=term,
                academic_year=year,
                start_date=year.start_date,
                end_date=year.start_date,
            )

        cache[year.id] = session
        return session

    def handle(self, *args, **options):
        etab_id = int(options["etab_id"])
        term = normalize_term(options["term"])
        seed = int(options["seed"])
        dry_run = bool(options["dry_run"])
        close_term = bool(options["close_term"])
        close_notes = str(options["close_notes"] or "").strip()

        if not term:
            raise CommandError("Periode invalide. Utilisez T1, T2 ou T3.")

        classrooms, subjects_by_classroom, students = self._load_scope(etab_id)

        rng = random.Random(seed)
        session_by_year: dict[int, ExamSession] = {}
        created_grades = 0
        updated_grades = 0
        created_exam_results = 0
        updated_exam_results = 0
        eligible_pairs = 0

        with transaction.atomic():
            for student in students:
                classroom = student.classroom
                if classroom is None:
                    continue
                subjects = subjects_by_classroom.get(classroom.id, [])
                if not subjects:
                    continue
                session = self._session_for(classroom, term, session_by_year)

                for subject in subjects:
                    eligible_pairs += 1
                    homework_scores = [str(rng.randint(0, 20)) for _ in range(3)]
                    grade, created = Grade.objects.update_or_create(
                        student=student,
                        subject=subject,
                        classroom=classroom,
                        academic_year=classroom.academic_year,
                        term=term,
                        defaults={"homework_scores": homework_scores},
                    )
                    if created:
                        created_grades += 1
                    else:
                        updated_grades += 1

                    exam_score = Decimal(str(rng.randint(0, 20)))
                    exam_result = (
                        ExamResult.objects.filter(
                            student=student,
                            subject=subject,
                            session__academic_year=classroom.academic_year,
                            session__term=term,
                        )
                        .select_related("session")
                        .order_by("-session__end_date", "-session__start_date", "-created_at", "-id")
                        .first()
                    )
                    if exam_result is None:
                        ExamResult.objects.create(
                            session=session,
                            student=student,
                            subject=subject,
                            score=exam_score,
                        )
                        created_exam_results += 1
                    else:
                        exam_result.score = exam_score
                        exam_result.save(update_fields=["score", "updated_at"])
                        updated_exam_results += 1

            for classroom in classrooms:
                recalculate_term_ranking(classroom, classroom.academic_year, term)

            closed_validations = 0
            if close_term:
                for classroom in classrooms:
                    GradeValidation.objects.update_or_create(
                        classroom=classroom,
                        academic_year=classroom.academic_year,
                        term=term,
                        defaults={
                            "is_validated": True,
                            "validated_by": None,
                            "validated_at": timezone.now(),
                            "notes": close_notes,
                        },
                    )
                    closed_validations += 1

            totals = {
                "grades": Grade.objects.filter(classroom__etablissement_id=etab_id, term=term).count(),
                "exam_results": ExamResult.objects.filter(
                    student__etablissement_id=etab_id,
                    session__term=term,
                ).count(),
                "validations": GradeValidation.objects.filter(
                    classroom__etablissement_id=etab_id,
                    term=term,
                    is_validated=True,
                ).count(),
            }

            if dry_run:
                transaction.set_rollback(True)

        mode_label = "dry-run" if dry_run else "apply"
        self.stdout.write(
            str(
                {
                    "mode": mode_label,
                    "etab_id": etab_id,
                    "term": term,
                    "seed": seed,
                    "eligible_pairs": eligible_pairs,
                    "created_grades": created_grades,
                    "updated_grades": updated_grades,
                    "created_exam_results": created_exam_results,
                    "updated_exam_results": updated_exam_results,
                    "close_term": close_term,
                    "closed_validations": closed_validations if close_term else 0,
                    "totals": totals,
                    "classrooms": len(classrooms),
                }
            )
        )