from asgiref.sync import sync_to_async
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer
from django.contrib.auth.models import AnonymousUser
from django.db import transaction
from django.utils import timezone

from .models import ChatMessage, ChatPresence, Conversation, ConversationParticipant


class ChatStreamConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        user = self.scope.get("user")
        if not user or isinstance(user, AnonymousUser) or not user.is_authenticated:
            await self.close(code=4401)
            return

        self.user = user
        self.user_group = f"chat_user_{self.user.id}"
        self.etablissement_id = getattr(self.user, "etablissement_id", None)

        await self.channel_layer.group_add(self.user_group, self.channel_name)
        for conversation_id in await self._conversation_ids_for_user():
            await self.channel_layer.group_add(
                f"chat_conversation_{conversation_id}",
                self.channel_name,
            )

        if self.etablissement_id:
            await self.channel_layer.group_add(
                f"chat_presence_{self.etablissement_id}",
                self.channel_name,
            )

        is_online = await self._increment_presence()
        await self.accept()

        await self.send_json({"event": "connected", "user_id": self.user.id})
        await self._send_initial_presence_snapshot()
        await self._broadcast_presence_update(
            online=is_online,
            last_seen_at=timezone.now().isoformat(),
        )

    async def disconnect(self, close_code):
        if not hasattr(self, "user"):
            return

        for conversation_id in await self._conversation_ids_for_user():
            await self.channel_layer.group_discard(
                f"chat_conversation_{conversation_id}",
                self.channel_name,
            )

        await self.channel_layer.group_discard(self.user_group, self.channel_name)

        if self.etablissement_id:
            await self.channel_layer.group_discard(
                f"chat_presence_{self.etablissement_id}",
                self.channel_name,
            )

        is_online, last_seen = await self._decrement_presence()
        await self._broadcast_presence_update(
            online=is_online,
            last_seen_at=last_seen.isoformat() if last_seen else None,
        )

    async def _broadcast_presence_update(self, online, last_seen_at):
        payload = {
            "type": "presence.update",
            "user_id": self.user.id,
            "online": bool(online),
            "last_seen_at": last_seen_at,
        }

        if self.etablissement_id:
            await self.channel_layer.group_send(
                f"chat_presence_{self.etablissement_id}",
                payload,
            )

        contact_user_ids = await self._contact_user_ids()
        for user_id in contact_user_ids:
            await self.channel_layer.group_send(
                f"chat_user_{user_id}",
                payload,
            )

    async def _send_initial_presence_snapshot(self):
        snapshots = await self._contact_presence_snapshot()
        for row in snapshots:
            await self.send_json(
                {
                    "event": "presence",
                    "user_id": row["user_id"],
                    "online": row["online"],
                    "last_seen_at": row["last_seen_at"],
                }
            )

    async def receive_json(self, content, **kwargs):
        action = str(content.get("action", "")).strip().lower()

        if action == "ping":
            await self.send_json({"event": "pong", "ts": timezone.now().isoformat()})
            return

        if action == "send_message":
            conversation_id = content.get("conversation_id")
            text = str(content.get("content", "")).strip()
            if not text:
                return
            message_payload = await self._create_message(conversation_id, text)
            if message_payload is None:
                await self.send_json({"event": "error", "detail": "Conversation invalide."})
                return

            base_message = {
                "conversation_id": message_payload["conversation_id"],
                "message_id": message_payload["message_id"],
                "sender_id": message_payload["sender_id"],
                "sender_name": message_payload["sender_name"],
                "content": message_payload["content"],
                "created_at": message_payload["created_at"],
            }

            for user_id in message_payload.get("participant_user_ids", []):
                await self.channel_layer.group_send(
                    f"chat_user_{user_id}",
                    {
                        "type": "chat.message",
                        "message": base_message,
                    },
                )
            return

        if action == "mark_read":
            conversation_id = content.get("conversation_id")
            read_payload = await self._mark_conversation_read(conversation_id)
            await self.send_json({
                "event": "marked_read",
                "conversation_id": conversation_id,
                "last_read_message_id": read_payload["last_read_message_id"] if read_payload else None,
            })
            if read_payload is not None:
                for user_id in read_payload.get("participant_user_ids", []):
                    if user_id == self.user.id:
                        continue
                    await self.channel_layer.group_send(
                        f"chat_user_{user_id}",
                        {
                            "type": "chat.read_receipt",
                            "payload": {
                                "conversation_id": read_payload["conversation_id"],
                                "user_id": self.user.id,
                                "last_read_message_id": read_payload["last_read_message_id"],
                            },
                        },
                    )
            return

        if action == "typing":
            conversation_id = content.get("conversation_id")
            is_typing = bool(content.get("is_typing", False))
            if not await self._is_participant(conversation_id):
                return
            participant_user_ids = await self._participant_user_ids(conversation_id)
            for user_id in participant_user_ids:
                await self.channel_layer.group_send(
                    f"chat_user_{user_id}",
                    {
                        "type": "chat.typing",
                        "conversation_id": int(conversation_id),
                        "user_id": self.user.id,
                        "is_typing": is_typing,
                    },
                )

    async def chat_message(self, event):
        await self.send_json({"event": "message", **event["message"]})

    async def chat_typing(self, event):
        await self.send_json({"event": "typing", **event})

    async def presence_update(self, event):
        await self.send_json({"event": "presence", **event})

    async def chat_read_receipt(self, event):
        await self.send_json({"event": "read_receipt", **event["payload"]})

    @database_sync_to_async
    def _conversation_ids_for_user(self):
        return list(
            ConversationParticipant.objects.filter(user=self.user)
            .values_list("conversation_id", flat=True)
            .distinct()
        )

    @database_sync_to_async
    def _is_participant(self, conversation_id):
        try:
            conversation_id = int(conversation_id)
        except (TypeError, ValueError):
            return False
        return ConversationParticipant.objects.filter(
            user=self.user,
            conversation_id=conversation_id,
        ).exists()

    @database_sync_to_async
    def _participant_user_ids(self, conversation_id):
        try:
            conversation_id = int(conversation_id)
        except (TypeError, ValueError):
            return []
        return list(
            ConversationParticipant.objects.filter(conversation_id=conversation_id)
            .values_list("user_id", flat=True)
        )

    @database_sync_to_async
    def _contact_user_ids(self):
        return self._contact_user_ids_sync()

    def _contact_user_ids_sync(self):
        conversation_ids = (
            ConversationParticipant.objects.filter(user=self.user)
            .values_list("conversation_id", flat=True)
            .distinct()
        )
        return list(
            ConversationParticipant.objects.filter(conversation_id__in=conversation_ids)
            .exclude(user=self.user)
            .values_list("user_id", flat=True)
            .distinct()
        )

    @database_sync_to_async
    def _contact_presence_snapshot(self):
        contact_user_ids = self._contact_user_ids_sync()
        if not contact_user_ids:
            return []

        presence_by_user = {
            row["user_id"]: {
                "online": bool(row["is_online"]),
                "last_seen_at": row["last_seen_at"].isoformat() if row["last_seen_at"] else None,
            }
            for row in ChatPresence.objects.filter(user_id__in=contact_user_ids).values(
                "user_id", "is_online", "last_seen_at"
            )
        }

        payload = []
        for user_id in contact_user_ids:
            state = presence_by_user.get(user_id)
            payload.append(
                {
                    "user_id": user_id,
                    "online": state["online"] if state else False,
                    "last_seen_at": state["last_seen_at"] if state else None,
                }
            )
        return payload

    @database_sync_to_async
    def _create_message(self, conversation_id, text):
        try:
            conversation_id = int(conversation_id)
        except (TypeError, ValueError):
            return None

        with transaction.atomic():
            participant = ConversationParticipant.objects.select_for_update().filter(
                conversation_id=conversation_id,
                user=self.user,
            ).first()
            if participant is None:
                return None

            conversation = Conversation.objects.select_for_update().filter(id=conversation_id).first()
            if conversation is None:
                return None

            message = ChatMessage.objects.create(
                conversation=conversation,
                sender=self.user,
                content=text,
            )
            conversation.save(update_fields=["updated_at"])
            participant_user_ids = list(
                ConversationParticipant.objects.filter(conversation_id=conversation.id)
                .values_list("user_id", flat=True)
            )

            sender_name = self.user.get_full_name().strip() or self.user.username
            return {
                "conversation_id": conversation.id,
                "message_id": message.id,
                "sender_id": self.user.id,
                "sender_name": sender_name,
                "content": message.content,
                "created_at": message.created_at.isoformat(),
                "participant_user_ids": participant_user_ids,
            }

    @database_sync_to_async
    def _mark_conversation_read(self, conversation_id):
        try:
            conversation_id = int(conversation_id)
        except (TypeError, ValueError):
            return None

        with transaction.atomic():
            participant = ConversationParticipant.objects.select_for_update().filter(
                conversation_id=conversation_id,
                user=self.user,
            ).first()
            if participant is None:
                return None

            last_message = ChatMessage.objects.filter(conversation_id=conversation_id).order_by("-id").first()
            participant.last_read_message = last_message
            participant.save(update_fields=["last_read_message", "updated_at"])
            participant_user_ids = list(
                ConversationParticipant.objects.filter(conversation_id=conversation_id)
                .values_list("user_id", flat=True)
            )
            return {
                "conversation_id": conversation_id,
                "last_read_message_id": last_message.id if last_message else None,
                "participant_user_ids": participant_user_ids,
            }

    @database_sync_to_async
    def _increment_presence(self):
        with transaction.atomic():
            row, _ = ChatPresence.objects.select_for_update().get_or_create(
                user=self.user,
                defaults={"is_online": True, "connection_count": 0},
            )
            row.connection_count += 1
            row.is_online = row.connection_count > 0
            row.save(update_fields=["connection_count", "is_online", "updated_at"])
            return row.is_online

    @database_sync_to_async
    def _decrement_presence(self):
        with transaction.atomic():
            row, _ = ChatPresence.objects.select_for_update().get_or_create(
                user=self.user,
                defaults={"is_online": False, "connection_count": 0},
            )
            row.connection_count = max(0, row.connection_count - 1)
            row.is_online = row.connection_count > 0
            row.last_seen_at = timezone.now()
            row.save(update_fields=["connection_count", "is_online", "last_seen_at", "updated_at"])
            return row.is_online, row.last_seen_at
