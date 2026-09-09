"""Retire de la base les comptes de demonstration.

Leur mot de passe est ecrit dans le depot: tant qu'ils existent ailleurs
qu'en developpement, n'importe qui peut se connecter en super-utilisateur.
Le controle de deploiement W005 les signale a chaque demarrage; cette
commande les enleve.

    manage.py purger_comptes_demo --dry-run
    manage.py purger_comptes_demo
    manage.py purger_comptes_demo --desactiver

Supprimer est le comportement par defaut. `--desactiver` ferme les comptes
sans les effacer: c'est le choix a faire si l'un d'eux a servi de compte de
travail et porte des ecritures qu'on ne veut pas voir partir avec lui.
"""

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import ProtectedError

from apps.common.comptes_demo import (
    NOMS_DES_COMPTES_DE_DEMONSTRATION,
    comptes_de_demonstration_presents,
)


class Command(BaseCommand):
    help = "Supprime (ou desactive) les comptes de demonstration."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Affiche les comptes vises, sans rien modifier.",
        )
        parser.add_argument(
            "--desactiver",
            action="store_true",
            help="Ferme les comptes au lieu de les supprimer.",
        )

    def handle(self, *args, **options):
        comptes = list(
            comptes_de_demonstration_presents().order_by("username")
        )

        if not comptes:
            self.stdout.write(
                self.style.SUCCESS(
                    "Aucun compte de demonstration en base. Rien a faire."
                )
            )
            return

        for compte in comptes:
            marque = " (super-utilisateur)" if compte.is_superuser else ""
            etat = "actif" if compte.is_active else "deja ferme"
            self.stdout.write(f"  - {compte.username}{marque}: {etat}")

        if options["dry_run"]:
            self.stdout.write(
                self.style.WARNING(
                    f"[simulation] {len(comptes)} compte(s) vise(s). "
                    "Relancer sans --dry-run pour agir."
                )
            )
            return

        if options["desactiver"]:
            with transaction.atomic():
                fermes = 0
                for compte in comptes:
                    if not compte.is_active:
                        continue
                    compte.is_active = False
                    # Un compte ferme mais toujours super-utilisateur
                    # redeviendrait dangereux au premier `is_active = True`
                    # pose par megarde depuis l'admin.
                    compte.is_superuser = False
                    compte.is_staff = False
                    compte.set_unusable_password()
                    compte.save(
                        update_fields=[
                            "is_active",
                            "is_superuser",
                            "is_staff",
                            "password",
                        ]
                    )
                    fermes += 1
            self.stdout.write(
                self.style.SUCCESS(
                    f"{fermes} compte(s) ferme(s), mot de passe rendu inutilisable."
                )
            )
            return

        try:
            with transaction.atomic():
                supprimes, _ = comptes_de_demonstration_presents().delete()
        except ProtectedError as erreur:
            raise CommandError(
                "Suppression impossible: un de ces comptes porte des ecritures "
                "protegees (paiements encaisses, validations). Relancez avec "
                f"--desactiver pour les fermer sans les effacer. Detail: {erreur}"
            ) from erreur

        self.stdout.write(
            self.style.SUCCESS(
                f"{supprimes} ligne(s) supprimee(s) pour "
                f"{len(comptes)} compte(s) de demonstration."
            )
        )
        self.stdout.write(
            "Comptes surveilles: " + ", ".join(NOMS_DES_COMPTES_DE_DEMONSTRATION)
        )
