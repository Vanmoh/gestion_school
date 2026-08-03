"""Controles de deploiement propres au projet, remontes par `manage.py check`.

Ils visent des pannes qui ne provoquent aucune erreur au demarrage et se
manifestent seulement a l'usage, une fois en production.
"""

from django.conf import settings
from django.core.checks import Warning as CheckWarning
from django.core.checks import register


W001_MEDIA_LOCAL = "gestion_school.W001"
W002_CONN_MAX_AGE = "gestion_school.W002"


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


@register(deploy=True)
def persistent_connections_leak_under_asgi(app_configs, **kwargs):
    """Une connexion "persistante" servie en ASGI fuit au lieu d'etre reutilisee.

    Django cree un thread par requete et le detruit ensuite (asgiref,
    ThreadSensitiveContext). Avec CONN_MAX_AGE > 0, close_old_connections juge
    la connexion encore valide et ne la ferme pas: le thread meurt, la session
    reste ouverte cote serveur. Chaque requete en fuit une jusqu'a saturation
    du pooler, et l'application cesse de demarrer.

    Le reglage ne procure aucun gain en contrepartie, puisqu'un thread neuf ne
    retrouve jamais la connexion du precedent: c'est un cout sans benefice.
    """
    conn_max_age = settings.DATABASES.get("default", {}).get("CONN_MAX_AGE", 0)
    if not conn_max_age:
        return []

    return [
        CheckWarning(
            f"DB_CONN_MAX_AGE vaut {conn_max_age} alors que le service tourne en ASGI.",
            hint=(
                "Passez DB_CONN_MAX_AGE a 0. Les connexions persistantes ne sont "
                "pas reutilisables en ASGI (un thread par requete) et restent "
                "ouvertes cote serveur jusqu'a saturer le pooler. Pour du vrai "
                "pooling, passez par le pooler en mode transaction de votre "
                "hebergeur de base."
            ),
            id=W002_CONN_MAX_AGE,
        )
    ]
