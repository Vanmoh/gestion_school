"""Controles de deploiement propres au projet, remontes par `manage.py check`.

Ils visent des pannes qui ne provoquent aucune erreur au demarrage et se
manifestent seulement a l'usage, une fois en production.
"""

from django.conf import settings
from django.core.checks import Warning as CheckWarning
from django.core.checks import register


W001_MEDIA_LOCAL = "gestion_school.W001"
W002_CONN_MAX_AGE = "gestion_school.W002"
W003_S3_REGION = "gestion_school.W003"
W004_CHANNEL_LAYER = "gestion_school.W004"


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
def signed_media_urls_need_a_region(app_configs, **kwargs):
    """Sans region, les URL signees des fichiers televerses sont invalides.

    La signature v4 inscrit la region dans son perimetre
    (X-Amz-Credential=<cle>/<date>/<region>/s3/aws4_request). Region vide, ce
    champ l'est aussi et le fournisseur rejette la signature. Rien ne le
    signale: le televersement reussit, l'objet existe bel et bien dans le
    bucket, mais toute lecture repond 403 et la photo s'affiche simplement
    comme indisponible.
    """
    if not getattr(settings, "USE_OBJECT_STORAGE", False):
        return []
    if getattr(settings, "AWS_S3_REGION_NAME", ""):
        return []

    return [
        CheckWarning(
            "AWS_S3_REGION_NAME est vide alors qu'un bucket objet est configure.",
            hint=(
                "Renseignez la region du fournisseur de stockage. Supabase "
                "l'affiche dans Storage > S3 Connection (ex. eu-west-3); elle "
                "doit correspondre exactement, sinon les URL de lecture "
                "repondent 403. `manage.py check_media_storage` verifie "
                "l'aller-retour complet."
            ),
            id=W003_S3_REGION,
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


@register(deploy=True)
def realtime_channel_layer_is_reachable(app_configs, **kwargs):
    """Une couche Channels laissee sur l'hote de developpement tue le temps reel.

    `redis` est le nom de service de docker-compose: hors de cette stack, il ne
    resout pas. Le consumer echoue alors des group_add, et la diffusion depuis
    l'API est avalee par un except volontaire. Aucune erreur ne remonte: le
    chat parait fonctionner, les messages arrivent en base, et rien ne
    parvient jamais aux autres participants en direct.
    """
    hosts = (
        settings.CHANNEL_LAYERS.get("default", {}).get("CONFIG", {}).get("hosts", [])
    )
    suspects = [str(host) for host in hosts if "//redis:" in str(host)]
    if not suspects:
        return []

    return [
        CheckWarning(
            "La couche temps reel pointe sur l'hote de developpement "
            f"({', '.join(suspects)}).",
            hint=(
                "Renseignez CHANNEL_REDIS_URL (ou REDIS_URL) avec l'URL interne "
                "de votre instance Redis/Valkey. Sans cela le chat enregistre "
                "les messages mais ne les distribue jamais en direct."
            ),
            id=W004_CHANNEL_LAYER,
        )
    ]
