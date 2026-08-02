"""Controles de deploiement propres au projet, remontes par `manage.py check`.

Ils visent des pannes qui ne provoquent aucune erreur au demarrage et se
manifestent seulement a l'usage, une fois en production.
"""

from django.conf import settings
from django.core.checks import Warning as CheckWarning
from django.core.checks import register


W001_MEDIA_LOCAL = "gestion_school.W001"


@register(deploy=True)
def uploaded_files_survive_a_deployment(app_configs, **kwargs):
    """Le stockage local des fichiers televerses ne survit pas a un deploiement.

    Sans stockage objet, `MEDIA_ROOT` vit dans le conteneur: photos d'eleves,
    logos, signatures, justificatifs et pieces jointes du chat sont perdus a
    chaque redeploiement, et l'URL /media/ n'est meme pas servie hors DEBUG.
    Rien dans les logs ne le signale, d'ou ce controle.
    """
    if settings.DEBUG or getattr(settings, "USE_OBJECT_STORAGE", False):
        return []

    return [
        CheckWarning(
            "Les fichiers televerses sont stockes sur le disque local.",
            hint=(
                "Renseignez AWS_STORAGE_BUCKET_NAME (+ AWS_ACCESS_KEY_ID, "
                "AWS_SECRET_ACCESS_KEY, AWS_S3_ENDPOINT_URL) pour basculer sur "
                "du stockage objet. A ignorer uniquement si MEDIA_ROOT est un "
                "volume persistant servi par un serveur web en amont."
            ),
            id=W001_MEDIA_LOCAL,
        )
    ]
