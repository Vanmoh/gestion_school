"""Point d'entree ASGI: HTTP classique + websocket du chat.

L'ordre des lignes est porteur de sens et ne doit pas etre reorganise par un
tri d'imports automatique. `get_asgi_application()` declenche django.setup():
tout module qui touche aux modeles (le middleware JWT, le routage des
consumers) doit donc etre importe apres, faute de quoi le worker refuse de
demarrer sur AppRegistryNotReady.
"""

import os

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from django.core.asgi import get_asgi_application  # noqa: E402

django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402

from apps.chat.jwt_ws import JwtAuthMiddlewareStack  # noqa: E402
from config.routing import websocket_urlpatterns  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        "websocket": JwtAuthMiddlewareStack(URLRouter(websocket_urlpatterns)),
    }
)
