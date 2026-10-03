"""Donner une ecole, donc une annee, aux depenses qui n'en ont aucune.

`Expense.etablissement` est nullable. Dix depenses de la base reelle en
profitaient -- « Achat fournitures », 120 000 F chacune, du 13 au 22 avril
2026 -- et une depense sans ecole est invisible **deux fois**: absente de la
liste de chaque etablissement, et absente de chaque annee, puisque sans ecole
le rattachement a l'annee ne peut pas se deduire.

1 200 000 F de charges qu'aucun ecran ne montrait, et qu'aucune tresorerie ne
comptait.

Rien ne distingue ces dix lignes les unes des autres: meme libelle, meme
montant, meme categorie, dates consecutives. Aucune regle ne peut donc dire
laquelle appartient a quelle ecole, et la commande ne pretend pas le deviner:
elle les repartit a tour de role, chacune rattachee a l'annee active de l'ecole
qui la recoit. C'est un choix assume, pas une deduction -- `--etablissement`
permet de tout donner a une seule ecole si la comptabilite sait mieux.

Sans `--appliquer`, la commande n'ecrit rien: elle montre ce qu'elle ferait.
"""

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.school.models import AcademicYear, Etablissement, Expense


class Command(BaseCommand):
    help = "Repartit les depenses sans etablissement entre les ecoles, avec leur annee active."

    def add_arguments(self, parser):
        parser.add_argument(
            "--appliquer",
            action="store_true",
            help="Ecrit les rattachements. Sans ce drapeau, rien n'est modifie.",
        )
        parser.add_argument(
            "--etablissement",
            default="",
            help=(
                "Code ou nom d'une ecole a qui tout donner, au lieu de repartir. "
                "A utiliser quand la comptabilite sait a qui ces charges reviennent."
            ),
        )

    def handle(self, *args, **options):
        appliquer = options["appliquer"]
        vise = options["etablissement"].strip()

        orphelines = list(
            Expense.objects.filter(etablissement__isnull=True).order_by("id")
        )
        if not orphelines:
            self.stdout.write(
                self.style.SUCCESS("Aucune depense sans etablissement: rien a faire.")
            )
            return

        ecoles = self._ecoles(vise)
        if not ecoles:
            return

        total = sum(depense.amount for depense in orphelines)
        self.stdout.write(
            f"{len(orphelines)} depense(s) sans ecole, {total:,.0f} F au total, "
            f"a repartir entre {len(ecoles)} ecole(s)."
        )
        self.stdout.write("")

        plan = []
        for rang, depense in enumerate(orphelines):
            # A tour de role: rien ne distingue ces lignes, donc rien ne
            # justifierait de charger une ecole plus qu'une autre.
            ecole = ecoles[rang % len(ecoles)]
            annee = AcademicYear.courante(ecole)
            if not (annee.start_date <= depense.date <= annee.end_date):
                # La depense garde son ecole, mais pas cette annee-la: le
                # `pre_save` de `rattachement_a_l_annee` ne posera rien, et le
                # controle continuera de la signaler. C'est plus honnete que de
                # la ranger dans une annee qui ne couvre pas sa date.
                plan.append((depense, ecole, None))
                continue
            plan.append((depense, ecole, annee))

        for depense, ecole, annee in plan:
            libelle_annee = annee.name if annee is not None else "-- hors de son annee active"
            self.stdout.write(
                f"  #{depense.id} {depense.date} {depense.amount:>12,.0f} F "
                f"-> {ecole.code or ecole.name} / {libelle_annee}"
            )
        if not appliquer:
            self.stdout.write("")
            self.stdout.write(
                self.style.WARNING(
                    "Essai a blanc: rien n'a ete ecrit. Relancez avec --appliquer."
                )
            )
            return

        with transaction.atomic():
            for depense, ecole, annee in plan:
                depense.etablissement = ecole
                if annee is not None:
                    depense.academic_year = annee
                depense.save(update_fields=["etablissement", "academic_year"])

        self.stdout.write("")
        par_ecole = {}
        for _, ecole, _ in plan:
            par_ecole[ecole.code or ecole.name] = par_ecole.get(ecole.code or ecole.name, 0) + 1
        detail = ", ".join(f"{code}: {combien}" for code, combien in sorted(par_ecole.items()))
        self.stdout.write(
            self.style.SUCCESS(f"{len(plan)} depense(s) rattachee(s) -- {detail}.")
        )

    def _ecoles(self, vise):
        """Les ecoles destinataires: une seule si `--etablissement`, toutes sinon.

        Seules celles qui ont une annee active sont candidates. Une ecole sans
        annee ouverte ne peut pas recevoir une charge datee: la depense
        deviendrait visible dans sa liste mais resterait hors de toute annee --
        a moitie rangee, ce qui n'est pas mieux qu'orpheline.

        Il en existe de telles: la migration `9999_insert_etablissements` cree
        les quatre ecoles reelles, et une base neuve les porte sans annee.
        """
        toutes = list(Etablissement.objects.order_by("id"))
        avec_annee = [
            ecole for ecole in toutes if AcademicYear.courante(ecole) is not None
        ]
        ecartees = [ecole for ecole in toutes if ecole not in avec_annee]
        for ecole in ecartees:
            self.stdout.write(
                self.style.WARNING(
                    f"  « {ecole.name} » ecartee: aucune annee scolaire active."
                )
            )

        if not vise:
            if not avec_annee:
                self.stdout.write(
                    self.style.ERROR(
                        "Aucun etablissement avec une annee active: ouvrez une "
                        "annee avant de rattacher des charges."
                    )
                )
            return avec_annee

        choisie = next(
            (
                ecole
                for ecole in avec_annee
                if vise in (ecole.code or "", ecole.name)
            ),
            None,
        )
        if choisie is None:
            connues = ", ".join(f"{e.code or '?'} ({e.name})" for e in avec_annee)
            self.stdout.write(
                self.style.ERROR(
                    f"« {vise} » introuvable, ou sans annee active. "
                    f"Ecoles disponibles: {connues or 'aucune'}"
                )
            )
            return []
        return [choisie]
