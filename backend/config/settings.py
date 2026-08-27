from datetime import timedelta
from pathlib import Path

from celery.schedules import crontab
from decouple import config
import dj_database_url
from corsheaders.defaults import default_headers
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent


def _csv_setting(name: str, default: str = "") -> list[str]:
    return [value.strip() for value in config(name, default=default).split(",") if value.strip()]

DEBUG = config("DEBUG", cast=bool, default=True)

_secret_key = config("SECRET_KEY", default="").strip()
if _secret_key:
    SECRET_KEY = _secret_key
elif DEBUG:
    SECRET_KEY = "dev-insecure-key-change-me"
else:
    raise ImproperlyConfigured(
        "SECRET_KEY is required when DEBUG=False. "
        "Set a strong SECRET_KEY in environment variables."
    )

_default_allowed_hosts = "localhost,127.0.0.1,0.0.0.0" if DEBUG else ""
ALLOWED_HOSTS = _csv_setting("ALLOWED_HOSTS", default=_default_allowed_hosts)
if not DEBUG and not ALLOWED_HOSTS:
    raise ImproperlyConfigured(
        "ALLOWED_HOSTS is required when DEBUG=False. "
        "Set ALLOWED_HOSTS to your domain(s), separated by commas."
    )

DATABASE_URL = config("DATABASE_URL", default="").strip()
# 0 par defaut: le service HTTP tourne en ASGI, ou Django cree un thread par
# requete et le detruit ensuite. Une connexion "persistante" n'y est jamais
# reutilisee et reste ouverte cote serveur apres la mort du thread, jusqu'a
# saturer le pooler. Seuls les processus synchrones (workers Celery) gagnent
# a relever cette valeur.
DB_CONN_MAX_AGE = config("DB_CONN_MAX_AGE", cast=int, default=0)
DB_SSL_REQUIRE = config("DB_SSL_REQUIRE", cast=bool, default=False)

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "channels",
    "django_celery_beat",
    "django_celery_results",
    "corsheaders",
    "rest_framework",
    "rest_framework_simplejwt",
    # Requis par BLACKLIST_AFTER_ROTATION: sans cette app SimpleJWT ignore
    # silencieusement la revocation et un refresh token vole reste valide
    # jusqu'a son expiration naturelle.
    "rest_framework_simplejwt.token_blacklist",
    "django_filters",
    "drf_spectacular",
    "apps.common",
    "apps.accounts",
    "apps.school",
    "apps.reports",
    "apps.chat",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    # Les listes paginees de l'API sont du JSON tres repetitif: une page de
    # 80 eleves pese 43 Ko brute et 3 Ko compressee, mesure sur la base de
    # developpement. Sur une connexion mobile, ces 40 Ko economises sont
    # l'essentiel du temps d'affichage d'un ecran de liste.
    #
    # Place avant WhiteNoise, qui sert deja ses propres fichiers compresses et
    # n'a donc rien a gagner a repasser dessous.
    #
    # A savoir: compresser une reponse qui melange un secret et une entree
    # controlee par l'attaquant ouvre la voie a BREACH. Ici les reponses sont
    # du JSON servi a une origine unique et declaree (CORS_ALLOWED_ORIGINS),
    # les jetons ne voyagent pas avec du contenu reflechi, et Django laisse de
    # toute facon les reponses de moins de 200 octets non compressees.
    # Celui d'apps.common et non celui de Django: voir la classe, qui laisse
    # passer PDF et images au lieu de les recompresser en pure perte.
    "apps.common.middleware.GZipMiddleware",
    # Doit suivre SecurityMiddleware et preceder tout le reste: gunicorn ne
    # sert pas /static/, l'admin Django et DRF n'auraient donc aucun style.
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "apps.common.middleware.RequestTimingMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "apps.common.middleware.ActivityLogMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [BASE_DIR / "templates"],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

if DATABASE_URL:
    DATABASES = {
        "default": dj_database_url.parse(
            DATABASE_URL,
            conn_max_age=DB_CONN_MAX_AGE,
            ssl_require=DB_SSL_REQUIRE,
        ),
    }

    # Un pooler en mode transaction rend la connexion a chaque fin de
    # transaction: elle peut alors servir une autre requete, ce que le mode
    # session ne permet pas (une connexion reste captive de son client, d'ou
    # une saturation rapide). En contrepartie, plus rien de lie a la session
    # ne survit d'une transaction a l'autre: les instructions preparees et les
    # curseurs serveur cassent, il faut donc les desactiver.
    # 6543 est le port du pooler transactionnel chez Supabase.
    _db_port = str(DATABASES["default"].get("PORT") or "")
    DB_TRANSACTION_POOLER = config(
        "DB_TRANSACTION_POOLER", cast=bool, default=_db_port == "6543"
    )
    if DB_TRANSACTION_POOLER:
        DATABASES["default"].setdefault("OPTIONS", {})
        DATABASES["default"]["OPTIONS"]["prepare_threshold"] = None
        DATABASES["default"]["DISABLE_SERVER_SIDE_CURSORS"] = True
else:
    if not DEBUG:
        raise ImproperlyConfigured(
            "DATABASE_URL is required when DEBUG=False. "
            "Set DATABASE_URL in Render environment variables to your Supabase PostgreSQL URL."
        )

    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.mysql",
            "NAME": config("DB_NAME", default="gestion_school"),
            "USER": config("DB_USER", default="gestion_user"),
            "PASSWORD": config("DB_PASSWORD", default="gestion_password"),
            "HOST": config("DB_HOST", default="db"),
            "PORT": config("DB_PORT", default="3306"),
            "CONN_MAX_AGE": DB_CONN_MAX_AGE,
            "OPTIONS": {"charset": "utf8mb4"},
        }
    }

AUTH_USER_MODEL = "accounts.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "fr-fr"
TIME_ZONE = "Africa/Abidjan"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"

STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        # Noms de fichiers empreintes + compression: le cache navigateur peut
        # etre agressif sans risquer de servir un asset perime.
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

# Fichiers televerses (photos d'eleves, logos, tampons, signatures,
# justificatifs d'absence, pieces jointes du chat).
#
# Sur un hebergement a disque ephemere comme Render, le systeme de fichiers du
# conteneur repart de zero a chaque deploiement: stockes en local, ces fichiers
# disparaissent. Des qu'un bucket est renseigne, tout passe en stockage objet.
AWS_STORAGE_BUCKET_NAME = config("AWS_STORAGE_BUCKET_NAME", default="").strip()
USE_OBJECT_STORAGE = bool(AWS_STORAGE_BUCKET_NAME)

if USE_OBJECT_STORAGE:
    AWS_ACCESS_KEY_ID = config("AWS_ACCESS_KEY_ID", default="")
    AWS_SECRET_ACCESS_KEY = config("AWS_SECRET_ACCESS_KEY", default="")
    AWS_S3_REGION_NAME = config("AWS_S3_REGION_NAME", default="").strip()
    # Renseigne pour tout fournisseur compatible S3 non-AWS
    # (Supabase Storage: https://<projet>.supabase.co/storage/v1/s3).
    AWS_S3_ENDPOINT_URL = config("AWS_S3_ENDPOINT_URL", default="").strip() or None

    # Signature v4 imposee, jamais laissee a la decouverte automatique. Selon
    # la version de botocore et la facon dont le client est construit, une
    # configuration incomplete produit une URL signee en v2
    # (AWSAccessKeyId/Signature/Expires); Supabase la rejette alors sans meme
    # la lire: "403 AccessDenied - Missing signature", ce qu'a renvoye l'URL
    # de production. La v2 est refusee par Supabase, R2, MinIO et les regions
    # AWS ouvertes apres 2014: rien ne justifie de la laisser possible.
    AWS_S3_SIGNATURE_VERSION = config("AWS_S3_SIGNATURE_VERSION", default="s3v4")

    # La region entre dans le perimetre de la signature v4
    # (X-Amz-Credential=<cle>/<date>/<region>/s3/aws4_request) et doit
    # correspondre a celle du fournisseur. Laissee vide, elle ne provoque
    # aucune erreur: le perimetre est simplement produit avec un champ vide
    # ("/<date>//s3/aws4_request") et toute lecture repond 403. C'est le
    # controle W003 qui le signale, plutot qu'une exception qui empecherait
    # tout le backend de demarrer pour une panne limitee aux televersements.
    AWS_S3_CUSTOM_DOMAIN = config("AWS_S3_CUSTOM_DOMAIN", default="").strip() or None
    AWS_S3_FILE_OVERWRITE = False
    AWS_DEFAULT_ACL = None
    # URLs signees a duree limitee, et non un bucket public: ces fichiers sont
    # des donnees personnelles d'eleves mineurs. Une URL publique reste
    # accessible a quiconque l'a vue passer, indefiniment.
    AWS_QUERYSTRING_AUTH = config("AWS_QUERYSTRING_AUTH", cast=bool, default=True)
    AWS_QUERYSTRING_EXPIRE = config("AWS_QUERYSTRING_EXPIRE", cast=int, default=3600)
    STORAGES["default"] = {"BACKEND": "storages.backends.s3.S3Storage"}

# Rediriger le lecteur vers le stockage plutot que lui relayer le PDF.
#
# Le gain est net: un document de 40 Mo cesse de traverser le conteneur, qui
# ne dispose que de 0,1 CPU et 512 Mo. Le client va le chercher directement
# la ou il est, par une URL signee a duree limitee (AWS_QUERYSTRING_EXPIRE).
#
# Desactive par defaut, et ce n'est pas de la prudence excessive: sur le web,
# l'application lit ce fichier en XHR, et une redirection vers un autre
# domaine declenche un controle CORS cote bucket. Tant que le bucket n'a pas
# ete configure pour accepter l'origine de l'application, activer ce reglage
# casse l'ouverture des documents dans le navigateur -- sans rien casser sur
# Android ni sur le poste, ou le CORS n'existe pas.
#
# Marche a suivre pour l'activer: docs/OPERATIONS_BIBLIOTHEQUE.md, §3.
LIBRARY_STORAGE_REDIRECT = config(
    "LIBRARY_STORAGE_REDIRECT", cast=bool, default=False
)

# Poids maximal d'un PDF televerse depuis l'application.
#
# 50 Mo laisse passer un manuel scanne entier tout en fermant la porte a la
# video renommee en .pdf. Le fonds importe, lui, monte jusqu'a 127 Mo par
# document: il n'entre pas par cette porte mais par la commande d'import,
# que cette limite ne regarde pas.
LIBRARY_UPLOAD_MAX_MB = config("LIBRARY_UPLOAD_MAX_MB", cast=int, default=50)

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

CORS_ALLOW_ALL_ORIGINS = config(
    "CORS_ALLOW_ALL_ORIGINS", cast=bool, default=DEBUG
)

# Never allow wildcard CORS in production even if the env var is misconfigured.
if not DEBUG and CORS_ALLOW_ALL_ORIGINS:
    CORS_ALLOW_ALL_ORIGINS = False

CORS_ALLOWED_ORIGINS = _csv_setting("CORS_ALLOWED_ORIGINS") if not CORS_ALLOW_ALL_ORIGINS else []
if not DEBUG and not CORS_ALLOW_ALL_ORIGINS and not CORS_ALLOWED_ORIGINS:
    CORS_ALLOWED_ORIGINS = [
        config("WEB_APP_ORIGIN", default="https://gestion-school-web.onrender.com")
    ]
CORS_ALLOW_HEADERS = list(default_headers) + [
    "x-etablissement-id",
    "x-etablissement-name",
]
CSRF_TRUSTED_ORIGINS = _csv_setting("CSRF_TRUSTED_ORIGINS")

USE_X_FORWARDED_HOST = config("USE_X_FORWARDED_HOST", cast=bool, default=True)
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Le preload HSTS est un engagement difficilement reversible: il faut garantir
# durablement le HTTPS sur le domaine et tous ses sous-domaines, et la sortie
# de la liste prend des mois. Choix assume, tu par un controle qui doit rester
# exploitable comme porte de CI.
SILENCED_SYSTEM_CHECKS = ["security.W021"]

SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"

if not DEBUG:
    SESSION_COOKIE_SECURE = config("SESSION_COOKIE_SECURE", cast=bool, default=True)
    CSRF_COOKIE_SECURE = config("CSRF_COOKIE_SECURE", cast=bool, default=True)
    SESSION_COOKIE_HTTPONLY = True
    # Le proxy termine TLS et annonce le schema via X-Forwarded-Proto
    # (SECURE_PROXY_SSL_HEADER ci-dessus): la redirection est donc sure.
    SECURE_SSL_REDIRECT = config("SECURE_SSL_REDIRECT", cast=bool, default=True)
    # La sonde de sante peut etre appelee en HTTP depuis le reseau interne de
    # l'hebergeur. Redirigee en 301, elle serait lue comme un echec et le
    # service serait declare mort alors qu'il fonctionne.
    SECURE_REDIRECT_EXEMPT = [r"^api/healthz/$"]
    # 1 an. Passer preload a True suppose d'assumer que tous les
    # sous-domaines servent en HTTPS, de facon durable.
    SECURE_HSTS_SECONDS = config("SECURE_HSTS_SECONDS", cast=int, default=31536000)
    SECURE_HSTS_INCLUDE_SUBDOMAINS = config(
        "SECURE_HSTS_INCLUDE_SUBDOMAINS", cast=bool, default=True
    )
    SECURE_HSTS_PRELOAD = config("SECURE_HSTS_PRELOAD", cast=bool, default=False)

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ),
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    # Sans ce relais, un `ProtectedError` -- supprimer une classe qui porte
    # des notes -- sortait en 500 avec une trace, la ou c'est une regle
    # metier que l'utilisateur doit pouvoir lire.
    "EXCEPTION_HANDLER": "apps.common.exception_handler.custom_exception_handler",
    # Sans pagination par defaut, /students/, /grades/ ou /payments/ serialisent
    # la table entiere a chaque appel: la charge cote serveur n'est bornee par
    # rien, et le cahier des charges vise 1000+ eleves.
    "DEFAULT_PAGINATION_CLASS": "apps.common.pagination.StandardResultsSetPagination",
    "DEFAULT_THROTTLE_CLASSES": (
        "rest_framework.throttling.ScopedRateThrottle",
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ),
    "DEFAULT_THROTTLE_RATES": {
        # Le login est la seule route ou un anonyme peut deviner un secret:
        # elle est limitee bien plus bas que le reste du trafic anonyme.
        "login": config("THROTTLE_LOGIN", default="10/min"),
        "anon": config("THROTTLE_ANON", default="60/min"),
        # Large: une page de saisie de notes enchaine beaucoup d'appels
        # legitimes. Le but est de couper l'abus, pas l'usage normal.
        "user": config("THROTTLE_USER", default="2000/hour"),
    },
}

SPECTACULAR_SETTINGS = {
    "TITLE": "GESTION SCHOOL API",
    "DESCRIPTION": "API de gestion scolaire multi-module",
    "VERSION": "1.0.0",
    # drf-spectacular sert le schema en AllowAny par defaut: la cartographie
    # complete de l'API, parametres compris, etait donc publique en production.
    # Ouvert en developpement, reserve au staff ensuite.
    "SERVE_PERMISSIONS": (
        ["rest_framework.permissions.AllowAny"]
        if DEBUG
        else ["rest_framework.permissions.IsAdminUser"]
    ),
}

SCHOOL_NAME = config("SCHOOL_NAME", default="LYCÉE TECHNIQUE OUMAR BAH")
SCHOOL_SHORT = config("SCHOOL_SHORT", default="LTOB")
SCHOOL_LEVEL = config("SCHOOL_LEVEL", default="1er étage")
SCHOOL_PHONE = config("SCHOOL_PHONE", default="78 78 59 13 / 66 74 22 32")
SCHOOL_LOGO_PATH = config(
    "SCHOOL_LOGO_PATH",
    default=str(BASE_DIR.parent / "frontend" / "gestion_school_app" / "assets" / "images" / "logo_ecole.png"),
)

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=60),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=7),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "ALGORITHM": "HS256",
    "SIGNING_KEY": SECRET_KEY,
    "AUTH_HEADER_TYPES": ("Bearer",),
}

CELERY_BROKER_URL = config("CELERY_BROKER_URL", default="redis://redis:6379/0")
CELERY_RESULT_BACKEND = config("CELERY_RESULT_BACKEND", default="redis://redis:6379/1")
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = TIME_ZONE

# Le service beat tournait sans aucune tache planifiee: la sauvegarde
# automatique exigee par le cahier des charges n'a jamais eu lieu.
# L'heure est locale (TIME_ZONE), choisie hors des heures de saisie.
CELERY_BEAT_BACKUP_HOUR = config("BACKUP_HOUR", cast=int, default=2)
CELERY_BEAT_BACKUP_MINUTE = config("BACKUP_MINUTE", cast=int, default=30)
CELERY_BEAT_SCHEDULE = {
    "sauvegarde-quotidienne-base": {
        "task": "apps.common.tasks.scheduled_database_backup",
        "schedule": crontab(
            hour=CELERY_BEAT_BACKUP_HOUR,
            minute=CELERY_BEAT_BACKUP_MINUTE,
        ),
    },
    # Filet, et non le mecanisme principal: le catalogue est demande au
    # demarrage de l'API (entrypoint.sh). Ce passage quotidien rattrape le cas
    # ou le courtier etait injoignable a ce moment-la. La tache s'arrete d'
    # elle-meme si le fonds est deja catalogue, elle ne coute alors qu'une
    # requete en base.
    "catalogue-fonds-documentaire": {
        "task": "apps.school.tasks.import_library_catalogue",
        "schedule": crontab(hour=3, minute=15),
    },
    # Le lendemain matin, avant l'ouverture: la direction apprend qu'une
    # classe est restee sans professeur pendant qu'elle peut encore
    # organiser un remplacement, et non en fin de mois sur une fiche de paie.
    "seances-non-assurees": {
        "task": "apps.school.tasks.signaler_les_seances_non_assurees",
        "schedule": crontab(hour=6, minute=30),
    },
    # Le lundi matin: un reapprovisionnement se prepare en debut de semaine,
    # et une alerte quotidienne sur un stock qui bouge peu ne serait plus lue.
    "stock-bas": {
        "task": "apps.school.tasks.signaler_le_stock_bas",
        "schedule": crontab(hour=7, minute=0, day_of_week=1),
    },
}

CHANNEL_REDIS_URL = config(
    "CHANNEL_REDIS_URL",
    default=config("REDIS_URL", default="redis://redis:6379/2"),
)
CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {
            "hosts": [CHANNEL_REDIS_URL],
        },
    },
}

# Les quotas de debit se comptent dans le cache. Avec le cache local par
# defaut, chaque worker gunicorn tient son propre compteur et la limite reelle
# est multipliee par le nombre de workers: en production le cache doit etre
# partage. On ne bascule sur Redis que s'il est explicitement fourni, pour que
# les tests et le dev restent autonomes.
CACHE_URL = config("CACHE_URL", default="").strip()
if CACHE_URL:
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": CACHE_URL,
        }
    }
else:
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "gestion-school-local",
        }
    }

ENABLE_FILE_LOGGING = config("ENABLE_FILE_LOGGING", cast=bool, default=True)
ENABLE_PROFILING_HEADERS = config(
    "ENABLE_PROFILING_HEADERS", cast=bool, default=DEBUG
)
LOG_DIR = BASE_DIR / "logs"
LOG_FILE_PATH = LOG_DIR / "app.log"

_file_logging_enabled = ENABLE_FILE_LOGGING
if _file_logging_enabled:
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with LOG_FILE_PATH.open("a", encoding="utf-8"):
            pass
    except OSError:
        _file_logging_enabled = False

_log_handlers = {
    "console": {
        "class": "logging.StreamHandler",
        "formatter": "verbose",
    },
}

_django_logger_handlers = ["console"]
_apps_logger_handlers = ["console"]

if _file_logging_enabled:
    _log_handlers["file"] = {
        "level": "INFO",
        "class": "logging.FileHandler",
        "filename": LOG_FILE_PATH,
        "formatter": "verbose",
    }
    _django_logger_handlers.append("file")
    _apps_logger_handlers.append("file")

# Supervision des erreurs. Sans DSN, rien n'est initialise: le projet doit
# rester utilisable sans compte Sentry, et les tests ne doivent rien emettre.
SENTRY_DSN = config("SENTRY_DSN", default="").strip()
if SENTRY_DSN:
    import sentry_sdk

    sentry_sdk.init(
        dsn=SENTRY_DSN,
        environment=config("SENTRY_ENVIRONMENT", default="production"),
        release=config("SENTRY_RELEASE", default="") or None,
        # Jamais True ici: l'application manipule des donnees d'eleves mineurs,
        # qui n'ont rien a faire dans un service de supervision tiers.
        send_default_pii=False,
        traces_sample_rate=config("SENTRY_TRACES_SAMPLE_RATE", cast=float, default=0.0),
    )

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        },
    },
    "handlers": _log_handlers,
    "loggers": {
        "django": {
            "handlers": _django_logger_handlers,
            "level": "INFO",
            "propagate": True,
        },
        "apps": {
            "handlers": _apps_logger_handlers,
            "level": "INFO",
            "propagate": False,
        },
    },
}
