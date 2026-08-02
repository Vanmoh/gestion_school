"""Sonde de sante consommee par le health check de l'hebergeur.

Elle repond a une question precise: cette instance peut-elle servir une
requete utile? Un service qui repond 200 sur une page statique alors que sa
base est injoignable reste declare sain et continue de recevoir du trafic,
d'ou la verification effective des dependances.
"""

from django.core.cache import cache
from django.db import connection
from rest_framework import status
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from drf_spectacular.utils import extend_schema

_PROBE_KEY = "healthz-probe"


def _check_database() -> tuple[bool, str]:
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    except Exception as exc:  # noqa: BLE001 - toute panne doit devenir un 503
        return False, type(exc).__name__
    return True, "ok"


def _check_cache() -> tuple[bool, str]:
    """Le cache porte les quotas de debit: hors service, ils ne s'appliquent plus."""
    try:
        cache.set(_PROBE_KEY, "1", 10)
        if cache.get(_PROBE_KEY) != "1":
            return False, "lecture incoherente"
    except Exception as exc:  # noqa: BLE001
        return False, type(exc).__name__
    return True, "ok"


class HealthCheckView(APIView):
    """Etat des dependances. Publique: le health check n'a pas de jeton."""

    authentication_classes = ()
    permission_classes = [AllowAny]
    # Une sonde ne doit pas pouvoir etre bridee par les quotas, sinon
    # l'hebergeur conclut a une panne sur un service parfaitement sain.
    throttle_classes = ()

    @extend_schema(
        summary="Etat de sante du service",
        description="200 si la base et le cache repondent, 503 sinon.",
        responses={200: dict, 503: dict},
        auth=[],
    )
    def get(self, request):
        database_ok, database_detail = _check_database()
        cache_ok, cache_detail = _check_cache()
        healthy = database_ok and cache_ok

        return Response(
            {
                "status": "ok" if healthy else "degraded",
                "checks": {
                    "database": {"ok": database_ok, "detail": database_detail},
                    "cache": {"ok": cache_ok, "detail": cache_detail},
                },
            },
            status=status.HTTP_200_OK if healthy else status.HTTP_503_SERVICE_UNAVAILABLE,
        )
