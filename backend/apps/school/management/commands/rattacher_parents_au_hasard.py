"""Rattache au hasard les eleves sans parent aux parents deja enregistres.

A N'UTILISER QUE SUR DES DONNEES DE DEMONSTRATION.

Rien dans la base ne dit quel parent va avec quel eleve: cette commande ne
devine pas, elle tire au sort. Sur de vraies familles, elle donnerait a des
inconnus l'acces aux notes, aux absences et aux frais d'enfants qui ne sont
pas les leurs -- c'est pourquoi elle exige `--confirmer`, annonce ce qu'elle
va faire, et ecrit de quoi tout defaire.

Pour remplir de vraies fiches, il faut un rapprochement propose et confirme
au guichet (meme telephone, meme nom), pas un tirage.
"""

import json
import random
from datetime import datetime, timezone as fuseau_utc
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.school.models import ParentProfile, Student


class Command(BaseCommand):
    help = (
        "Rattache au hasard les eleves sans parent (donnees de demonstration "
        "uniquement)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--confirmer",
            action="store_true",
            help="Execute reellement. Sans ce drapeau, la commande se contente "
                 "d'annoncer ce qu'elle ferait.",
        )
        parser.add_argument(
            "--etablissement",
            type=int,
            default=None,
            help="Se limiter a cet etablissement.",
        )
        parser.add_argument(
            "--trace",
            default="",
            help="Fichier ou ecrire de quoi defaire (defaut: rattachements_<horodatage>.json).",
        )
        parser.add_argument(
            "--annuler",
            default="",
            help="Defait les rattachements notes dans ce fichier.",
        )

    def handle(self, *args, **options):
        if options["annuler"]:
            return self._annuler(Path(options["annuler"]))

        eleves = Student.objects.filter(parent__isnull=True, is_archived=False)
        parents = ParentProfile.objects.all()
        if options["etablissement"]:
            eleves = eleves.filter(etablissement_id=options["etablissement"])
            parents = parents.filter(etablissement_id=options["etablissement"])

        parents = list(parents)
        total = eleves.count()

        if not parents:
            raise CommandError(
                "Aucun parent enregistre: il n'y a rien a quoi rattacher."
            )
        if not total:
            self.stdout.write("Aucun eleve sans parent. Rien a faire.")
            return

        self.stdout.write(
            f"{total} eleve(s) sans parent, {len(parents)} parent(s) disponibles."
        )

        if not options["confirmer"]:
            self.stdout.write(
                self.style.WARNING(
                    "Essai a blanc: rien n'a ete ecrit. Relancez avec "
                    "--confirmer pour tirer au sort pour de bon."
                )
            )
            return

        liens = []
        with transaction.atomic():
            for eleve in eleves.select_related("user"):
                parent = random.choice(parents)
                liens.append({"eleve": eleve.id, "parent": parent.id})
                Student.objects.filter(pk=eleve.pk).update(parent=parent)

        horodatage = datetime.now(fuseau_utc.utc).strftime("%Y%m%d-%H%M%S")
        trace = Path(options["trace"] or f"rattachements_{horodatage}.json")
        trace.write_text(json.dumps(liens, indent=2), encoding="utf-8")

        self.stdout.write(
            self.style.SUCCESS(
                f"{len(liens)} eleve(s) rattache(s) au hasard. "
                f"Pour defaire: --annuler {trace}"
            )
        )

    def _annuler(self, fichier: Path):
        if not fichier.exists():
            raise CommandError(f"Fichier introuvable: {fichier}")

        liens = json.loads(fichier.read_text(encoding="utf-8"))
        with transaction.atomic():
            for lien in liens:
                # Seulement si le rattachement est toujours celui qu'on avait
                # pose: entre-temps, quelqu'un a pu corriger la fiche a la
                # main, et sa correction ne doit pas etre effacee.
                Student.objects.filter(
                    pk=lien["eleve"], parent_id=lien["parent"]
                ).update(parent=None)

        self.stdout.write(self.style.SUCCESS(f"{len(liens)} rattachement(s) defait(s)."))
