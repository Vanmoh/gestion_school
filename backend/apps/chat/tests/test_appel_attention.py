"""L'appel d'attention fait surgir la fenetre de discussion chez l'autre.

Deux exigences s'y croisent. Il doit porter -- sinon le bouton ne sert a
rien -- et il doit rester au personnel: la matrice des droits ouvre la
messagerie aux eleves et aux parents, mais nul ne doit pouvoir faire surgir
une fenetre chez le directeur en pleine reunion.
"""

from asgiref.sync import sync_to_async
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase, override_settings
from rest_framework_simplejwt.tokens import AccessToken

from apps.accounts.models import User, UserRole
from apps.chat.models import ChatMessage, Conversation, ConversationParticipant
from apps.school.models import Etablissement
from config.asgi import application

IN_MEMORY_LAYER = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}


@override_settings(CHANNEL_LAYERS=IN_MEMORY_LAYER)
class AppelAttentionTests(TransactionTestCase):
    def setUp(self):
        # La messagerie est cloisonnee par etablissement: sans lui, le
        # consumer ne voit aucune conversation et econduit tout le monde.
        self.etablissement = Etablissement.objects.create(
            name="IFP-OBK Test",
            address="Quartier test",
            phone="670000000",
            email="test@ifp-obk.com",
        )
        self.censeur = User.objects.create_user(
            username="censeur",
            password="Pass1234!",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
            first_name="Ousseini",
            last_name="Sissoko",
        )
        self.enseignant = User.objects.create_user(
            username="enseignant",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.eleve = User.objects.create_user(
            username="eleve",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )

        self.conversation = Conversation.objects.create(
            is_group=False, etablissement=self.etablissement
        )
        for compte in (self.censeur, self.enseignant, self.eleve):
            ConversationParticipant.objects.create(
                conversation=self.conversation, user=compte
            )

    async def _ouvrir(self, compte):
        jeton = str(AccessToken.for_user(compte))
        communicator = WebsocketCommunicator(
            application,
            f"/ws/chat/stream/?token={jeton}"
            f"&etablissement_id={self.etablissement.id}",
        )
        connecte, _ = await communicator.connect()
        self.assertTrue(connecte)
        await communicator.receive_json_from()  # « connected »
        return communicator

    async def _attendre(self, communicator, evenement):
        """Le prochain evenement du type voulu.

        La connexion diffuse aussi les entrees et sorties de presence des
        contacts: les attendre en aveugle rendrait le test dependant de qui
        se connecte dans quel ordre.
        """
        for _ in range(10):
            recu = await communicator.receive_json_from()
            if recu.get("event") == evenement:
                return recu
        self.fail(f"aucun evenement « {evenement} » recu")

    async def test_l_appel_atteint_l_autre_participant(self):
        appelant = await self._ouvrir(self.censeur)
        destinataire = await self._ouvrir(self.enseignant)
        try:
            await appelant.send_json_to(
                {"action": "attention", "conversation_id": self.conversation.id}
            )
            recu = await self._attendre(destinataire, "attention")

            self.assertEqual(recu["event"], "attention")
            self.assertEqual(recu["conversation_id"], self.conversation.id)
            self.assertEqual(recu["sender_id"], self.censeur.id)
            self.assertEqual(recu["sender_name"], "Ousseini Sissoko")
        finally:
            await appelant.disconnect()
            await destinataire.disconnect()

    async def test_l_appelant_recoit_aussi_l_evenement(self):
        """Sans cela, il ne verrait pas la ligne qu'il vient de laisser."""
        appelant = await self._ouvrir(self.censeur)
        try:
            await appelant.send_json_to(
                {"action": "attention", "conversation_id": self.conversation.id}
            )
            recu = await self._attendre(appelant, "attention")
            self.assertEqual(recu["event"], "attention")
        finally:
            await appelant.disconnect()

    async def test_l_appel_laisse_sa_trace_dans_le_fil(self):
        appelant = await self._ouvrir(self.censeur)
        try:
            await appelant.send_json_to(
                {"action": "attention", "conversation_id": self.conversation.id}
            )
            await self._attendre(appelant, "attention")
        finally:
            await appelant.disconnect()

        trace = await ChatMessage.objects.filter(
            conversation=self.conversation,
            message_type=ChatMessage.MessageType.ATTENTION,
        ).afirst()
        self.assertIsNotNone(trace, "l'appel n'a laisse aucune trace")
        self.assertEqual(trace.sender_id, self.censeur.id)
        self.assertIn("Ousseini Sissoko", trace.content)

    async def test_un_eleve_ne_peut_pas_faire_surgir_de_fenetre(self):
        appelant = await self._ouvrir(self.eleve)
        try:
            await appelant.send_json_to(
                {"action": "attention", "conversation_id": self.conversation.id}
            )
            reponse = await self._attendre(appelant, "error")

            self.assertEqual(reponse["event"], "error")
            self.assertIn("personnel", reponse["detail"])
        finally:
            await appelant.disconnect()

        # Et le refus ne laisse rien derriere lui.
        self.assertEqual(
            await ChatMessage.objects.filter(
                message_type=ChatMessage.MessageType.ATTENTION
            ).acount(),
            0,
        )

    async def test_un_etranger_a_la_conversation_est_econduit(self):
        etranger = await sync_to_async(User.objects.create_user)(
            username="autre_censeur",
            password="Pass1234!",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )
        appelant = await self._ouvrir(etranger)
        try:
            await appelant.send_json_to(
                {"action": "attention", "conversation_id": self.conversation.id}
            )
            reponse = await self._attendre(appelant, "error")
            self.assertEqual(reponse["event"], "error")
        finally:
            await appelant.disconnect()

    async def test_chaque_clic_rappelle_l_attention(self):
        """Aucun delai d'attente: reappeler doit refaire surgir la fenetre."""
        appelant = await self._ouvrir(self.censeur)
        destinataire = await self._ouvrir(self.enseignant)
        try:
            for _ in range(3):
                await appelant.send_json_to(
                    {"action": "attention", "conversation_id": self.conversation.id}
                )
                recu = await self._attendre(destinataire, "attention")
                self.assertEqual(recu["event"], "attention")
        finally:
            await appelant.disconnect()
            await destinataire.disconnect()

        self.assertEqual(
            await ChatMessage.objects.filter(
                message_type=ChatMessage.MessageType.ATTENTION
            ).acount(),
            3,
        )
