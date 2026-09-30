"""Remettre les quatre ecoles au nom, au code et au numero qui leur reviennent.

Trois descriptions concurrentes des memes quatre ecoles ont laisse une base
dans cet etat:

- « LYCCE OBK », saisi a la main, qu'aucune liste ne reconnaissait --
  `controler_la_dotation` repondait « hors des listes de classes, non
  controlee », et cette ecole n'a donc jamais ete verifiee;
- des identifiants 3, 5, 7 et 11 pour quatre ecoles, trace de sept lignes
  creees puis fusionnees (voir `etablissements_reels`).

La commande fait deux choses, et rien d'autre:

1. **Le nom et le code.** Chaque ecole est reconnue par son code, a defaut par
   son nom -- meme mal orthographie -- puis renommee au nom canonique, qui
   porte son sigle entre parentheses. Le code n'est pose que s'il manque:
   il compose les matricules deja distribues et ne doit jamais changer.

2. **La numerotation.** Les identifiants deviennent 1, 2, 3, 4 dans l'ordre de
   `ETABLISSEMENTS_REELS`. Vingt-six cles etrangeres et vingt-trois mille
   lignes suivent, en une seule transaction: Django cree ses contraintes
   `DEFERRABLE INITIALLY DEFERRED` sur PostgreSQL, donc elles ne sont
   verifiees qu'au commit -- une ecole peut porter momentanement le numero
   d'une autre.

**Ce que la renumerotation casse:** l'application garde l'ecole choisie en
cache et l'envoie dans `X-Etablissement-Id`. Apres renumerotation, ce cache
designe une autre ecole ou aucune. Chaque utilisateur doit rechoisir son
etablissement -- une fois. C'est la raison de `--renumeroter`, qui n'est pas
active par defaut.

Sans `--appliquer`, la commande n'ecrit rien.
"""

from django.core.management.base import BaseCommand
from django.db import connection, transaction

from apps.school.etablissements_reels import ETABLISSEMENTS_REELS, PAR_CODE, code_de
from apps.school.models import Etablissement


class Command(BaseCommand):
    help = "Normalise noms, codes et identifiants des quatre etablissements reels."

    def add_arguments(self, parser):
        parser.add_argument(
            "--appliquer",
            action="store_true",
            help="Ecrit les changements. Sans ce drapeau, rien n'est modifie.",
        )
        parser.add_argument(
            "--renumeroter",
            action="store_true",
            help=(
                "Renumerote les etablissements en 1..4. Oblige chaque "
                "utilisateur a rechoisir son ecole une fois."
            ),
        )

    def handle(self, *args, **options):
        appliquer = options["appliquer"]
        renumeroter = options["renumeroter"]

        toutes = list(Etablissement.objects.order_by("id"))
        if not toutes:
            self.stdout.write(self.style.WARNING("Aucun etablissement en base."))
            return

        reconnues, inconnues = self._reconnaitre(toutes)
        self._montrer(reconnues, inconnues)

        renommages = [
            (ecole, PAR_CODE[code])
            for code, ecole in reconnues.items()
            if ecole.name != PAR_CODE[code]["nom"] or not (ecole.code or "").strip()
        ]

        plan_numeros = self._plan_de_numerotation(reconnues) if renumeroter else []

        if not renommages and not plan_numeros:
            self.stdout.write("")
            self.stdout.write(self.style.SUCCESS("Rien a corriger."))
            return

        self.stdout.write("")
        for ecole, canonique in renommages:
            quoi = []
            if ecole.name != canonique["nom"]:
                quoi.append(f"nom « {ecole.name} » -> « {canonique['nom']} »")
            if not (ecole.code or "").strip():
                quoi.append(f"code -> {canonique['code']}")
            self.stdout.write(f"  #{ecole.id} " + ", ".join(quoi))
        for ecole, nouveau in plan_numeros:
            self.stdout.write(f"  #{ecole.id} -> #{nouveau}  ({ecole.name})")

        if not appliquer:
            self.stdout.write("")
            self.stdout.write(
                self.style.WARNING(
                    "Essai a blanc: rien n'a ete ecrit. Relancez avec --appliquer"
                    + (" --renumeroter." if renumeroter else ".")
                )
            )
            return

        with transaction.atomic():
            for ecole, canonique in renommages:
                ecole.name = canonique["nom"]
                if not (ecole.code or "").strip():
                    ecole.code = canonique["code"]
                ecole.save(update_fields=["name", "code"])
            if plan_numeros:
                self._renumeroter(plan_numeros)

        self.stdout.write("")
        self.stdout.write(
            self.style.SUCCESS(
                f"{len(renommages)} renommage(s), {len(plan_numeros)} "
                "renumerotation(s) appliquee(s)."
            )
        )
        if plan_numeros:
            self.stdout.write(
                self.style.WARNING(
                    "Chaque utilisateur doit rechoisir son etablissement: "
                    "l'application garde l'ancien numero en cache."
                )
            )

    # --------------------------------------------------------------- lecture

    def _reconnaitre(self, toutes):
        """Range chaque ligne sous son code canonique.

        Un doublon -- deux lignes pour la meme ecole -- n'est pas traite ici:
        c'est `insert_etablissements` qui fusionne, et melanger les deux
        responsabilites ferait qu'un simple renommage pourrait supprimer une
        ecole.
        """
        reconnues = {}
        inconnues = []
        for ecole in toutes:
            code = code_de(ecole)
            if code is None:
                inconnues.append(ecole)
            elif code in reconnues:
                inconnues.append(ecole)
            else:
                reconnues[code] = ecole
        return reconnues, inconnues

    def _montrer(self, reconnues, inconnues):
        self.stdout.write("=== etat actuel ===")
        for ecole in sorted(reconnues.values(), key=lambda e: e.id):
            code = code_de(ecole)
            self.stdout.write(
                f"  #{ecole.id:<4} {ecole.code or '-':4} {ecole.name!r} "
                f"-> reconnue comme {code}"
            )
        for ecole in inconnues:
            self.stdout.write(
                self.style.WARNING(
                    f"  #{ecole.id:<4} {ecole.code or '-':4} {ecole.name!r} "
                    "-> non reconnue (doublon, ou ecole hors des quatre reelles): "
                    "laissee telle quelle"
                )
            )

    def _plan_de_numerotation(self, reconnues):
        """Les deplacements a faire, dans l'ordre de `ETABLISSEMENTS_REELS`."""
        plan = []
        for rang, canonique in enumerate(ETABLISSEMENTS_REELS, start=1):
            ecole = reconnues.get(canonique["code"])
            if ecole is not None and ecole.id != rang:
                plan.append((ecole, rang))
        return plan

    # --------------------------------------------------------------- ecriture

    def _renumeroter(self, plan):
        """Deplace les identifiants, et avec eux toutes les references.

        En deux temps, par un intervalle libre: passer directement #7 a #1
        echouerait si #1 est occupe par une ecole qui doit elle-meme bouger.
        On eloigne donc tout le monde, puis on redescend chacun a sa place.

        `filter(...).update(...)` et non `instance.save()`: modifier la cle
        primaire puis sauver **insere** une ligne de plus au lieu de deplacer
        celle qui existe. Et `id=` et non `pk=`: `update()` ne connait pas
        l'alias `pk` et leve `KeyError`.
        """
        libre = (
            Etablissement.objects.order_by("-id").values_list("id", flat=True).first()
            or 0
        ) + 1000

        etapes = [(ecole.id, libre + rang) for rang, (ecole, _) in enumerate(plan)]

        # `constraint_checks_disabled` et non la seule transaction: PostgreSQL
        # differe ses contraintes jusqu'au commit, mais SQLite les verifie a
        # chaque instruction et refuserait le premier deplacement. C'est l'API
        # que Django prevoit pour ce genre de chirurgie, et `check_constraints`
        # verifie ensuite que rien ne pend dans le vide.
        with connection.constraint_checks_disabled():
            for ancien, provisoire in etapes:
                self._deplacer(ancien, provisoire)
            for (_, provisoire), (_, definitif) in zip(etapes, plan):
                self._deplacer(provisoire, definitif)
        connection.check_constraints()

        self._recaler_la_sequence()

    def _deplacer(self, ancien, nouveau):
        from django.apps import apps as registre
        from django.db.models import ForeignKey

        Etablissement.objects.filter(id=ancien).update(id=nouveau)
        for modele in registre.get_models():
            for champ in modele._meta.get_fields():
                if not isinstance(champ, ForeignKey):
                    continue
                if getattr(champ.remote_field, "model", None) is not Etablissement:
                    continue
                # `attname` (« etablissement_id ») et non `name`: filtrer par
                # l'objet forcerait une lecture de l'etablissement, qui porte
                # justement un identifiant en train de changer.
                modele.objects.filter(**{champ.attname: ancien}).update(
                    **{champ.attname: nouveau}
                )

    def _recaler_la_sequence(self):
        """Le prochain identifiant doit suivre le dernier, et non les anciens.

        Sans cela, la sequence PostgreSQL pointe toujours au-dela de #11 et la
        cinquieme ecole creee porterait #12 -- les trous reviendraient aussitot.
        """
        if connection.vendor != "postgresql":
            return
        table = Etablissement._meta.db_table
        with connection.cursor() as curseur:
            curseur.execute(
                "SELECT setval(pg_get_serial_sequence(%s, 'id'), "
                "COALESCE((SELECT MAX(id) FROM " + table + "), 1))",
                [table],
            )
