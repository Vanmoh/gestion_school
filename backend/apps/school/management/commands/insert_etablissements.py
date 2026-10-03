"""Garantir les quatre ecoles reelles, et fusionner les doublons de noms.

Cette commande creait sa propre liste -- « LTOB », « LOBK », « IFP-OBK »,
« Complexe Scolaire Oumar Bah » -- differente de celle de la migration
`9999_insert_etablissements`, qui creait « Lycee Technique Oumar Bah (LTOB) »,
« Lycee Technique Oumar Bah (LOBK) », « IFP-OBK » et « Complexe Scolaire Omar
Bah (CSOB) ».

Un seul nom etait commun. Enchainer les deux creait donc **sept** lignes pour
quatre ecoles, avant que cette commande n'en fusionne trois -- d'ou une base
aux identifiants 3, 5, 7, 11 que rien n'expliquait.

Les deux lisent desormais `apps.school.etablissements_reels`. La commande ne
cree plus rien qui existe: elle reconnait chaque ligne par son code, a defaut
par son nom -- meme mal orthographie -- et fusionne les doublons dans celle qui
porte le code.

Elle ne renomme pas et ne renumerote pas: c'est
`normaliser_les_etablissements` qui s'en charge, et separer les deux evite
qu'un simple renommage puisse supprimer une ecole.
"""

from django.apps import apps
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import ForeignKey

from apps.school.etablissements_reels import ETABLISSEMENTS_REELS, code_de
from apps.school.models import Etablissement


class Command(BaseCommand):
    help = "Garantit les quatre etablissements reels et fusionne les doublons."

    def add_arguments(self, parser):
        parser.add_argument(
            "--appliquer",
            action="store_true",
            help="Ecrit les changements. Sans ce drapeau, rien n'est modifie.",
        )

    def handle(self, *args, **options):
        appliquer = options["appliquer"]

        # Range chaque ligne existante sous le code qu'elle designe. La
        # premiere rencontree qui porte deja le bon code gagne; les autres sont
        # des doublons a fusionner vers elle.
        par_code = {}
        doublons = []
        for ecole in Etablissement.objects.order_by("id"):
            code = code_de(ecole)
            if code is None:
                continue
            gardee = par_code.get(code)
            if gardee is None:
                par_code[code] = ecole
            elif (gardee.code or "").strip().upper() == code:
                doublons.append((ecole, gardee))
            else:
                # Celle qui porte le code est la reference, meme trouvee apres.
                par_code[code] = ecole
                doublons.append((gardee, ecole))

        a_creer = [
            ecole for ecole in ETABLISSEMENTS_REELS if ecole["code"] not in par_code
        ]

        for ecole in a_creer:
            self.stdout.write(f"  a creer : {ecole['code']} « {ecole['nom']} »")
        for retiree, gardee in doublons:
            self.stdout.write(
                f"  a fusionner : #{retiree.id} « {retiree.name} » "
                f"-> #{gardee.id} « {gardee.name} »"
            )
        if not a_creer and not doublons:
            self.stdout.write(
                self.style.SUCCESS(
                    f"Les {len(par_code)} ecoles reelles sont en place, sans doublon."
                )
            )
            return

        if not appliquer:
            self.stdout.write("")
            self.stdout.write(
                self.style.WARNING(
                    "Essai a blanc: rien n'a ete ecrit. Relancez avec --appliquer."
                )
            )
            return

        references = 0
        with transaction.atomic():
            for ecole in a_creer:
                Etablissement.objects.create(name=ecole["nom"], code=ecole["code"])
            for retiree, gardee in doublons:
                references += self._reporter_les_references(retiree, gardee)
                retiree.delete()

        self.stdout.write("")
        self.stdout.write(
            self.style.SUCCESS(
                f"{len(a_creer)} ecole(s) creee(s), {len(doublons)} doublon(s) "
                f"fusionne(s), {references} reference(s) reportee(s). "
                f"Total en base : {Etablissement.objects.count()}"
            )
        )

    def _reporter_les_references(self, retiree, gardee):
        """Fait suivre les vingt-six cles etrangeres avant de supprimer.

        `attname` (« etablissement_id ») et non `name`: filtrer par l'objet
        forcerait une lecture de plus par modele, pour un identifiant qu'on
        connait deja.
        """
        reportees = 0
        for modele in apps.get_models():
            for champ in modele._meta.get_fields():
                if not isinstance(champ, ForeignKey):
                    continue
                if getattr(champ.remote_field, "model", None) is not Etablissement:
                    continue
                reportees += modele.objects.filter(
                    **{champ.attname: retiree.id}
                ).update(**{champ.attname: gardee.id})
        return reportees
