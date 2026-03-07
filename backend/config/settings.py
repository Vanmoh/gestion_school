from datetime import timedelta
from pathlib import Path
from decouple import config
import dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent


def _csv_setting(name: str, default: str = "") -> list[str]:
    return [value.strip() for value in config(name, default=default).split(",") if value.strip()]

SECRET_KEY = config("SECRET_KEY", default="change-me-in-production")
DEBUG = config("DEBUG", cast=bool, default=False)
ALLOWED_HOSTS = _csv_setting("ALLOWED_HOSTS", default="*")

DATABASE_URL = config("DATABASE_URL", default="").strip()
DB_CONN_MAX_AGE = config("DB_CONN_MAX_AGE", cast=int, default=600)
DB_SSL_REQUIRE = config("DB_SSL_REQUIRE", cast=bool, default=False)

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django_celery_beat",
    "django_celery_results",
    "corsheaders",
    "rest_framework",
    "rest_framework_simplejwt",
    "django_filters",
    "drf_spectacular",
    "apps.common",
    "apps.accounts",
    "apps.school",
    "apps.reports",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "apps.common.middleware.ActivityLogMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

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
else:
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

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

CORS_ALLOW_ALL_ORIGINS = config("CORS_ALLOW_ALL_ORIGINS", cast=bool, default=True)
CORS_ALLOWED_ORIGINS = _csv_setting("CORS_ALLOWED_ORIGINS") if not CORS_ALLOW_ALL_ORIGINS else []
CSRF_TRUSTED_ORIGINS = _csv_setting("CSRF_TRUSTED_ORIGINS")

USE_X_FORWARDED_HOST = config("USE_X_FORWARDED_HOST", cast=bool, default=True)
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

if not DEBUG:
    SESSION_COOKIE_SECURE = config("SESSION_COOKIE_SECURE", cast=bool, default=True)
    CSRF_COOKIE_SECURE = config("CSRF_COOKIE_SECURE", cast=bool, default=True)

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
}

SPECTACULAR_SETTINGS = {
    "TITLE": "GESTION SCHOOL API",
    "DESCRIPTION": "API de gestion scolaire multi-module",
    "VERSION": "1.0.0",
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

ENABLE_FILE_LOGGING = config("ENABLE_FILE_LOGGING", cast=bool, default=True)
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
