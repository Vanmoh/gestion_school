"""Previent l'intendance des articles passes sous leur seuil.

`is_low_stock` existait sur l'article depuis toujours, mais aucun ecran ni
aucune alerte ne s'en servait: le seuil se franchissait en silence, et la
rupture se decouvrait le jour ou l'on cherchait la craie.

    manage.py signaler_stock_bas
    manage.py signaler_stock_bas --etablissement 3
    manage.py signaler_stock_bas --dry-run
"""

from __future__ import annotations

from django.core.management.base import BaseCommand
from django.db.models import F

from apps.accounts.models import UserRole
from apps.school.models import (
    Etablissement,
    Notification,
    NotificationChannel,
    StockItem,
)

# Qui doit l'apprendre: celui qui commande et celui qui signe la depense.
ROLES_DESTINATAIRES = (UserRole.SUPER_ADMIN, UserRole.DIRECTOR, UserRole.ACCOUNTANT)


class Command(BaseCommand):
    help = "Notifie l'intendance des articles sous leur seuil de reapprovisionnement."

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            type=int,
            default=None,
            help="Limiter a un etablissement (identifiant).",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Affiche ce qui serait signale sans creer de notification.",
        )

    def handle(self, *args, **options):
        articles = StockItem.objects.select_related("etablissement").filter(
            quantity__lte=F("minimum_threshold")
        )
        cible = options.get("etablissement")
        if cible:
            articles = articles.filter(etablissement_id=cible)

        par_etablissement = {}
        for article in articles:
            if article.etablissement_id is None:
                continue
            par_etablissement.setdefault(article.etablissement_id, []).append(article)

        if not par_etablissement:
            self.stdout.write("Aucun article sous son seuil.")
            return

        total = sum(len(lignes) for lignes in par_etablissement.values())

        if options.get("dry_run"):
            for etablissement_id, lignes in par_etablissement.items():
                self.stdout.write(f"Etablissement {etablissement_id}: {len(lignes)} article(s)")
                for article in lignes:
                    self.stdout.write(
                        f"  - {article.name}: {article.quantity} {article.unit} "
                        f"(seuil {article.minimum_threshold})"
                    )
            self.stdout.write(f"{total} article(s) sous seuil (dry-run).")
            return

        envoyees = self._notifier(par_etablissement)
        self.stdout.write(
            f"{total} article(s) sous seuil, {envoyees} notification(s) envoyee(s)."
        )

    def _notifier(self, par_etablissement):
        """Un recapitulatif par responsable, pas une alerte par article.

        Un inventaire de rentree fait passer dix articles sous le seuil le
        meme jour: dix messages identiques dans la meme boite ne seraient
        plus lus des le troisieme.
        """
        from apps.accounts.models import User

        envoyees = 0
        for etablissement_id, lignes in par_etablissement.items():
            etablissement = Etablissement.objects.filter(id=etablissement_id).first()
            if etablissement is None:
                continue

            destinataires = User.objects.filter(
                etablissement=etablissement, role__in=ROLES_DESTINATAIRES
            )
            detail = "\n".join(
                f"- {article.name} : {article.quantity} {article.unit} "
                f"(seuil {article.minimum_threshold})"
                for article in sorted(
                    lignes, key=lambda a: a.quantity - a.minimum_threshold
                )
            )
            message = (
                f"{len(lignes)} article(s) sont au niveau ou en dessous de leur "
                f"seuil de réapprovisionnement :\n{detail}"
            )

            for destinataire in destinataires:
                Notification.objects.create(
                    etablissement=etablissement,
                    recipient=destinataire,
                    channel=NotificationChannel.PUSH,
                    title="Stock bas",
                    message=message,
                )
                envoyees += 1
        return envoyees
