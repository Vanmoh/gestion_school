"""Reconstruit les bilans trimestriels d'annees deja cloturees.

Jusqu'a la migration 0057, `StudentAcademicHistory` ne portait pas de
periode: chaque cloture ecrasait la precedente, et il ne reste en base
qu'une seule ligne par eleve et par annee -- celle du dernier trimestre clos,
que rien ne permet d'identifier retrospectivement. Ces lignes sont donc
laissees telles quelles, sur la periode « annee entiere ».

Consequence: un bulletin ancien affiche « - » a la place de son rang, tant
que le bilan de son trimestre n'existe pas. Cette commande le recree, a
partir des notes qui sont toujours en base.

Elle recalcule aussi les moyennes selon la regle unifiee (conduite comprise,
composition comprise -- voir apps/school/moyennes.py): les bilans d'avant
avaient ete ecrits par un calcul qui ignorait la conduite, et divergeaient
donc des bulletins de la meme classe.

    manage.py recalculer_rangs --etab-id=11
    manage.py recalculer_rangs --annee=2025-2026 --terms=T1,T2 --dry-run

Sans option, elle traite toutes les annees de tous les etablissements.
"""

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Grade,
    StudentAcademicHistory,
    recalculate_term_ranking,
)
from apps.school.term_utils import TERMS, normalize_term


class Command(BaseCommand):
    help = "Recalcule les bilans et rangs par trimestre a partir des notes en base."

    def add_arguments(self, parser):
        parser.add_argument(
            "--etab-id",
            type=int,
            default=None,
            help="Limite le traitement a un etablissement.",
        )
        parser.add_argument(
            "--annee",
            type=str,
            default="",
            help="Nom de l'annee scolaire a traiter (ex. 2025-2026).",
        )
        parser.add_argument(
            "--terms",
            type=str,
            default=",".join(TERMS),
            help="Trimestres a recalculer, separes par des virgules (defaut: T1,T2,T3).",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Affiche ce qui serait recalcule, sans rien ecrire.",
        )

    def handle(self, *args, **options):
        terms = []
        for brut in str(options["terms"]).split(","):
            terme = normalize_term(brut)
            if not terme:
                raise CommandError(
                    f"Trimestre invalide: « {brut.strip()} ». Attendu: T1, T2 ou T3."
                )
            if terme not in terms:
                terms.append(terme)

        classes = ClassRoom.objects.select_related("academic_year", "etablissement")
        if options["etab_id"]:
            classes = classes.filter(etablissement_id=options["etab_id"])
        if options["annee"]:
            annees = AcademicYear.objects.filter(name=options["annee"].strip())
            if not annees.exists():
                raise CommandError(f"Aucune annee scolaire nommee « {options['annee']} ».")
            classes = classes.filter(academic_year__in=annees)

        classes = list(classes.order_by("etablissement__name", "academic_year__name", "name"))
        if not classes:
            self.stdout.write("Aucune classe ne correspond aux criteres.")
            return

        dry_run = options["dry_run"]
        traitees = 0
        ignorees = 0

        for classe in classes:
            annee = classe.academic_year
            if annee is None:
                continue

            for terme in terms:
                # Sans note, il n'y a rien a classer: recalculer poserait des
                # bilans a zero sur toute une classe, ce qui est pire que
                # l'absence de bilan.
                if not Grade.objects.filter(
                    classroom=classe, academic_year=annee, term=terme
                ).exists():
                    ignorees += 1
                    continue

                if dry_run:
                    effectif = classe.students.filter(is_archived=False).count()
                    self.stdout.write(
                        f"[simulation] {classe.name} / {annee.name} / {terme}: "
                        f"{effectif} eleve(s) a classer"
                    )
                    traitees += 1
                    continue

                with transaction.atomic():
                    recalculate_term_ranking(classe, annee, terme)
                traitees += 1
                self.stdout.write(f"{classe.name} / {annee.name} / {terme}: bilans recrees")

        total = StudentAcademicHistory.objects.exclude(
            term=StudentAcademicHistory.ANNEE_ENTIERE
        ).count()
        prefixe = "[simulation] " if dry_run else ""
        self.stdout.write(
            self.style.SUCCESS(
                f"{prefixe}{traitees} periode(s) traitee(s), {ignorees} sans note. "
                f"Bilans trimestriels en base: {total}."
            )
        )
