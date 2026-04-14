from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.chat.models import ChatMessage, Conversation, ConversationParticipant
from apps.school.models import AcademicYear, Etablissement


class ChatSendMessageApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="IFP-OBK Test",
            address="Quartier test",
            phone="670000000",
            email="test@ifp-obk.com",
        )
        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        self.sender = User.objects.create_user(
            username="director_chat",
            password="pass1234",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.receiver = User.objects.create_user(
            username="superadmin_chat",
            password="pass1234",
            role=UserRole.SUPER_ADMIN,
            etablissement=self.etablissement,
        )
        self.conversation = Conversation.objects.create(
            is_group=False,
            etablissement=self.etablissement,
        )
        self.sender_participant = ConversationParticipant.objects.create(
            conversation=self.conversation,
            user=self.sender,
        )
        ConversationParticipant.objects.create(
            conversation=self.conversation,
            user=self.receiver,
        )
        self.client.force_authenticate(self.sender)

    def test_send_message_creates_message_and_updates_sender_last_read(self):
        response = self.client.post(
            f"/api/chat/conversations/{self.conversation.id}/send/",
            {"content": "Bonjour depuis le test"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(ChatMessage.objects.count(), 1)

        message = ChatMessage.objects.get()
        self.assertEqual(message.content, "Bonjour depuis le test")
        self.assertEqual(message.sender_id, self.sender.id)
        self.assertEqual(message.conversation_id, self.conversation.id)

        self.sender_participant.refresh_from_db()
        self.assertEqual(self.sender_participant.last_read_message_id, message.id)
        self.assertEqual(response.data["id"], message.id)
        self.assertEqual(response.data["content"], message.content)

    def test_send_message_rejects_empty_content(self):
        response = self.client.post(
            f"/api/chat/conversations/{self.conversation.id}/send/",
            {"content": "   "},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(ChatMessage.objects.count(), 0)
