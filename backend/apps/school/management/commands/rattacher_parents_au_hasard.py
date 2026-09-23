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
import re
from datetime import datetime, timezone as fuseau_utc
from pathlib import Path

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from django.contrib.auth import get_user_model

from apps.school.admission import identifiant_du_parent
from apps.school.models import ParentProfile, Student

User = get_user_model()

# De quoi peupler une demonstration avec des noms d'ici plutot que
# « Parent 1 », « Parent 2 ».
_NOMS = [
    "Traore", "Diarra", "Keita", "Coulibaly", "Sissoko", "Konate", "Diallo",
    "Toure", "Sangare", "Camara", "Dembele", "Doumbia", "Maiga", "Cisse",
    "Sidibe", "Kone", "Bagayoko", "Fofana", "Samake", "Berthe",
]
_PRENOMS = [
    "Amadou", "Fanta", "Moussa", "Aminata", "Ibrahim", "Kadiatou", "Seydou",
    "Mariam", "Oumar", "Fatoumata", "Bakary", "Awa", "Modibo", "Rokia",
    "Souleymane", "Assitan", "Adama", "Djeneba", "Cheick", "Salimata",
]


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
            "--creer-des-parents",
            action="store_true",
            help="Cree assez de parents fictifs pour que chacun ait deux ou "
                 "trois enfants. Sans cela, six parents se partagent six cent "
                 "eleves et aucun ecran n'est testable.",
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

        parents_crees = []
        if options["creer_des_parents"] and total:
            # Deux ou trois enfants par famille: c'est ce qui rend les ecrans
            # lisibles. Six parents pour six cents eleves donneraient cent
            # enfants chacun, et « 107 enfants deja rattaches » ne teste rien.
            manquants = max(0, (total // 3) + 1 - len(parents))
            if manquants and options["confirmer"]:
                parents_crees = self._creer_des_parents(
                    manquants, eleves, options["etablissement"]
                )
                parents.extend(parents_crees)
                self.stdout.write(f"{len(parents_crees)} parent(s) fictif(s) cree(s).")
            elif manquants:
                self.stdout.write(
                    f"{manquants} parent(s) fictif(s) seraient crees."
                )

        if not parents:
            raise CommandError(
                "Aucun parent enregistre: il n'y a rien a quoi rattacher. "
                "Ajoutez --creer-des-parents pour peupler une demonstration."
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
        trace.write_text(
            json.dumps(
                {
                    "liens": liens,
                    # Les comptes inventes: sans eux dans la trace, defaire
                    # les rattachements laisserait des parents fantomes.
                    "parents_crees": [p.id for p in parents_crees],
                },
                indent=2,
            ),
            encoding="utf-8",
        )

        self.stdout.write(
            self.style.SUCCESS(
                f"{len(liens)} eleve(s) rattache(s) au hasard. "
                f"Pour defaire: --annuler {trace}"
            )
        )

    def _creer_des_parents(self, combien, eleves, etablissement_id):
        """Des familles credibles, reparties comme les eleves.

        Le parent doit appartenir au meme etablissement que ses enfants,
        sinon les ecrans le filtrent et il devient invisible la ou on le
        cherche.
        """
        etablissements = list(
            eleves.values_list("etablissement_id", flat=True).distinct()
        )
        etablissements = [e for e in etablissements if e] or [etablissement_id]

        crees = []
        for rang in range(combien):
            prenom = random.choice(_PRENOMS)
            nom = random.choice(_NOMS)
            # Un numero malien plausible, et faux: 7X 12 34 56 n'appartient a
            # personne dans une base de demonstration.
            telephone = f"7{random.randint(0, 9)} {random.randint(10, 99)} "
            telephone += f"{random.randint(10, 99)} {random.randint(10, 99)}"

            compte = User(
                username=identifiant_du_parent(telephone, nom, prenom),
                first_name=prenom,
                last_name=nom,
                phone=telephone,
                role="parent",
                etablissement_id=etablissements[rang % len(etablissements)],
                doit_changer_mot_de_passe=True,
            )
            compte.set_password(re.sub(r"\D", "", telephone))
            compte.save()

            crees.append(
                ParentProfile.objects.create(
                    user=compte, etablissement_id=compte.etablissement_id
                )
            )
        return crees

    def _annuler(self, fichier: Path):
        if not fichier.exists():
            raise CommandError(f"Fichier introuvable: {fichier}")

        contenu = json.loads(fichier.read_text(encoding="utf-8"))
        # Une trace ecrite avant l'option --creer-des-parents est une simple
        # liste: les deux formes se lisent.
        if isinstance(contenu, list):
            liens, parents_crees = contenu, []
        else:
            liens = contenu.get("liens", [])
            parents_crees = contenu.get("parents_crees", [])

        with transaction.atomic():
            for lien in liens:
                # Seulement si le rattachement est toujours celui qu'on avait
                # pose: entre-temps, quelqu'un a pu corriger la fiche a la
                # main, et sa correction ne doit pas etre effacee.
                Student.objects.filter(
                    pk=lien["eleve"], parent_id=lien["parent"]
                ).update(parent=None)

            if parents_crees:
                profils = ParentProfile.objects.filter(id__in=parents_crees)
                comptes = list(profils.values_list("user_id", flat=True))
                profils.delete()
                User.objects.filter(id__in=comptes).delete()

        self.stdout.write(
            self.style.SUCCESS(
                f"{len(liens)} rattachement(s) defait(s), "
                f"{len(parents_crees)} parent(s) fictif(s) supprime(s)."
            )
        )
