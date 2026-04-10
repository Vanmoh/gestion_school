from collections import defaultdict
from itertools import cycle

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.school.models import ClassRoom, Etablissement, Subject, Teacher, TeacherAssignment


CURRICULUM = {
    "LOBK": {
        "etablissement_aliases": [
            "LOBK",
            "Lycée Technique Oumar Bah (LOBK)",
            "Lycee Technique Oumar Bah (LOBK)",
            "Lycée Oumar Bah de Kaloum",
            "Lycee Oumar Bah de Kaloum",
        ],
        "classes": ["CG1", "CG2"],
        "subjects": [
            ("EPS", "Education Physique et Sportive (EPS)", "1"),
            ("ECM", "Education Civique et Morale (ECM)", "1"),
            ("FR_CG", "Français", "3"),
            ("HG_CG", "Histoire-Geographie (Histoire-Geo)", "2"),
            ("INFO", "Informatique", "1"),
            ("LV1", "Langue vivante 1", "2"),
            ("LV2", "Langue vivante 2", "2"),
            ("MATH_CG", "Mathématique (Math)", "3"),
            ("PC_CG", "Physique-Chimie", "2"),
            ("SVT", "SVT", "2"),
        ],
    },
    "IFP-OBK": {
        "etablissement_aliases": [
            "IFP-OBK",
            "IFP OBK",
            "Institut de Formation Professionnelle Oumar Bah",
        ],
        "classes": ["1ère Année EM1", "1ère Année EM2"],
        "subjects": [
            ("EPS", "Education Physique et Sportive (EPS)", "1"),
            ("ECM", "Education Civique et Morale (ECM)", "1"),
            ("MATH_EM", "Mathématique (Math)", "2"),
            ("PC_EM", "PC", "4"),
            ("FR_EM", "Français", "2"),
            ("TP", "TP", "5"),
            ("LABO", "LABO", "2"),
            ("HG_EM", "Histoire-Geographie (Histoire-Geo)", "2"),
            ("LANG", "Langues", "2"),
            ("DESSIN_TC", "Dessin + TC", "3"),
            ("TECHNO", "Techno", "2"),
        ],
    },
}


class Command(BaseCommand):
    help = (
        "Crée/met à jour les matières de programme et les affecte aux classes "
        "via TeacherAssignment (si des enseignants existent dans l'établissement)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Prévisualise les changements sans écrire en base.",
        )

    @staticmethod
    def _find_etablissement(aliases):
        for alias in aliases:
            match = Etablissement.objects.filter(name__iexact=alias).first()
            if match:
                return match
        for alias in aliases:
            match = Etablissement.objects.filter(name__icontains=alias).order_by("name").first()
            if match:
                return match
        return None

    @staticmethod
    def _get_or_update_subject(code, name, coefficient):
        subject, created = Subject.objects.get_or_create(
            code=code,
            defaults={"name": name, "coefficient": coefficient},
        )
        updated = False
        if subject.name != name:
            subject.name = name
            updated = True
        if str(subject.coefficient) != str(coefficient):
            subject.coefficient = coefficient
            updated = True
        if updated:
            subject.save(update_fields=["name", "coefficient"])
        return subject, created, updated

    @transaction.atomic
    def handle(self, *args, **options):
        dry_run = options["dry_run"]

        subjects_created = 0
        subjects_updated = 0
        assignments_created = 0
        assignments_existing = 0
        missing_classes = []
        skipped_no_teacher = defaultdict(list)

        self.stdout.write(self.style.WARNING("Début affectation matières -> classes..."))

        for scope_name, cfg in CURRICULUM.items():
            etablissement = self._find_etablissement(cfg["etablissement_aliases"])
            if not etablissement:
                self.stdout.write(self.style.ERROR(f"Etablissement introuvable: {scope_name}"))
                continue

            teachers = list(Teacher.objects.filter(etablissement=etablissement).order_by("id"))
            teacher_cycle = cycle(teachers) if teachers else None

            subjects = []
            for code, name, coef in cfg["subjects"]:
                subject, created, updated = self._get_or_update_subject(code=code, name=name, coefficient=coef)
                subjects.append(subject)
                if created:
                    subjects_created += 1
                elif updated:
                    subjects_updated += 1

            for class_name in cfg["classes"]:
                classroom = ClassRoom.objects.filter(
                    etablissement=etablissement,
                    name=class_name,
                ).order_by("-id").first()

                if not classroom:
                    missing_classes.append(f"{etablissement.name} -> {class_name}")
                    continue

                for subject in subjects:
                    exists = TeacherAssignment.objects.filter(
                        classroom=classroom,
                        subject=subject,
                    ).exists()
                    if exists:
                        assignments_existing += 1
                        continue

                    if not teacher_cycle:
                        skipped_no_teacher[f"{etablissement.name} / {classroom.name}"].append(subject.code)
                        continue

                    teacher = next(teacher_cycle)
                    TeacherAssignment.objects.create(
                        teacher=teacher,
                        subject=subject,
                        classroom=classroom,
                    )
                    assignments_created += 1

        if dry_run:
            transaction.set_rollback(True)
            self.stdout.write(self.style.WARNING("Dry-run activé: aucun changement persistant."))

        self.stdout.write(self.style.SUCCESS("Affectation terminée."))
        self.stdout.write(f"Matières créées: {subjects_created}")
        self.stdout.write(f"Matières mises à jour: {subjects_updated}")
        self.stdout.write(f"Affectations créées: {assignments_created}")
        self.stdout.write(f"Affectations déjà présentes: {assignments_existing}")

        if missing_classes:
            self.stdout.write(self.style.WARNING("Classes manquantes:"))
            for row in missing_classes:
                self.stdout.write(f" - {row}")

        if skipped_no_teacher:
            self.stdout.write(self.style.WARNING("Affectations ignorées (aucun enseignant dans établissement):"))
            for scope, subject_codes in skipped_no_teacher.items():
                unique_codes = sorted(set(subject_codes))
                self.stdout.write(f" - {scope}: {', '.join(unique_codes)}")
