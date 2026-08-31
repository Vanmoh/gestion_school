"""La presence dit qui est la maintenant, pas qui l'a ete un jour.

Le defaut corrige ici se voyait a l'oeil nu: un compte reste vert pendant des
jours apres sa derniere visite. Le compteur de sockets, qui pilotait
l'affichage, ne redescendait jamais quand le socket mourait sans prevenir --
navigateur ferme d'un coup, wifi coupe, serveur redemarre.
"""

from datetime import date, timedelta

from channels.db import database_sync_to_async
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase, override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import AccessToken

from apps.accounts.models import User, UserRole
from apps.chat.models import ChatPresence, Conversation, ConversationParticipant
from apps.school.models import AcademicYear, Etablissement
from config.asgi import application

IN_MEMORY_LAYER = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}


class PresenceApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="IFP-OBK Presence",
            address="Quartier test",
            phone="670000001",
            email="presence@ifp-obk.com",
        )
        AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        self.moi = User.objects.create_user(
            username="directeur_presence",
            password="pass1234",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.autre = User.objects.create_user(
            username="collegue_presence",
            password="pass1234",
            role=UserRole.SUPER_ADMIN,
            etablissement=self.etablissement,
        )
        self.conversation = Conversation.objects.create(
            is_group=False,
            etablissement=self.etablissement,
        )
        ConversationParticipant.objects.create(
            conversation=self.conversation, user=self.moi
        )
        ConversationParticipant.objects.create(
            conversation=self.conversation, user=self.autre
        )
        self.client.force_authenticate(self.moi)

    def _presence_de_lautre(self, **champs):
        return ChatPresence.objects.create(user=self.autre, **champs)

    def _ligne_de_lautre(self, payload):
        for row in payload:
            if row.get("user_id") == self.autre.id:
                return row
        self.fail("La presence du correspondant est absente de la reponse.")

    def test_socket_fantome_n_affiche_plus_en_ligne(self):
        """Le cas signale: compteur reste a 1, plus aucun signe de vie depuis des jours."""
        self._presence_de_lautre(
            is_online=True,
            connection_count=1,
            last_seen_at=timezone.now() - timedelta(days=3),
        )

        response = self.client.get(
            f"/api/chat/conversations/{self.conversation.id}/presence/"
        )

        self.assertEqual(response.status_code, 200)
        ligne = self._ligne_de_lautre(response.data)
        self.assertFalse(ligne["online"])
        self.assertIsNotNone(ligne["last_seen_at"])

    def test_activite_recente_affiche_en_ligne(self):
        self._presence_de_lautre(
            is_online=False,
            connection_count=0,
            last_seen_at=timezone.now() - timedelta(seconds=10),
        )

        response = self.client.get(
            f"/api/chat/conversations/{self.conversation.id}/presence/"
        )

        self.assertTrue(self._ligne_de_lautre(response.data)["online"])

    def test_annuaire_du_chat_rend_la_derniere_activite(self):
        vu_a = timezone.now() - timedelta(hours=5)
        self._presence_de_lautre(
            is_online=True, connection_count=2, last_seen_at=vu_a
        )

        response = self.client.get("/api/chat/users/")

        self.assertEqual(response.status_code, 200)
        ligne = next(row for row in response.data if row["id"] == self.autre.id)
        self.assertFalse(ligne["online"])
        self.assertIsNotNone(ligne["last_seen_at"])

    def test_jamais_vu_reste_hors_ligne_sans_horodatage(self):
        response = self.client.get("/api/chat/users/")

        ligne = next(row for row in response.data if row["id"] == self.autre.id)
        self.assertFalse(ligne["online"])
        self.assertIsNone(ligne["last_seen_at"])

    def test_toute_requete_authentifiee_vaut_signe_de_vie(self):
        """Travailler dans l'application suffit: le chat n'a pas a etre ouvert."""
        self.client.get("/api/chat/users/")

        presence = ChatPresence.objects.filter(user=self.moi).first()
        self.assertIsNotNone(presence)
        self.assertIsNotNone(presence.last_seen_at)
        self.assertLessEqual(
            timezone.now() - presence.last_seen_at, timedelta(seconds=30)
        )


class PresenceAdministrationTests(APITestCase):
    """La fiche d'un compte, dans « Gestion des utilisateurs »."""

    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="IFP-OBK Admin",
            address="Quartier test",
            phone="670000002",
            email="admin@ifp-obk.com",
        )
        self.admin = User.objects.create_user(
            username="super_presence",
            password="pass1234",
            role=UserRole.SUPER_ADMIN,
            etablissement=self.etablissement,
        )
        self.employe = User.objects.create_user(
            username="employe_presence",
            password="pass1234",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(self.admin)

    def _fiche_employe(self):
        response = self.client.get(f"/api/auth/users/{self.employe.id}/")
        self.assertEqual(response.status_code, 200)
        return response.data

    def test_compte_jamais_connecte(self):
        fiche = self._fiche_employe()

        self.assertTrue(fiche["has_never_logged_in"])
        self.assertFalse(fiche["online"])
        self.assertIsNone(fiche["last_seen_at"])

    def test_compte_en_ligne(self):
        ChatPresence.objects.create(
            user=self.employe,
            is_online=True,
            connection_count=1,
            last_seen_at=timezone.now(),
        )

        self.assertTrue(self._fiche_employe()["online"])

    def test_compte_parti_rend_l_heure_de_son_depart(self):
        ChatPresence.objects.create(
            user=self.employe,
            is_online=True,
            connection_count=1,
            last_seen_at=timezone.now() - timedelta(hours=2),
        )

        fiche = self._fiche_employe()
        self.assertFalse(fiche["online"])
        self.assertIsNotNone(fiche["last_seen_at"])


@override_settings(CHANNEL_LAYERS=IN_MEMORY_LAYER)
class BattementWebsocketTests(TransactionTestCase):
    """Le battement du client tient la presence a jour.

    Sans lui, une fenetre laissee ouverte sans un clic passait hors ligne au
    bout d'une minute alors que la personne etait devant son ecran.
    """

    def setUp(self):
        self.user = User.objects.create_user(
            username="ws_presence",
            password="Pass1234!",
            role=UserRole.SUPERVISOR,
        )

    @database_sync_to_async
    def _last_seen(self):
        row = ChatPresence.objects.filter(user=self.user).first()
        return row.last_seen_at if row else None

    @database_sync_to_async
    def _vieillir_la_presence(self):
        ChatPresence.objects.filter(user=self.user).update(
            last_seen_at=timezone.now() - timedelta(minutes=10)
        )

    async def test_le_ping_rafraichit_la_derniere_activite(self):
        token = str(AccessToken.for_user(self.user))
        communicator = WebsocketCommunicator(
            application, f"/ws/chat/stream/?token={token}"
        )
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        try:
            await communicator.receive_json_from()  # « connected »
            await self._vieillir_la_presence()

            await communicator.send_json_to({"action": "ping"})
            for _ in range(5):
                message = await communicator.receive_json_from()
                if message.get("event") == "pong":
                    break
            else:
                self.fail("Le serveur n'a pas repondu au battement.")

            vu_a = await self._last_seen()
            self.assertIsNotNone(vu_a)
            self.assertLessEqual(timezone.now() - vu_a, timedelta(seconds=30))
        finally:
            await communicator.disconnect()

    async def test_la_deconnexion_pose_l_heure_du_depart(self):
        token = str(AccessToken.for_user(self.user))
        communicator = WebsocketCommunicator(
            application, f"/ws/chat/stream/?token={token}"
        )
        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await communicator.receive_json_from()
        await communicator.disconnect()

        row = await database_sync_to_async(
            lambda: ChatPresence.objects.filter(user=self.user).first()
        )()
        self.assertIsNotNone(row)
        self.assertEqual(row.connection_count, 0)
        self.assertFalse(row.is_online)
        self.assertIsNotNone(row.last_seen_at)
