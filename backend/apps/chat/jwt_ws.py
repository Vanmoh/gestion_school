from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from django.contrib.auth import get_user_model
from django.contrib.auth.models import AnonymousUser
from rest_framework_simplejwt.tokens import UntypedToken
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError

User = get_user_model()


@database_sync_to_async
def _get_user_by_id(user_id):
    try:
        return User.objects.get(id=user_id)
    except User.DoesNotExist:
        return AnonymousUser()


class JwtAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        try:
            query_string = scope.get("query_string", b"").decode("utf-8")
            params = parse_qs(query_string)
            token_values = params.get("token", [])
            token = token_values[0] if token_values else None

            if token:
                validated = UntypedToken(token)
                user_id = validated.payload.get("user_id")
                if user_id:
                    scope["user"] = await _get_user_by_id(user_id)
                else:
                    scope["user"] = AnonymousUser()
            else:
                scope["user"] = AnonymousUser()
        except (InvalidToken, TokenError, Exception):
            scope["user"] = AnonymousUser()

        return await super().__call__(scope, receive, send)


def JwtAuthMiddlewareStack(inner):
    return JwtAuthMiddleware(inner)
