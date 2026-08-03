"""Verifie que le stockage des fichiers televerses fonctionne vraiment.

Une configuration incomplete ne se voit pas au demarrage: l'application
accepte les televersements et c'est seulement en consultant une fiche eleve,
plus tard, qu'on decouvre que la photo n'existe nulle part. Cette commande
fait l'aller-retour complet (ecriture, relecture, URL, suppression) pour que
la panne apparaisse tout de suite.
"""

import re
import urllib.error
import urllib.request

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand, CommandError

PROBE_NAME = "healthcheck/probe-stockage.txt"
PROBE_BODY = b"verification du stockage gestion school"
FETCH_TIMEOUT = 15

# Les fournisseurs S3 renvoient l'erreur en XML; ces deux champs suffisent a
# nommer la panne au lieu d'afficher un mur de balises.
_S3_CODE = re.compile(rb"<Code>([^<]+)</Code>")
_S3_MESSAGE = re.compile(rb"<Message>([^<]+)</Message>")
# "the region 'us-east-1' is wrong; expecting 'eu-west-3'"
_EXPECTED_REGION = re.compile(r"expecting '([^']+)'")


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

            # Etape decisive: une URL bien formee n'est pas une URL qui marche.
            # Une signature v2 la rend inexploitable alors que tout le reste du
            # trajet -- ecriture, relecture, generation -- reussit sans broncher.
            self._fetch(url)
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

    def _fetch(self, url):
        """Telecharge l'URL produite et compare l'octet a octet.

        Sans cette etape, la commande validait une URL que le fournisseur
        refusait: elle ne verifiait que la presence d'un "?".
        """
        if not url.lower().startswith(("http://", "https://")):
            # Stockage local: l'URL est relative, il n'y a rien a joindre.
            self.stdout.write("  telechargement  ignore (URL relative)")
            return

        try:
            with urllib.request.urlopen(url, timeout=FETCH_TIMEOUT) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            raise CommandError(self._explain(error)) from error
        except urllib.error.URLError as error:
            raise CommandError(
                f"Le stockage est injoignable depuis ce serveur: {error.reason}"
            ) from error

        if body != PROBE_BODY:
            raise CommandError(
                "L'URL repond mais ne renvoie pas le fichier attendu "
                f"({len(body)} octets recus). Le bucket sert probablement "
                "autre chose a cette adresse."
            )

        self.stdout.write(self.style.SUCCESS("  telechargement  OK"))

    def _explain(self, error):
        """Traduit l'erreur XML du fournisseur en cause probable."""
        payload = b""
        try:
            payload = error.read()
        except Exception:  # noqa: BLE001 - le corps est facultatif
            pass

        code_match = _S3_CODE.search(payload)
        message_match = _S3_MESSAGE.search(payload)
        code = code_match.group(1).decode(errors="replace") if code_match else ""
        message = message_match.group(1).decode(errors="replace") if message_match else ""

        lines = [
            f"L'URL generee est refusee par le stockage (HTTP {error.code}).",
        ]
        if code or message:
            lines.append(f"Reponse du fournisseur: {code} - {message}")

        region = getattr(settings, "AWS_S3_REGION_NAME", "")
        expected = _EXPECTED_REGION.search(message)
        if expected:
            lines.append(
                f"Corrigez AWS_S3_REGION_NAME: '{region or '(vide)'}' est utilise, "
                f"'{expected.group(1)}' est attendu."
            )
        elif "signature" in message.lower() or code in {
            "AccessDenied",
            "SignatureDoesNotMatch",
            "InvalidAccessKeyId",
        }:
            lines.append(
                "Verifiez AWS_S3_SIGNATURE_VERSION (v4 exigee par Supabase, R2 "
                f"et MinIO), AWS_S3_REGION_NAME (actuellement '{region or '(vide)'}') "
                "et les cles d'acces. Une region vide fait retomber boto3 sur la "
                "signature v2, que ces fournisseurs rejettent."
            )

        return "\n".join(lines)
