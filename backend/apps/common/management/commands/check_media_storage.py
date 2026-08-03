"""Verifie que le stockage des fichiers televerses fonctionne vraiment.

Une configuration incomplete ne se voit pas au demarrage: l'application
accepte les televersements et c'est seulement en consultant une fiche eleve,
plus tard, qu'on decouvre que la photo n'existe nulle part. Cette commande
fait l'aller-retour complet (ecriture, relecture, URL, suppression) pour que
la panne apparaisse tout de suite.
"""

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand, CommandError

PROBE_NAME = "healthcheck/probe-stockage.txt"
PROBE_BODY = b"verification du stockage gestion school"


class Command(BaseCommand):
    help = "Teste l'ecriture, la relecture et la suppression sur le stockage configure."

    def handle(self, *args, **options):
        if not getattr(settings, "USE_OBJECT_STORAGE", False):
            raise CommandError(
                "Aucun stockage objet configure (AWS_STORAGE_BUCKET_NAME est vide). "
                "Les fichiers televerses vivent sur le disque du conteneur et "
                "disparaitront au prochain deploiement."
            )

        self.stdout.write(f"Bucket   : {settings.AWS_STORAGE_BUCKET_NAME}")
        self.stdout.write(f"Endpoint : {settings.AWS_S3_ENDPOINT_URL or '(AWS par defaut)'}")
        self.stdout.write(
            f"URLs     : {'signees' if settings.AWS_QUERYSTRING_AUTH else 'PUBLIQUES'}"
        )

        stored = None
        try:
            stored = default_storage.save(PROBE_NAME, ContentFile(PROBE_BODY))
            self.stdout.write(self.style.SUCCESS(f"  ecriture     OK  ({stored})"))

            with default_storage.open(stored, "rb") as handle:
                if handle.read() != PROBE_BODY:
                    raise CommandError("Le fichier relu ne correspond pas a ce qui a ete ecrit.")
            self.stdout.write(self.style.SUCCESS("  relecture    OK"))

            url = default_storage.url(stored)
            signed = "?" in url
            self.stdout.write(self.style.SUCCESS(f"  URL          OK  ({'signee' if signed else 'publique'})"))
            if settings.AWS_QUERYSTRING_AUTH and not signed:
                self.stdout.write(
                    self.style.WARNING(
                        "  Les URL signees sont demandees mais l'URL produite ne l'est "
                        "pas: verifiez que le bucket n'est pas public."
                    )
                )
        finally:
            if stored:
                default_storage.delete(stored)
                self.stdout.write(self.style.SUCCESS("  suppression  OK"))

        if not settings.AWS_QUERYSTRING_AUTH:
            self.stdout.write(
                self.style.WARNING(
                    "\nBucket public: photos d'eleves et justificatifs seraient "
                    "lisibles par toute personne connaissant l'URL, et la "
                    "sauvegarde de base refusera de s'y deposer."
                )
            )
            return

        self.stdout.write(self.style.SUCCESS("\nStockage operationnel."))
