"""Une classe, une matiere: retirer les doublons laisses par d'anciens seeds.

Une base sur laquelle on a travaille des mois accumule les programmes. La classe
« 1ere Annee TC » d'IFP-OBK portait ainsi « Mathematiques » trois fois --
`MA-20`, `MATH`, `MATH_CG` --, « Anglais » deux fois et « Physique-Chimie »
trois. Vingt-huit matieres pour une dizaine de matieres reelles.

Ce n'est pas seulement inelegant. Un bulletin imprime la meme matiere trois fois
avec trois moyennes differentes; la moyenne generale la compte trois fois; et la
grille horaire, qui n'a que trente-six places par semaine, s'epuise a placer des
doublons au lieu du programme.

**Cette commande supprime des matieres et les notes qui y pendent.** Elle ne
s'exécute donc pas par defaut: sans `--appliquer`, elle se contente de dire ce
qu'elle ferait. Trois precautions de plus:

- elle **ne touche qu'aux classes des listes de `insert_classes`**, sur l'annee
  active. Une classe d'essai ou l'annee suivante ne sont pas son affaire;
- elle **garde la matiere du programme** -- celle que
  `doter_les_etablissements_reels` gere, reconnaissable a son code suffixe --
  parce que c'est la seule dont tous les eleves ont les notes. Ecarter celle-la
  laisserait des eleves sans moyenne;
- elle **ne supprime jamais une matiere seule de son nom**. Sans doublon, il n'y
  a rien a fusionner, et une matiere isolee n'est pas un desordre.

    manage.py fusionner_les_matieres_en_double
    manage.py fusionner_les_matieres_en_double --etablissement "IFP-OBK" --appliquer
"""

import re
import unicodedata
from collections import defaultdict

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.school.management.commands.doter_les_etablissements_reels import (
    Command as CommandeDeDotation,
)
from apps.school.management.commands.insert_classes import ESTABLISSEMENT_CLASSES
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    ExamResult,
    Grade,
    Subject,
    TeacherAssignment,
    TeacherScheduleSlot,
)


def cle_de_matiere(nom):
    """Rapprocher « Mathematique (Math) », « Mathematiques » et « MATH ».

    Les accents tombent, les parentheses aussi -- elles ne portent qu'un rappel
    du sigle --, les mots courts sont ecartes, et le pluriel ne compte pas. Ce
    qui reste est un ensemble de mots, insensible a l'ordre: « Histoire-Geo » et
    « Geographie-Histoire » se rejoignent, ce qui est voulu.
    """
    sans_accent = "".join(
        caractere
        for caractere in unicodedata.normalize("NFD", nom)
        if unicodedata.category(caractere) != "Mn"
    )
    sans_parenthese = re.sub(r"\(.*?\)", " ", sans_accent).lower()
    mots = re.findall(r"[a-z]+", sans_parenthese)
    retenus = {mot.rstrip("s") for mot in mots if len(mot) > 2}
    return tuple(sorted(retenus)) or (sans_parenthese.strip(),)


class Command(BaseCommand):
    help = "Fusionne les matieres en double d'une meme classe (simulation par defaut)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            default="",
            help="N'en traiter qu'un seul, par son nom. Vide = tous.",
        )
        parser.add_argument(
            "--appliquer",
            action="store_true",
            help="Supprimer reellement. Sans cette option, rien n'est ecrit.",
        )
        parser.add_argument(
            "--forcer",
            action="store_true",
            help="Passe outre le refus hors developpement.",
        )

    def handle(self, *args, **options):
        appliquer = options["appliquer"]
        if appliquer and not options["forcer"] and not settings.DEBUG:
            raise CommandError(
                "Refus: DEBUG est faux. Cette commande supprime des notes. "
                "Utilisez --forcer sur une base dont vous avez une sauvegarde."
            )

        vise = options["etablissement"].strip()
        dotation = CommandeDeDotation()
        bilan = defaultdict(int)

        for etablissement in Etablissement.objects.order_by("id"):
            if vise and etablissement.name != vise:
                continue
            noms = dotation._classes_de(etablissement, ESTABLISSEMENT_CLASSES)
            if noms is None:
                continue
            annee = AcademicYear.objects.filter(
                etablissement=etablissement, is_active=True
            ).first()
            if annee is None:
                continue

            classes = ClassRoom.objects.filter(
                etablissement=etablissement,
                academic_year=annee,
                name__in=list(noms),
            ).order_by("name")
            if not classes.exists():
                continue

            self.stdout.write("")
            self.stdout.write(self.style.SUCCESS(f"=== {etablissement.name} ==="))
            self._traiter(classes, appliquer, bilan)

        self.stdout.write("")
        if not bilan["doublons"]:
            self.stdout.write(
                self.style.SUCCESS("Aucune matiere en double: rien a fusionner.")
            )
            return

        verbe = "supprimees" if appliquer else "seraient supprimees"
        self.stdout.write(
            f"  {bilan['doublons']} matieres {verbe}, et avec elles:"
        )
        self.stdout.write(f"    notes                 {bilan['notes']}")
        self.stdout.write(f"    resultats d'examen    {bilan['resultats']}")
        self.stdout.write(f"    epreuves planifiees   {bilan['epreuves']}")
        self.stdout.write(f"    affectations          {bilan['affectations']}")
        self.stdout.write(f"    creneaux d'horaire    {bilan['creneaux']}")
        self.stdout.write("")
        mot = "reprises" if appliquer else "seraient reprises"
        combien = bilan["deplacees"] if appliquer else bilan["reprises"]
        self.stdout.write(
            f"  dont {combien} notes et resultats {mot} sur la matiere gardee "
            "-- aucun eleve ne perd sa seule note."
        )
        self.stdout.write("")
        if appliquer:
            self.stdout.write(
                self.style.SUCCESS(
                    "Fusion appliquee. Relancez « doter_les_etablissements_reels » "
                    "pour que la grille horaire reprenne la place liberee."
                )
            )
        else:
            self.stdout.write(
                self.style.WARNING(
                    "Simulation: rien n'a ete ecrit. Ajoutez --appliquer pour "
                    "executer, apres avoir sauvegarde la base."
                )
            )

    # ------------------------------------------------------------------ detail

    def _traiter(self, classes, appliquer, bilan):
        for classe in classes:
            groupes = defaultdict(list)
            for matiere in Subject.objects.filter(classroom=classe).order_by("pk"):
                groupes[cle_de_matiere(matiere.name)].append(matiere)

            a_retirer = []
            for groupe in groupes.values():
                if len(groupe) < 2:
                    continue  # une matiere seule de son nom n'est pas un doublon
                gardee = self._celle_qu_on_garde(groupe, classe)
                for matiere in groupe:
                    if matiere.pk != gardee.pk:
                        a_retirer.append((gardee, matiere))

            if not a_retirer:
                continue

            self.stdout.write(f"  {classe.name}")
            for gardee, retiree in a_retirer:
                compte = self._ce_qui_pend(retiree, gardee)
                self.stdout.write(
                    f"    « {retiree.name} » ({retiree.code}) -> "
                    f"« {gardee.name} » ({gardee.code}) "
                    f"[{compte['notes']} notes, {compte['creneaux']} creneaux]"
                )
                bilan["doublons"] += 1
                for champ, valeur in compte.items():
                    bilan[champ] += valeur
                bilan["reprises"] += compte.pop("reprises_prevues", 0)
                if appliquer:
                    bilan["deplacees"] += self._fusionner(gardee, retiree)

    @staticmethod
    def _celle_qu_on_garde(groupe, classe):
        """Celle du programme d'abord, la mieux notee ensuite.

        Le code des matieres posees par la dotation finit par `-<id de la
        classe>`: c'est la seule dont **tous** les eleves ont les notes, aux
        trois trimestres. La garder est donc la seule facon de ne laisser aucun
        eleve sans moyenne dans cette matiere.
        """
        suffixe = f"-{classe.id}"
        du_programme = [m for m in groupe if (m.code or "").endswith(suffixe)]
        if du_programme:
            return du_programme[0]
        return max(
            groupe,
            key=lambda m: (Grade.objects.filter(subject=m).count(), -m.pk),
        )

    @staticmethod
    def _ce_qui_pend(matiere, gardee=None):
        compte = {
            "notes": Grade.objects.filter(subject=matiere).count(),
            "resultats": ExamResult.objects.filter(subject=matiere).count(),
            "epreuves": ExamPlanning.objects.filter(subject=matiere).count(),
            "affectations": TeacherAssignment.objects.filter(subject=matiere).count(),
            "creneaux": TeacherScheduleSlot.objects.filter(
                assignment__subject=matiere
            ).count(),
        }
        if gardee is not None:
            # Ce qui serait deplace plutot que supprime: la simulation doit le
            # dire, sinon elle annonce une perte qui n'aura pas lieu.
            deja = set(
                Grade.objects.filter(subject=gardee).values_list(
                    "student_id", "term"
                )
            )
            sans_equivalent = sum(
                1
                for couple in Grade.objects.filter(subject=matiere).values_list(
                    "student_id", "term"
                )
                if couple not in deja
            )
            reportables = (
                ExamResult.objects.filter(subject=matiere)
                .exclude(planning__subject=matiere)
                .count()
            )
            compte["reprises_prevues"] = sans_equivalent + reportables
        return compte

    @staticmethod
    @transaction.atomic
    def _fusionner(gardee, retiree):
        """Deplacer ce qui n'a pas d'equivalent, supprimer le reste.

        Une suppression seche perdait cent vingt-six notes sans filet: des eleves
        n'avaient de moyenne dans cette matiere que sur le doublon, et se
        retrouvaient sans rien. Fusionner veut donc dire **deplacer d'abord**.

        L'unicite d'une note porte sur (eleve, matiere, classe, annee,
        trimestre). Une note du doublon se reporte donc sur la matiere gardee
        tant que celle-ci n'en a pas deja une pour le meme eleve et le meme
        trimestre. Quand elle en a une, c'est la sienne qui fait foi -- elle
        couvre tous les eleves, ce qui est la raison pour laquelle on la garde.

        L'ordre de suppression compte ensuite: `TeacherAssignment`, `Grade`,
        `ExamPlanning` et `ExamResult` protegent tous `Subject`. On descend du
        plus dependant au moins dependant, dans une transaction, pour ne jamais
        laisser la base a moitie defaite.
        """
        deplacees = 0

        # 1. Les notes qui n'ont pas d'equivalent sur la matiere gardee.
        deja = set(
            Grade.objects.filter(subject=gardee).values_list("student_id", "term")
        )
        for note in Grade.objects.filter(subject=retiree):
            if (note.student_id, note.term) in deja:
                continue
            Grade.objects.filter(pk=note.pk).update(subject=gardee)
            deja.add((note.student_id, note.term))
            deplacees += 1

        # 2. Les resultats d'examen suivent leur epreuve, qui appartient a une
        #    autre matiere: seul leur libelle de matiere change. L'unicite porte
        #    sur (epreuve, eleve), que ce report ne touche pas.
        reportes = ExamResult.objects.filter(subject=retiree).exclude(
            planning__subject=retiree
        )
        deplacees += reportes.update(subject=gardee)

        # 3. Ce qui reste part, du plus dependant au moins dependant.
        epreuves = ExamPlanning.objects.filter(subject=retiree)
        # `ExamResult` est en RESTRICT sur l'epreuve: il part avant elle.
        ExamResult.objects.filter(planning__in=epreuves).delete()
        ExamResult.objects.filter(subject=retiree).delete()
        ExamInvigilation.objects.filter(planning__in=epreuves).delete()
        epreuves.delete()
        Grade.objects.filter(subject=retiree).delete()
        # Les creneaux tombent en cascade avec l'affectation.
        TeacherAssignment.objects.filter(subject=retiree).delete()
        retiree.delete()
        return deplacees
