"""Retirer les enseignants qui ne tiennent plus aucune matiere.

Depuis qu'une matiere ne se confie qu'a un enseignant a la fois
(`une_matiere_un_enseignant`, migration 0071), les titulaires en trop ont perdu
leur affectation. Ils restent en base sans rien enseigner: ils apparaissent dans
la liste du personnel, dans les selecteurs d'affectation, dans les campagnes de
disponibilites, et ils encombrent sans rien dire.

**Cette commande supprime des comptes et, par cascade, des ecritures.** Une
fiche de paie, un pointage, un emargement, une declaration de disponibilite:
tout pend a l'enseignant en `CASCADE`, et tout part avec lui. L'inventaire est
etabli par le collecteur de Django lui-meme -- pas par une liste ecrite a la
main qui oublierait une relation ajoutee demain.

Quatre precautions, et elles ne sont pas de trop:

- **simulation par defaut.** Rien ne s'ecrit sans `--appliquer`;
- **les comptes de la dotation seulement**, sauf `--tous`. Un enseignant saisi
  par l'ecole n'est pas un artefact de peuplement, et le distinguer evite de
  supprimer quelqu'un de reel -- la base de developpement contenait ainsi le
  compte personnel de son proprietaire parmi les sans-matiere;
- **refus quand une fiche de paie existe**, sauf `--avec-la-paie`. Une fiche de
  paie est une ecriture comptable; la faire disparaitre n'est pas une operation
  de menage;
- **`--desactiver` plutot que supprimer.** Le compte perd l'acces et sort des
  listes actives, mais son historique reste. C'est ce qu'on fait d'un enseignant
  qui s'en va, et c'est reversible.

    manage.py retirer_les_enseignants_sans_matiere
    manage.py retirer_les_enseignants_sans_matiere --desactiver --appliquer
    manage.py retirer_les_enseignants_sans_matiere --tous --avec-la-paie --appliquer
"""

import re
from collections import Counter

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models.deletion import Collector

from apps.school.models import (
    Etablissement,
    Teacher,
    TeacherAssignment,
    TeacherPayroll,
)

# Les comptes que la dotation cree: « io.prof073 », « lt.prof011 ». Un
# enseignant saisi par l'ecole ne porte pas cette forme, et c'est le seul moyen
# de les distinguer sans demander a l'utilisateur de les nommer un par un.
IDENTIFIANT_DE_LA_DOTATION = re.compile(r"^[a-z]{2,4}\.prof\d+$")


class Command(BaseCommand):
    help = "Retire les enseignants qui ne tiennent aucune matiere (simulation par defaut)."

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            default="",
            help="N'en traiter qu'un seul, par son nom. Vide = tous.",
        )
        parser.add_argument(
            "--tous",
            action="store_true",
            help=(
                "Inclure les enseignants que l'ecole a saisis, et non seulement "
                "les comptes crees par la dotation."
            ),
        )
        parser.add_argument(
            "--avec-la-paie",
            action="store_true",
            help="Retirer aussi ceux qui portent une fiche de paie.",
        )
        parser.add_argument(
            "--desactiver",
            action="store_true",
            help=(
                "Desactiver au lieu de supprimer: l'historique reste, l'acces "
                "part. Reversible."
            ),
        )
        parser.add_argument(
            "--garder",
            default="",
            help="Identifiants a epargner, separes par des virgules.",
        )
        parser.add_argument(
            "--appliquer",
            action="store_true",
            help="Executer. Sans cette option, rien n'est ecrit.",
        )
        parser.add_argument(
            "--forcer",
            action="store_true",
            help="Passe outre le refus hors developpement.",
        )

    def handle(self, *args, **options):
        appliquer = options["appliquer"]
        desactiver = options["desactiver"]
        if appliquer and not desactiver and not options["forcer"] and not settings.DEBUG:
            raise CommandError(
                "Refus: DEBUG est faux. Cette commande supprime des comptes et "
                "des ecritures. Utilisez --desactiver, ou --forcer sur une base "
                "dont vous avez une sauvegarde."
            )

        epargnes = {
            nom.strip() for nom in options["garder"].split(",") if nom.strip()
        }
        vise = options["etablissement"].strip()

        retenus, ecartes = [], []
        for etablissement in Etablissement.objects.order_by("id"):
            if vise and etablissement.name != vise:
                continue
            sans_matiere = (
                Teacher.objects.filter(etablissement=etablissement)
                .exclude(id__in=TeacherAssignment.objects.values("teacher_id"))
                .select_related("user")
                .order_by("id")
            )
            if not sans_matiere:
                continue

            self.stdout.write("")
            self.stdout.write(self.style.SUCCESS(f"=== {etablissement.name} ==="))
            for enseignant in sans_matiere:
                identifiant = enseignant.user.username if enseignant.user else ""
                paie = TeacherPayroll.objects.filter(teacher=enseignant).count()

                motif = None
                if identifiant in epargnes:
                    motif = "epargne par --garder"
                elif not options["tous"] and not IDENTIFIANT_DE_LA_DOTATION.match(
                    identifiant
                ):
                    motif = "saisi par l'ecole, pas par la dotation"
                elif paie and not options["avec_la_paie"]:
                    motif = f"{paie} fiche(s) de paie"

                if motif:
                    ecartes.append((identifiant, motif))
                    self.stdout.write(
                        f"    garde   {identifiant:26} ({motif})"
                    )
                    continue

                retenus.append(enseignant)
                self.stdout.write(
                    f"    retire  {identifiant:26} "
                    f"{enseignant.user.get_full_name() if enseignant.user else ''}"
                )

        self.stdout.write("")
        if not retenus:
            self.stdout.write(
                self.style.SUCCESS(
                    "Aucun enseignant a retirer"
                    + (f" ({len(ecartes)} garde(s))." if ecartes else ".")
                )
            )
            return

        if desactiver:
            self._desactiver(retenus, appliquer)
        else:
            self._supprimer(retenus, appliquer)

        if ecartes:
            self.stdout.write("")
            self.stdout.write(
                f"  {len(ecartes)} enseignant(s) garde(s): voir les motifs ci-dessus."
            )
        if not appliquer:
            self.stdout.write("")
            self.stdout.write(
                self.style.WARNING(
                    "Simulation: rien n'a ete ecrit. Ajoutez --appliquer pour "
                    "executer, apres avoir sauvegarde la base."
                )
            )

    # ------------------------------------------------------------------ actions

    def _desactiver(self, enseignants, appliquer):
        self.stdout.write(
            f"  {len(enseignants)} compte(s) "
            f"{'desactive(s)' if appliquer else 'seraient desactive(s)'} "
            "-- l'historique reste, l'acces part."
        )
        if not appliquer:
            return
        with transaction.atomic():
            for enseignant in enseignants:
                if enseignant.user and enseignant.user.is_active:
                    enseignant.user.is_active = False
                    enseignant.user.save(update_fields=["is_active"])
        self.stdout.write(self.style.SUCCESS("  Desactivation faite."))

    def _supprimer(self, enseignants, appliquer):
        """L'inventaire vient du collecteur de Django, pas d'une liste ecrite.

        Tout ce qui pend a un enseignant est en `CASCADE`: paie, pointages,
        emargements, disponibilites. Une liste tenue a la main oublierait la
        relation qu'on ajoutera le mois prochain; le collecteur, non.
        """
        collecteur = Collector(using="default")
        collecteur.collect([e.user for e in enseignants if e.user])
        inventaire = Counter()
        for modele, objets in collecteur.data.items():
            inventaire[modele.__name__] += len(objets)
        # `fast_deletes` **aussi**: Django y range les suppressions qu'il peut
        # faire en une requete, sans charger les objets. Les compter seulement
        # dans `data` sous-estimait l'inventaire -- la paie, les pointages et les
        # disponibilites n'y figuraient pas, alors qu'ils partaient bel et bien.
        # Un rapport qui annonce moins que ce qu'il emporte est pire qu'absent.
        for requete in collecteur.fast_deletes:
            inventaire[requete.model.__name__] += requete.count()

        verbe = "supprime(s)" if appliquer else "seraient supprime(s)"
        self.stdout.write(f"  {len(enseignants)} enseignant(s) {verbe}, et avec eux:")
        for nom, combien in sorted(
            inventaire.items(), key=lambda couple: -couple[1]
        ):
            self.stdout.write(f"    {nom:28} {combien}")

        if not appliquer:
            return
        with transaction.atomic():
            for enseignant in enseignants:
                if enseignant.user:
                    enseignant.user.delete()  # la cascade emporte la fiche
                else:
                    enseignant.delete()
        self.stdout.write(self.style.SUCCESS("  Suppression faite."))
