"""Retirer les pointages et emargements d'enseignants qui n'enseignent rien.

Un pointage dit « cet enseignant etait la ». Un emargement dit « il a couvert
ces seances ». Les deux supposent quelque chose a assurer: quelqu'un qui ne
tient aucune matiere n'a de cours **aucun** jour, donc ni presence a constater
ni seance a couvrir.

Depuis `signals._ne_pointer_que_ceux_qui_enseignent` et son jumeau pour
l'emargement, la base refuse d'en creer. Mais les lignes anterieures a la
regle sont restees: elles faussent la charge horaire, la concordance et le
calcul de paie -- `_teacher_hours_worked` compte des heures travaillees sur des
seances qui n'existaient pas.

`controler_la_dotation` les signale sans pouvoir les corriger, et son conseil
« relancez la dotation » ne s'applique pas ici: la dotation ne connait pas ces
enseignants. Cette commande est le remede manquant.

Elle ne touche pas aux enseignants eux-memes -- `retirer_les_enseignants_sans_matiere`
s'en occupe, et c'est une decision separee: un enseignant sans matiere cette
annee peut en reprendre une la prochaine.

Sans `--appliquer`, la commande n'ecrit rien: elle montre ce qu'elle ferait.
"""

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.school.models import (
    Etablissement,
    Teacher,
    TeacherAssignment,
    TeacherAttendance,
    TeacherTimeEntry,
)


class Command(BaseCommand):
    help = (
        "Retire les pointages et emargements des enseignants sans aucune matiere."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--appliquer",
            action="store_true",
            help="Supprime les lignes. Sans ce drapeau, rien n'est modifie.",
        )
        parser.add_argument(
            "--etablissement",
            default="",
            help="Code ou nom d'une ecole a traiter seule.",
        )

    def handle(self, *args, **options):
        appliquer = options["appliquer"]
        vise = options["etablissement"].strip()

        ecoles = Etablissement.objects.order_by("id")
        if vise:
            ecoles = [
                ecole
                for ecole in ecoles
                if vise in (ecole.code or "", ecole.name)
            ]
            if not ecoles:
                self.stdout.write(self.style.ERROR(f"« {vise} » introuvable."))
                return

        total_pointages = 0
        total_emargements = 0
        a_supprimer = []

        for ecole in ecoles:
            # Un enseignant « sans matiere » est un enseignant qu'aucune
            # affectation ne nomme. `exclude(id__in=...)` et non
            # `filter(assignments__isnull=True)`: le second passe par une
            # jointure externe et compte plusieurs fois ceux qui en ont.
            sans_matiere = Teacher.objects.filter(etablissement=ecole).exclude(
                id__in=TeacherAssignment.objects.values("teacher_id")
            )
            pointages = TeacherAttendance.objects.filter(teacher__in=sans_matiere)
            emargements = TeacherTimeEntry.objects.filter(teacher__in=sans_matiere)

            combien_p = pointages.count()
            combien_m = emargements.count()
            if not (combien_p or combien_m):
                continue

            total_pointages += combien_p
            total_emargements += combien_m
            a_supprimer.append((ecole, pointages, emargements))

            self.stdout.write("")
            self.stdout.write(
                self.style.WARNING(
                    f"=== {ecole.code or ecole.name} : {combien_p} pointage(s), "
                    f"{combien_m} emargement(s) ==="
                )
            )
            for enseignant in sans_matiere.select_related("user").order_by("id"):
                p = pointages.filter(teacher=enseignant).count()
                m = emargements.filter(teacher=enseignant).count()
                if not (p or m):
                    continue
                nom = f"{enseignant.user.last_name} {enseignant.user.first_name}".strip()
                self.stdout.write(
                    f"  #{enseignant.id} {enseignant.employee_code or '-':10} "
                    f"{nom or '(sans nom)':28} {p:3} pointages, {m:3} emargements"
                )

        if not a_supprimer:
            self.stdout.write(
                self.style.SUCCESS(
                    "Aucun pointage ni emargement d'enseignant sans matiere."
                )
            )
            return

        self.stdout.write("")
        if not appliquer:
            self.stdout.write(
                self.style.WARNING(
                    f"Essai a blanc: {total_pointages} pointage(s) et "
                    f"{total_emargements} emargement(s) seraient supprimes. "
                    "Relancez avec --appliquer."
                )
            )
            return

        with transaction.atomic():
            for _, pointages, emargements in a_supprimer:
                emargements.delete()
                pointages.delete()

        self.stdout.write(
            self.style.SUCCESS(
                f"{total_pointages} pointage(s) et {total_emargements} "
                "emargement(s) supprimes."
            )
        )
