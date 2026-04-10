import time

from django.conf import settings
from django.db import connection

from apps.common.models import ActivityLog


class RequestTimingMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        start = time.perf_counter()
        initial_queries = len(connection.queries) if settings.DEBUG else 0
        response = self.get_response(request)

        if getattr(settings, "ENABLE_PROFILING_HEADERS", settings.DEBUG):
            elapsed_ms = (time.perf_counter() - start) * 1000
            response["X-Response-Time-ms"] = f"{elapsed_ms:.2f}"
            if settings.DEBUG:
                response["X-Query-Count"] = str(max(0, len(connection.queries) - initial_queries))

        return response


class ActivityLogMiddleware:
    MUTATING_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
    EXCLUDED_PREFIXES = (
        "/api/activity-logs",
        "/api/docs",
        "/api/schema",
        "/admin",
        "/static",
        "/media",
    )

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)

        if request.method not in self.MUTATING_METHODS:
            return response

        path = request.path or ""
        if any(path.startswith(prefix) for prefix in self.EXCLUDED_PREFIXES):
            return response

        try:
            user = request.user if getattr(request, "user", None) and request.user.is_authenticated else None
            role = getattr(user, "role", "") if user else ""
            etablissement = self._resolve_etablissement(request, user)
            module = self._extract_module(path)
            action = self._build_action(request.method, module)
            target = self._extract_target(path)
            ip_address = self._extract_ip(request)
            user_agent = (request.META.get("HTTP_USER_AGENT", "") or "")[:255]
            details = self._build_details(request)

            ActivityLog.objects.create(
                user=user,
                etablissement=etablissement,
                role=role,
                action=action,
                method=request.method,
                path=path[:255],
                module=module,
                target=target,
                status_code=getattr(response, "status_code", 0) or 0,
                success=200 <= (getattr(response, "status_code", 0) or 0) < 400,
                ip_address=ip_address,
                user_agent=user_agent,
                details=details,
            )
        except Exception:
            pass

        return response

    def _extract_module(self, path: str) -> str:
        parts = [part for part in path.split("/") if part]
        if len(parts) < 2:
            return "system"
        return parts[1][:80]

    def _extract_target(self, path: str) -> str:
        parts = [part for part in path.split("/") if part]
        return parts[2][:120] if len(parts) > 2 else ""

    def _build_action(self, method: str, module: str) -> str:
        verb = {
            "POST": "CREATE",
            "PUT": "UPDATE",
            "PATCH": "UPDATE",
            "DELETE": "DELETE",
        }.get(method, method)
        return f"{verb}_{module.upper()}"[:120]

    def _extract_ip(self, request) -> str:
        forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR")
        if forwarded_for:
            return forwarded_for.split(",")[0].strip()[:45]
        return (request.META.get("REMOTE_ADDR", "") or "")[:45]

    def _build_details(self, request) -> str:
        body_bytes = getattr(request, "body", b"") or b""
        if not body_bytes:
            return ""
        try:
            body = body_bytes.decode("utf-8", errors="ignore")
        except Exception:
            return ""
        if any(keyword in body.lower() for keyword in ["password", "token", "refresh"]):
            return "payload masqué"
        return body[:255]

    def _requested_etablissement_id(self, request):
        raw_value = request.headers.get("X-Etablissement-Id") or request.query_params.get("etablissement")
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _resolve_etablissement(self, request, user):
        if not user:
            return None

        # Non-superadmin users are always pinned to their own establishment.
        if getattr(user, "role", None) != "super_admin":
            return getattr(user, "etablissement", None)

        requested_id = self._requested_etablissement_id(request)
        if not requested_id:
            return None

        try:
            from apps.school.models import Etablissement

            return Etablissement.objects.filter(id=requested_id).first()
        except Exception:
            return None
