from django.urls import re_path

from .consumers import ChatStreamConsumer

websocket_urlpatterns = [
    re_path(r"ws/chat/stream/$", ChatStreamConsumer.as_asgi()),
]
