"""L'application servie en production doit reellement router le websocket.

La regression visee est silencieuse cote serveur: servie en WSGI, l'API
repond normalement et seul le chat temps reel est mort, sans erreur dans les
logs backend. Ce test s'adresse donc a `config.asgi.application` lui-meme,
pas au consumer isole, pour couvrir aussi le routage et le middleware JWT.
"""

from pathlib import Path

from channels.testing import WebsocketCommunicator
from django.test import SimpleTestCase, TransactionTestCase, override_settings
from rest_framework_simplejwt.tokens import AccessToken

from apps.accounts.models import User, UserRole
from config.asgi import application

IN_MEMORY_LAYER = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}


@override_settings(CHANNEL_LAYERS=IN_MEMORY_LAYER)
class ChatWebsocketRoutingTests(TransactionTestCase):
    def setUp(self):
        # Pas de purge manuelle du cache de couches: channels branche
        # ChannelLayerManager._reset_backends sur le signal setting_changed,
        # donc override_settings suffit a basculer sur la couche memoire.
        self.user = User.objects.create_user(
            username="ws_user",
            password="Pass1234!",
            role=UserRole.SUPERVISOR,
        )

    async def _connect(self, query):
        communicator = WebsocketCommunicator(
            application, f"/ws/chat/stream/{query}"
        )
        connected, _ = await communicator.connect()
        return communicator, connected

    async def test_an_authenticated_user_reaches_the_chat_stream(self):
        token = str(AccessToken.for_user(self.user))
        communicator, connected = await self._connect(f"?token={token}")

        try:
            self.assertTrue(
                connected,
                "config.asgi.application ne route pas le websocket du chat",
            )
            message = await communicator.receive_json_from()
            self.assertEqual(message["event"], "connected")
            self.assertEqual(message["user_id"], self.user.id)
        finally:
            await communicator.disconnect()

    async def test_a_connection_without_token_is_refused(self):
        communicator, connected = await self._connect("")
        try:
            self.assertFalse(connected)
        finally:
            await communicator.disconnect()

    async def test_a_forged_token_is_refused(self):
        communicator, connected = await self._connect("?token=pas-un-jwt")
        try:
            self.assertFalse(connected)
        finally:
            await communicator.disconnect()


class ProductionServesTheAsgiApplicationTests(SimpleTestCase):
    """Les tests ci-dessus visent config.asgi.application directement.

    Ils resteraient verts avec un deploiement en WSGI, c'est-a-dire dans la
    configuration exacte ou le chat est mort en production. Ce qui compte donc
    ici, c'est ce que lance reellement le conteneur.
    """

    BACKEND_DIR = Path(__file__).resolve().parents[3]

    def _launch_commands(self):
        return {
            "Dockerfile": (self.BACKEND_DIR / "Dockerfile").read_text(encoding="utf-8"),
            "start_render.sh": (self.BACKEND_DIR / "start_render.sh").read_text(
                encoding="utf-8"
            ),
        }

    def test_no_entrypoint_serves_the_wsgi_application(self):
        for name, content in self._launch_commands().items():
            with self.subTest(fichier=name):
                self.assertNotIn(
                    "config.wsgi",
                    content,
                    f"{name} sert config.wsgi: le websocket du chat ne repondra pas",
                )

    def test_every_entrypoint_uses_an_asgi_worker(self):
        for name, content in self._launch_commands().items():
            with self.subTest(fichier=name):
                self.assertIn("config.asgi", content)
                self.assertIn("uvicorn.workers.UvicornWorker", content)
