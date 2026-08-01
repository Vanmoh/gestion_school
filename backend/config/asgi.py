import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

from apps.chat.jwt_ws import JwtAuthMiddlewareStack
from config.routing import websocket_urlpatterns

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

django_asgi_app = get_asgi_application()

application = ProtocolTypeRouter(
	{
		"http": django_asgi_app,
		"websocket": JwtAuthMiddlewareStack(URLRouter(websocket_urlpatterns)),
	}
)
