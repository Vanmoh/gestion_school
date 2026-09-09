"""Donne un programme aux classes qui n'en ont aucun.

Une classe sans matiere est un angle mort: elle apparait partout -- listes,
effectifs, emploi du temps -- mais aucune note ne peut y etre saisie, aucun
bulletin edite. Les ecrans la montrent pleine d'eleves et vide de contenu,
sans que rien n'explique pourquoi.

Le programme n'est pas invente: il est copie sur une classe du meme
etablissement qui en possede un. Deux classes d'un meme etablissement suivent
le meme tronc commun, et une liste de matieres tiree d'ailleurs -- ou pire,
ecrite en dur ici -- ferait apparaitre des enseignements que l'ecole ne donne
pas. A defaut de modele dans l'etablissement, la classe est laissee telle
quelle et signalee: mieux vaut une classe visiblement vide qu'un programme
emprunte a une autre ecole.

Ce qu'elle ne sait pas faire, et qu'il faut relire apres coup: le niveau
n'entre pas en ligne de compte. Une Terminale demunie recoit le programme de
la classe la mieux pourvue de l'etablissement, fut-ce une 6e. C'est sans
consequence la ou le tronc commun est reel, et faux ailleurs -- d'ou le
--dry-run, et la relecture par la direction avant toute saisie de notes.
Voir apps/school/tests/test_doter_les_classes.py, qui fixe ce comportement.
"""

from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count

from apps.school.models import ClassRoom, Etablissement, Subject


class Command(BaseCommand):
    help = (
        "Copie le programme d'une classe pourvue sur les classes du meme "
        "etablissement qui n'ont aucune matiere."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--etab-id",
            type=int,
            default=None,
            help="Restreindre a un etablissement. Par defaut: tous.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Enumerer ce qui serait cree, sans rien ecrire.",
        )

    def handle(self, *args, **options):
        etablissements = Etablissement.objects.all().order_by("id")
        if options["etab_id"]:
            etablissements = etablissements.filter(id=options["etab_id"])

        total_matieres = 0
        total_classes = 0
        laissees = []

        for etablissement in etablissements:
            classes = ClassRoom.objects.filter(
                etablissement=etablissement
            ).annotate(combien=Count("subjects"))

            demunies = [c for c in classes if c.combien == 0]
            if not demunies:
                continue

            # Le modele: la classe la mieux pourvue de l'etablissement. La
            # mieux pourvue et non la premiere venue -- une classe qui ne
            # porte qu'une matiere resterait un mauvais patron.
            modele = max(
                (c for c in classes if c.combien > 0),
                key=lambda c: c.combien,
                default=None,
            )
            if modele is None:
                laissees.append(
                    f"{etablissement.name}: {len(demunies)} classes, "
                    "aucun programme a copier dans cet etablissement"
                )
                continue

            programme = list(Subject.objects.filter(classroom=modele))
            self.stdout.write(
                f"[{etablissement.id}] {etablissement.name}: "
                f"{len(demunies)} classes a doter, "
                f"{len(programme)} matieres copiees de « {modele.name} »"
            )

            if options["dry_run"]:
                total_classes += len(demunies)
                total_matieres += len(demunies) * len(programme)
                continue

            with transaction.atomic():
                for classe in demunies:
                    for matiere in programme:
                        # `get_or_create` et non `create`: la contrainte
                        # d'unicite (classe, code) ferait echouer toute la
                        # transaction sur un doublon, et perdre le travail
                        # deja fait pour les autres classes.
                        Subject.objects.get_or_create(
                            classroom=classe,
                            code=matiere.code,
                            defaults={
                                "name": matiere.name,
                                "coefficient": matiere.coefficient,
                                "weekly_slots": matiere.weekly_slots,
                            },
                        )
                        total_matieres += 1
                    total_classes += 1

        verbe = "seraient creees" if options["dry_run"] else "creees"
        self.stdout.write(
            self.style.SUCCESS(
                f"{total_matieres} matieres {verbe} sur {total_classes} classes."
            )
        )
        for message in laissees:
            self.stdout.write(self.style.WARNING(f"Laissee en l'etat -- {message}"))
