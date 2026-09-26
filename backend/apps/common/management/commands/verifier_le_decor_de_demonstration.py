"""Barriere avant d'enregistrer: cette base est-elle bien un decor ?

Une video de demonstration se publie. Filmer une base reelle diffuserait donc
publiquement des noms d'eleves mineurs, leurs matricules, leurs notes, leurs
incidents disciplinaires et les sommes que leurs familles doivent. Aucune
relecture humaine ne rattrape cela apres coup: la video est deja en ligne.

Cette commande s'execute **entre le peuplement et l'enregistrement**, et fait
echouer la chaine si l'un des signes suivants manque. Elle ne repare rien: elle
refuse.

Ce n'est pas la seule barriere, et ce n'est pas la premiere. Le travail
d'enregistrement tourne dans un job qui declare sa propre base jetable et ne
lit aucun secret: il n'a aucun chemin vers la production. `seed_demo_data`
refuse par ailleurs de semer hors developpement et sur une base contenant des
classes reelles. Celle-ci est la barriere que l'on peut voir echouer, et que
l'on peut donc eprouver -- un garde-fou dont on n'a jamais vu le refus n'en est
pas un.
"""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import connection

from apps.accounts.models import User
from apps.common.comptes_demo import NOMS_DES_COMPTES_DE_DEMONSTRATION
from apps.school.models import Etablissement, Student

def noms_fictifs_connus():
    """Les noms de famille que les commandes de peuplement savent produire.

    Lus **a la source**, dans les commandes elles-memes: une copie figee ici
    avait deja laisse passer quinze eleves de `seed_ltob_data` au premier essai,
    parce que sa liste de noms est plus longue que ce que j'en avais recopie. Un
    garde-fou qui derive de ce qu'il garde ne garde rien.

    Le repli sur un jeu reduit n'est pas une commodite: si une commande de
    peuplement disparait, la barriere doit **rester stricte** plutot que
    s'ouvrir. Un nom hors liste est refuse, donc une liste plus courte refuse
    davantage.
    """
    noms = set()

    try:
        from apps.school.management.commands.seed_empty_classes import NOMS

        noms.update(nom.strip().lower() for nom in NOMS)
    except Exception:
        pass

    try:
        from apps.school.management.commands.seed_ltob_data import Command as LtobCommand

        noms.update(
            nom.strip().lower() for nom in getattr(LtobCommand, "LAST_NAMES", ())
        )
    except Exception:
        pass

    # Les deux comptes eleves de `seed_demo_data`, nommes a la main.
    noms.update({"nguessan", "diallo"})
    # Les enseignants du decor, dont la liste vit dans sa propre commande.
    try:
        from apps.school.management.commands.completer_le_decor_de_demonstration import (
            NOMS as NOMS_DU_DECOR,
        )

        noms.update(nom.strip().lower() for nom in NOMS_DU_DECOR)
    except Exception:
        pass

    return frozenset(noms)


# Les prefixes des comptes que le peuplement cree en plus des comptes canoniques.
#
# `student_<classe>_<rang>_<sequence>` vient de `seed_ltob_data`, `demo.ens<n>`
# du decor, `eleve<n>` de `seed_empty_classes`.
PREFIXES_DE_DECOR = ("demo.", "student_", "eleve", "etu", "ens", "ltob", "parent")


class Command(BaseCommand):
    help = (
        "Refuse si la base n'est pas un decor de demonstration. A executer "
        "avant tout enregistrement d'ecran."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            default="Établissement Démo",
            help="Nom du seul etablissement attendu.",
        )
        parser.add_argument(
            "--sans-exiger-debug",
            action="store_true",
            help=(
                "N'exige pas DEBUG. A n'employer que pour eprouver la commande "
                "elle-meme dans la suite de tests, ou Django force DEBUG=False."
            ),
        )

    def handle(self, *args, **options):
        refus = []

        refus.extend(self._verifier_l_environnement(options["sans_exiger_debug"]))
        refus.extend(self._verifier_l_etablissement(options["etablissement"]))
        refus.extend(self._verifier_les_eleves())
        refus.extend(self._verifier_les_comptes())
        refus.extend(self._verifier_la_matiere_a_montrer())

        if refus:
            self.stderr.write(
                self.style.ERROR(
                    "Cette base n'est pas un decor de demonstration. "
                    "Enregistrement refuse."
                )
            )
            for motif in refus:
                self.stderr.write(f"  - {motif}")
            raise CommandError(
                f"{len(refus)} verification(s) en echec: rien ne sera filme."
            )

        self.stdout.write(
            self.style.SUCCESS(
                "Decor de demonstration confirme: aucune donnee reelle detectee."
            )
        )

    # ------------------------------------------------------ l'environnement

    def _verifier_l_environnement(self, sans_exiger_debug):
        motifs = []
        if not sans_exiger_debug and not settings.DEBUG:
            motifs.append(
                "DEBUG est faux: cette base se comporte comme une production."
            )

        hote = (connection.settings_dict.get("HOST") or "").strip()
        if hote and hote not in {"localhost", "127.0.0.1", "::1", "db", "postgres"}:
            motifs.append(
                f"la base repond sur « {hote} », qui n'est pas une base locale."
            )
        return motifs

    # ----------------------------------------------------- l'etablissement

    def _verifier_l_etablissement(self, nom_attendu):
        """Le controle porte sur les ecoles **qui portent des eleves**.

        Exiger un etablissement unique refusait la base de developpement pour
        rien: une migration du depot (`9999_insert_etablissements`) en insere
        quatre, vides. Ce qui compte n'est pas leur existence, c'est qu'aucun
        eleve n'appartienne a une autre ecole que le decor.
        """
        if not Etablissement.objects.exists():
            return ["aucun etablissement en base: le peuplement n'a pas tourne."]

        peuples = set(
            Student.objects.exclude(etablissement__isnull=True)
            .values_list("etablissement__name", flat=True)
            .distinct()
        )
        if not peuples:
            return []

        inattendus = sorted(peuples - {nom_attendu})
        if inattendus:
            return [
                "des eleves appartiennent a une ecole qui n'est pas le decor: "
                + ", ".join(f"« {nom} »" for nom in inattendus[:5])
            ]
        return []

    # ------------------------------------------------------------ les eleves

    def _verifier_les_eleves(self):
        """Le controle qui compte: un nom reel ne doit pas etre filme."""
        motifs = []
        eleves = Student.objects.select_related("user").all()

        if not eleves.exists():
            return ["aucun eleve en base: il n'y aurait rien a montrer."]

        sans_etablissement = eleves.filter(etablissement__isnull=True).count()
        if sans_etablissement:
            motifs.append(
                f"{sans_etablissement} eleve(s) sans etablissement: origine "
                "indeterminee."
            )

        fictifs = noms_fictifs_connus()
        suspects = []
        for eleve in eleves:
            nom = (getattr(eleve.user, "last_name", "") or "").strip().lower()
            if not nom:
                # Un eleve sans nom de famille ne revele rien, mais il n'est pas
                # non plus un decor credible.
                continue
            if nom not in fictifs:
                suspects.append(f"{eleve.matricule or eleve.id} ({nom})")

        if suspects:
            motifs.append(
                f"{len(suspects)} eleve(s) portent un nom qui n'appartient a "
                "aucune liste fictive connue, par exemple "
                + ", ".join(suspects[:3])
            )
        return motifs

    # ----------------------------------------------------------- les comptes

    def _verifier_les_comptes(self):
        """Aucun compte etranger au decor.

        Un compte de direction reel en base signifie qu'on tient une copie de
        production, meme si les eleves ont ete remplaces.

        Le controle porte d'abord sur le **nom de famille**, et seulement
        ensuite sur la forme de l'identifiant: `seed_empty_classes` nomme ses
        comptes « prenom.nom », une forme qu'aucun prefixe ne distingue d'un
        compte reel. Se fier aux prefixes refusait donc cent vingt-huit eleves
        parfaitement fictifs.
        """
        attendus = set(NOMS_DES_COMPTES_DE_DEMONSTRATION)
        fictifs = noms_fictifs_connus()
        etrangers = []

        for identifiant, nom in User.objects.values_list("username", "last_name"):
            if identifiant in attendus:
                continue
            if (nom or "").strip().lower() in fictifs:
                continue
            if identifiant.lower().startswith(PREFIXES_DE_DECOR):
                continue
            etrangers.append(identifiant)

        if etrangers:
            return [
                f"{len(etrangers)} compte(s) etrangers au decor, par exemple "
                + ", ".join(sorted(etrangers)[:3])
            ]
        return []

    # ------------------------------------------------- la matiere a montrer

    def _verifier_la_matiere_a_montrer(self):
        """Une base vide passerait tous les controles precedents.

        Elle ne diffuserait rien, mais elle produirait une video d'ecrans vides
        -- trente-cinq minutes de runner pour montrer que rien ne marche. Les
        seuils sont bas volontairement: ils disent « le peuplement a tourne »,
        pas « le decor est beau ».
        """
        from apps.school.models import (
            ClassRoom,
            Payment,
            Subject,
            TeacherAssignment,
        )

        motifs = []
        seuils = (
            ("classes", ClassRoom.objects.count(), 3),
            ("eleves", Student.objects.count(), 20),
            (
                "matieres a volume horaire",
                Subject.objects.filter(weekly_slots__gt=0).count(),
                10,
            ),
            (
                "affectations enseignant-matiere",
                TeacherAssignment.objects.count(),
                10,
            ),
            ("encaissements", Payment.objects.count(), 5),
        )
        for libelle, compte, minimum in seuils:
            if compte < minimum:
                motifs.append(
                    f"{compte} {libelle} pour un minimum de {minimum}: le "
                    "peuplement est incomplet, les ecrans seraient vides."
                )
        return motifs
