from datetime import date
import shutil
import tempfile

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.chat.models import ChatMessage, Conversation, ConversationParticipant
from apps.chat.serializers import ConversationSerializer
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

    def test_send_message_is_idempotent_with_client_message_id(self):
        first = self.client.post(
            f"/api/chat/conversations/{self.conversation.id}/send/",
            {
                "content": "Message idempotent",
                "client_message_id": "client-msg-001",
            },
            format="json",
        )
        second = self.client.post(
            f"/api/chat/conversations/{self.conversation.id}/send/",
            {
                "content": "Message idempotent",
                "client_message_id": "client-msg-001",
            },
            format="json",
        )

        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertEqual(ChatMessage.objects.count(), 1)

        message = ChatMessage.objects.get()
        self.assertEqual(first.data["id"], message.id)
        self.assertEqual(second.data["id"], message.id)
        self.assertEqual(second.data["client_message_id"], "client-msg-001")

    def test_send_file_creates_file_message(self):
        upload = SimpleUploadedFile(
            "bulletin.txt",
            b"contenu de test",
            content_type="text/plain",
        )

        response = self.client.post(
            f"/api/chat/conversations/{self.conversation.id}/send-file/",
            {"file": upload, "content": "Piece jointe", "client_message_id": "file-msg-001"},
            format="multipart",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(ChatMessage.objects.count(), 1)
        message = ChatMessage.objects.get()
        self.assertEqual(message.message_type, ChatMessage.MessageType.FILE)
        self.assertEqual(message.attachment_name, "bulletin.txt")
        self.assertEqual(message.content, "Piece jointe")
        self.assertEqual(response.data["attachment_name"], "bulletin.txt")
        self.assertTrue(response.data["attachment_url"])

    def test_download_attachment_requires_participant(self):
        upload = SimpleUploadedFile(
            "bulletin.txt",
            b"contenu de test",
            content_type="text/plain",
        )
        message = ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.sender,
            message_type=ChatMessage.MessageType.FILE,
            attachment=upload,
            attachment_name="bulletin.txt",
            attachment_size=len(b"contenu de test"),
            attachment_mime_type="text/plain",
        )

        outsider = User.objects.create_user(
            username="outsider_chat",
            password="pass1234",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(outsider)
        response = self.client.get(f"/api/chat/messages/{message.id}/download/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_send_file_rejects_unsupported_type(self):
        upload = SimpleUploadedFile(
            "malware.exe",
            b"dummy-binary",
            content_type="application/octet-stream",
        )

        response = self.client.post(
            f"/api/chat/conversations/{self.conversation.id}/send-file/",
            {"file": upload},
            format="multipart",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("non autorise", str(response.data["detail"]).lower())

    def test_conversation_serializer_uses_other_participant_last_read_message(self):
        first_message = ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.sender,
            content="Premier message",
        )
        second_message = ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.sender,
            content="Deuxieme message",
        )
        receiver_participant = ConversationParticipant.objects.get(
            conversation=self.conversation,
            user=self.receiver,
        )
        receiver_participant.last_read_message = first_message
        receiver_participant.save(update_fields=["last_read_message", "updated_at"])

        serializer = ConversationSerializer(
            self.conversation,
            context={"request": type("Req", (), {"user": self.sender})()},
        )

        self.assertEqual(serializer.data["other_last_read_message_id"], first_message.id)
        self.assertNotEqual(serializer.data["other_last_read_message_id"], second_message.id)


class ChatScopedUsersApiTests(APITestCase):
    def setUp(self):
        self._temp_media_dir = tempfile.mkdtemp(prefix="chat-scope-tests-")
        self._media_override = override_settings(MEDIA_ROOT=self._temp_media_dir)
        self._media_override.enable()
        self.addCleanup(self._media_override.disable)
        self.addCleanup(lambda: shutil.rmtree(self._temp_media_dir, ignore_errors=True))

        self.etablissement_a = Etablissement.objects.create(
            name="Complexe Scolaire Oumar Bah",
            address="Quartier A",
            phone="620000001",
            email="a@test.com",
        )
        self.etablissement_b = Etablissement.objects.create(
            name="Groupe Scolaire Horizon",
            address="Quartier B",
            phone="620000002",
            email="b@test.com",
        )
        self.super_admin = User.objects.create_user(
            username="super_scope",
            password="pass1234",
            role=UserRole.SUPER_ADMIN,
        )
        self.user_a = User.objects.create_user(
            username="user_a",
            password="pass1234",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement_a,
        )
        self.user_b = User.objects.create_user(
            username="user_b",
            password="pass1234",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement_b,
        )
        self.out_of_scope_direct = Conversation.objects.create(
            is_group=False,
            etablissement=self.etablissement_b,
        )
        ConversationParticipant.objects.create(
            conversation=self.out_of_scope_direct,
            user=self.super_admin,
        )
        ConversationParticipant.objects.create(
            conversation=self.out_of_scope_direct,
            user=self.user_b,
        )
        self.group_b = Conversation.objects.create(
            is_group=True,
            title="Groupe B",
            etablissement=self.etablissement_b,
        )
        ConversationParticipant.objects.create(
            conversation=self.group_b,
            user=self.super_admin,
            is_admin=True,
        )
        ConversationParticipant.objects.create(
            conversation=self.group_b,
            user=self.user_b,
        )
        self.file_message = ChatMessage.objects.create(
            conversation=self.out_of_scope_direct,
            sender=self.user_b,
            message_type=ChatMessage.MessageType.FILE,
            attachment=SimpleUploadedFile(
                "scope.txt",
                b"scope",
                content_type="text/plain",
            ),
            attachment_name="scope.txt",
            attachment_size=len(b"scope"),
            attachment_mime_type="text/plain",
        )
        self.client.force_authenticate(self.super_admin)

    def _scope_headers(self):
        return {
            "HTTP_X_ETABLISSEMENT_ID": str(self.etablissement_a.id),
            "HTTP_X_ETABLISSEMENT_NAME": self.etablissement_a.name,
        }

    def test_chat_users_respects_requested_etablissement_header_for_super_admin(self):
        response = self.client.get(
            "/api/chat/users/",
            **self._scope_headers(),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        returned_ids = {row["id"] for row in response.data}
        self.assertIn(self.user_a.id, returned_ids)
        self.assertNotIn(self.user_b.id, returned_ids)

    def test_direct_conversation_creation_rejects_user_outside_requested_etablissement(self):
        response = self.client.post(
            "/api/chat/conversations/direct/",
            {"user_id": self.user_b.id},
            format="json",
            **self._scope_headers(),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("hors etablissement", str(response.data).lower())

    def test_messages_endpoint_rejects_out_of_scope_conversation_even_for_participant(self):
        response = self.client.get(
            f"/api/chat/conversations/{self.out_of_scope_direct.id}/messages/",
            **self._scope_headers(),
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_send_message_rejects_out_of_scope_conversation_even_for_participant(self):
        response = self.client.post(
            f"/api/chat/conversations/{self.out_of_scope_direct.id}/send/",
            {"content": "contournement"},
            format="json",
            **self._scope_headers(),
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_download_rejects_out_of_scope_attachment_even_for_participant(self):
        response = self.client.get(
            f"/api/chat/messages/{self.file_message.id}/download/",
            **self._scope_headers(),
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_group_member_add_rejects_out_of_scope_group_even_for_admin(self):
        response = self.client.post(
            f"/api/chat/conversations/{self.group_b.id}/group/add-member/",
            {"user_id": self.user_a.id},
            format="json",
            **self._scope_headers(),
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
