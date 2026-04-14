from django.contrib.auth import get_user_model
import threading
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from datetime import timedelta
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import ChatMessage, ChatPresence, Conversation, ConversationParticipant
from .serializers import (
    ChatMessageSerializer,
    ChatUserLiteSerializer,
    ConversationSerializer,
    DirectConversationCreateSerializer,
    GroupConversationCreateSerializer,
    GroupConversationRenameSerializer,
    GroupParticipantMutationSerializer,
)

User = get_user_model()


def _broadcast_rest_message_async(participant_user_ids, ws_message):
    def job():
        try:
            channel_layer = get_channel_layer()
            if channel_layer is None:
                return
            for user_id in participant_user_ids:
                async_to_sync(channel_layer.group_send)(
                    f"chat_user_{user_id}",
                    {
                        "type": "chat.message",
                        "message": ws_message,
                    },
                )
        except Exception:
            return

    worker = threading.Thread(target=job, name="chat-rest-broadcast", daemon=True)
    worker.start()


def _allowed_users_queryset(request):
    user = request.user
    query = User.objects.select_related("chat_presence", "etablissement").exclude(id=user.id)
    if getattr(user, "role", "") != "super_admin":
        query = query.filter(etablissement=user.etablissement)
    elif user.etablissement_id:
        query = query.filter(etablissement=user.etablissement)
    return query.order_by("first_name", "last_name", "username")


def _conversation_queryset_for_user(request):
    user = request.user
    query = (
        Conversation.objects.filter(participants__user=user)
        .prefetch_related("participants", "messages")
        .distinct()
        .order_by("-updated_at", "-id")
    )
    if getattr(user, "role", "") != "super_admin":
        query = query.filter(etablissement=user.etablissement)
    elif user.etablissement_id:
        query = query.filter(etablissement=user.etablissement)
    return query


def _ensure_participant(conversation_id, user):
    return ConversationParticipant.objects.filter(conversation_id=conversation_id, user=user).exists()


def _touch_presence(user):
    row, _ = ChatPresence.objects.get_or_create(
        user=user,
        defaults={"is_online": True, "connection_count": 0, "last_seen_at": timezone.now()},
    )
    row.is_online = True
    row.last_seen_at = timezone.now()
    row.save(update_fields=["is_online", "last_seen_at", "updated_at"])


def _presence_online_from_values(connection_count, last_seen_at):
    if (connection_count or 0) > 0:
        return True
    if last_seen_at is None:
        return False
    return (timezone.now() - last_seen_at) <= timedelta(seconds=90)


class ChatUsersView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        q = str(request.query_params.get("q", "")).strip()
        query = _allowed_users_queryset(request)
        if q:
            query = query.filter(
                Q(username__icontains=q)
                | Q(first_name__icontains=q)
                | Q(last_name__icontains=q)
            )
        serializer = ChatUserLiteSerializer(query, many=True)
        return Response(serializer.data)


class ConversationListView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        _touch_presence(request.user)
        rows = _conversation_queryset_for_user(request)
        serializer = ConversationSerializer(rows, many=True, context={"request": request})
        return Response(serializer.data)


class DirectConversationCreateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request):
        serializer = DirectConversationCreateSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        target_user = serializer.validated_data["target_user"]
        request_user = request.user

        existing = (
            Conversation.objects.filter(is_group=False, participants__user=request_user)
            .filter(participants__user=target_user)
            .distinct()
            .first()
        )
        if existing:
            payload = ConversationSerializer(existing, context={"request": request}).data
            return Response(payload)

        etablissement = request_user.etablissement or target_user.etablissement
        conversation = Conversation.objects.create(
            is_group=False,
            etablissement=etablissement,
        )
        ConversationParticipant.objects.create(conversation=conversation, user=request_user)
        ConversationParticipant.objects.create(conversation=conversation, user=target_user)
        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload, status=status.HTTP_201_CREATED)


class ConversationMessagesView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, conversation_id):
        if not _ensure_participant(conversation_id, request.user):
            return Response({"detail": "Acces refuse."}, status=status.HTTP_403_FORBIDDEN)

        query = ChatMessage.objects.filter(conversation_id=conversation_id).select_related("sender").order_by("-id")
        before_id = request.query_params.get("before_id")
        if before_id:
            try:
                query = query.filter(id__lt=int(before_id))
            except (TypeError, ValueError):
                pass

        page_size = request.query_params.get("page_size")
        try:
            size = max(1, min(100, int(page_size or 50)))
        except ValueError:
            size = 50

        rows = list(query[:size])
        rows.reverse()
        payload = ChatMessageSerializer(rows, many=True).data
        return Response(payload)


class ConversationPresenceView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, conversation_id):
        if not _ensure_participant(conversation_id, request.user):
            return Response({"detail": "Acces refuse."}, status=status.HTTP_403_FORBIDDEN)

        _touch_presence(request.user)

        rows = list(
            ConversationParticipant.objects.filter(conversation_id=conversation_id)
            .exclude(user=request.user)
            .values(
                "user_id",
                "user__chat_presence__connection_count",
                "user__chat_presence__last_seen_at",
            )
        )

        payload = []
        for row in rows:
            last_seen = row.get("user__chat_presence__last_seen_at")
            payload.append(
                {
                    "user_id": row.get("user_id"),
                    "online": _presence_online_from_values(
                        row.get("user__chat_presence__connection_count"),
                        last_seen,
                    ),
                    "last_seen_at": last_seen.isoformat() if last_seen else None,
                }
            )
        return Response(payload)


class GroupConversationCreateView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request):
        serializer = GroupConversationCreateSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)

        title = serializer.validated_data["title"]
        participants = serializer.validated_data["participants"]
        request_user = request.user
        etablissement = request_user.etablissement
        if etablissement is None and participants:
            etablissement = participants[0].etablissement

        conversation = Conversation.objects.create(
            is_group=True,
            title=title,
            etablissement=etablissement,
        )
        ConversationParticipant.objects.create(conversation=conversation, user=request_user, is_admin=True)
        ConversationParticipant.objects.bulk_create(
            [ConversationParticipant(conversation=conversation, user=user) for user in participants],
            ignore_conflicts=True,
        )

        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload, status=status.HTTP_201_CREATED)


class GroupConversationManageView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def _conversation_or_403(self, request, conversation_id):
        conversation = Conversation.objects.filter(id=conversation_id, is_group=True).first()
        if conversation is None:
            return None, Response({"detail": "Groupe introuvable."}, status=status.HTTP_404_NOT_FOUND)
        is_participant = ConversationParticipant.objects.filter(conversation=conversation, user=request.user).exists()
        if not is_participant:
            return None, Response({"detail": "Acces refuse."}, status=status.HTTP_403_FORBIDDEN)
        return conversation, None

    def _ensure_group_admin(self, conversation, user):
        return ConversationParticipant.objects.filter(
            conversation=conversation,
            user=user,
            is_admin=True,
        ).exists()

    @transaction.atomic
    def patch(self, request, conversation_id):
        conversation, error = self._conversation_or_403(request, conversation_id)
        if error is not None:
            return error

        if not self._ensure_group_admin(conversation, request.user):
            return Response({"detail": "Action reservee aux admins du groupe."}, status=status.HTTP_403_FORBIDDEN)

        serializer = GroupConversationRenameSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        conversation.title = serializer.validated_data["title"]
        conversation.save(update_fields=["title", "updated_at"])
        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload)

    @transaction.atomic
    def delete(self, request, conversation_id):
        conversation, error = self._conversation_or_403(request, conversation_id)
        if error is not None:
            return error

        if not self._ensure_group_admin(conversation, request.user):
            return Response({"detail": "Action reservee aux admins du groupe."}, status=status.HTTP_403_FORBIDDEN)

        conversation.delete()
        return Response({"ok": True})


class GroupConversationLeaveView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def _close_for_user(self, conversation, user):
        participant = ConversationParticipant.objects.select_for_update().filter(
            conversation=conversation,
            user=user,
        ).first()
        if participant is None:
            return {"ok": False, "detail": "Acces refuse."}

        was_admin = participant.is_admin
        participant.delete()

        remaining = ConversationParticipant.objects.filter(conversation=conversation).order_by("id")
        if not remaining.exists():
            conversation.delete()
            return {"ok": True, "deleted": True}

        if conversation.is_group:
            if was_admin and not remaining.filter(is_admin=True).exists():
                fallback = remaining.first()
                fallback.is_admin = True
                fallback.save(update_fields=["is_admin", "updated_at"])
        else:
            # 1-to-1 conversations are removed when one side closes it.
            conversation.delete()
            return {"ok": True, "deleted": True}

        return {"ok": True, "deleted": False}

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = Conversation.objects.filter(id=conversation_id, is_group=True).first()
        if conversation is None:
            return Response({"detail": "Groupe introuvable."}, status=status.HTTP_404_NOT_FOUND)

        result = self._close_for_user(conversation, request.user)
        if not result.get("ok"):
            return Response({"detail": result.get("detail", "Acces refuse.")}, status=status.HTTP_403_FORBIDDEN)
        return Response(result)


class ConversationCloseView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = Conversation.objects.select_for_update().filter(id=conversation_id).first()
        if conversation is None:
            return Response({"detail": "Conversation introuvable."}, status=status.HTTP_404_NOT_FOUND)

        leave_handler = GroupConversationLeaveView()
        result = leave_handler._close_for_user(conversation, request.user)
        if not result.get("ok"):
            return Response({"detail": result.get("detail", "Acces refuse.")}, status=status.HTTP_403_FORBIDDEN)
        return Response(result)


class GroupConversationAddMemberView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = Conversation.objects.filter(id=conversation_id, is_group=True).first()
        if conversation is None:
            return Response({"detail": "Groupe introuvable."}, status=status.HTTP_404_NOT_FOUND)

        if not ConversationParticipant.objects.filter(conversation=conversation, user=request.user, is_admin=True).exists():
            return Response({"detail": "Action reservee aux admins du groupe."}, status=status.HTTP_403_FORBIDDEN)

        serializer = GroupParticipantMutationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user_id = serializer.validated_data["user_id"]
        target_user = User.objects.filter(id=user_id).first()
        if target_user is None:
            return Response({"detail": "Utilisateur introuvable."}, status=status.HTTP_404_NOT_FOUND)

        if conversation.etablissement_id and target_user.etablissement_id and conversation.etablissement_id != target_user.etablissement_id:
            return Response({"detail": "Utilisateur hors etablissement."}, status=status.HTTP_400_BAD_REQUEST)

        ConversationParticipant.objects.get_or_create(
            conversation=conversation,
            user=target_user,
            defaults={"is_admin": False},
        )
        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload)


class GroupConversationRemoveMemberView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = Conversation.objects.filter(id=conversation_id, is_group=True).first()
        if conversation is None:
            return Response({"detail": "Groupe introuvable."}, status=status.HTTP_404_NOT_FOUND)

        if not ConversationParticipant.objects.filter(conversation=conversation, user=request.user, is_admin=True).exists():
            return Response({"detail": "Action reservee aux admins du groupe."}, status=status.HTTP_403_FORBIDDEN)

        serializer = GroupParticipantMutationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user_id = serializer.validated_data["user_id"]

        if user_id == request.user.id:
            return Response({"detail": "Vous ne pouvez pas vous retirer via cette action."}, status=status.HTTP_400_BAD_REQUEST)

        participant = ConversationParticipant.objects.filter(conversation=conversation, user_id=user_id).first()
        if participant is None:
            return Response({"detail": "Participant introuvable."}, status=status.HTTP_404_NOT_FOUND)
        participant.delete()

        remaining_admins = ConversationParticipant.objects.filter(conversation=conversation, is_admin=True).count()
        if remaining_admins == 0:
            fallback = ConversationParticipant.objects.filter(conversation=conversation).order_by("id").first()
            if fallback is not None:
                fallback.is_admin = True
                fallback.save(update_fields=["is_admin", "updated_at"])

        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload)


class GroupConversationPromoteAdminView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = Conversation.objects.filter(id=conversation_id, is_group=True).first()
        if conversation is None:
            return Response({"detail": "Groupe introuvable."}, status=status.HTTP_404_NOT_FOUND)

        if not ConversationParticipant.objects.filter(conversation=conversation, user=request.user, is_admin=True).exists():
            return Response({"detail": "Action reservee aux admins du groupe."}, status=status.HTTP_403_FORBIDDEN)

        serializer = GroupParticipantMutationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user_id = serializer.validated_data["user_id"]

        participant = ConversationParticipant.objects.filter(conversation=conversation, user_id=user_id).first()
        if participant is None:
            return Response({"detail": "Participant introuvable."}, status=status.HTTP_404_NOT_FOUND)

        participant.is_admin = True
        participant.save(update_fields=["is_admin", "updated_at"])
        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload)


class GroupConversationDemoteAdminView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = Conversation.objects.filter(id=conversation_id, is_group=True).first()
        if conversation is None:
            return Response({"detail": "Groupe introuvable."}, status=status.HTTP_404_NOT_FOUND)

        if not ConversationParticipant.objects.filter(conversation=conversation, user=request.user, is_admin=True).exists():
            return Response({"detail": "Action reservee aux admins du groupe."}, status=status.HTTP_403_FORBIDDEN)

        serializer = GroupParticipantMutationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user_id = serializer.validated_data["user_id"]

        participant = ConversationParticipant.objects.filter(conversation=conversation, user_id=user_id).first()
        if participant is None:
            return Response({"detail": "Participant introuvable."}, status=status.HTTP_404_NOT_FOUND)
        if not participant.is_admin:
            return Response({"detail": "Ce membre n'est pas admin."}, status=status.HTTP_400_BAD_REQUEST)

        admin_count = ConversationParticipant.objects.filter(conversation=conversation, is_admin=True).count()
        if admin_count <= 1:
            return Response({"detail": "Impossible de retirer le dernier admin."}, status=status.HTTP_400_BAD_REQUEST)

        participant.is_admin = False
        participant.save(update_fields=["is_admin", "updated_at"])
        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload)


class GroupConversationTransferAdminView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = Conversation.objects.filter(id=conversation_id, is_group=True).first()
        if conversation is None:
            return Response({"detail": "Groupe introuvable."}, status=status.HTTP_404_NOT_FOUND)

        requester = ConversationParticipant.objects.select_for_update().filter(
            conversation=conversation,
            user=request.user,
        ).first()
        if requester is None or not requester.is_admin:
            return Response({"detail": "Action reservee aux admins du groupe."}, status=status.HTTP_403_FORBIDDEN)

        serializer = GroupParticipantMutationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user_id = serializer.validated_data["user_id"]
        if user_id == request.user.id:
            return Response({"detail": "Vous etes deja admin."}, status=status.HTTP_400_BAD_REQUEST)

        target = ConversationParticipant.objects.select_for_update().filter(
            conversation=conversation,
            user_id=user_id,
        ).first()
        if target is None:
            return Response({"detail": "Participant introuvable."}, status=status.HTTP_404_NOT_FOUND)

        target.is_admin = True
        target.save(update_fields=["is_admin", "updated_at"])
        requester.is_admin = False
        requester.save(update_fields=["is_admin", "updated_at"])

        payload = ConversationSerializer(conversation, context={"request": request}).data
        return Response(payload)


class ConversationMarkReadView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        participant = ConversationParticipant.objects.select_for_update().filter(
            conversation_id=conversation_id,
            user=request.user,
        ).first()
        if participant is None:
            return Response({"detail": "Acces refuse."}, status=status.HTTP_403_FORBIDDEN)

        message_id = request.data.get("message_id")
        message = None
        if message_id is not None:
            try:
                message = ChatMessage.objects.filter(conversation_id=conversation_id, id=int(message_id)).first()
            except (TypeError, ValueError):
                message = None

        if message is None:
            message = ChatMessage.objects.filter(conversation_id=conversation_id).order_by("-id").first()

        participant.last_read_message = message
        participant.save(update_fields=["last_read_message", "updated_at"])
        return Response({"ok": True, "last_read_message": message.id if message else None})


class ConversationSendMessageView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request, conversation_id):
        _touch_presence(request.user)
        participant = ConversationParticipant.objects.select_for_update().filter(
            conversation_id=conversation_id,
            user=request.user,
        ).first()
        if participant is None:
            return Response({"detail": "Acces refuse."}, status=status.HTTP_403_FORBIDDEN)

        content = str(request.data.get("content", "")).strip()
        if not content:
            return Response({"detail": "Message vide."}, status=status.HTTP_400_BAD_REQUEST)
        raw_client_message_id = str(request.data.get("client_message_id", "")).strip()
        client_message_id = raw_client_message_id[:64] if raw_client_message_id else None

        conversation = Conversation.objects.select_for_update().filter(id=conversation_id).first()
        if conversation is None:
            return Response({"detail": "Conversation introuvable."}, status=status.HTTP_404_NOT_FOUND)

        created = True
        if client_message_id:
            message = ChatMessage.objects.filter(
                conversation=conversation,
                sender=request.user,
                client_message_id=client_message_id,
            ).first()
            if message is None:
                message = ChatMessage.objects.create(
                    conversation=conversation,
                    sender=request.user,
                    content=content,
                    client_message_id=client_message_id,
                )
            else:
                created = False
        else:
            message = ChatMessage.objects.create(
                conversation=conversation,
                sender=request.user,
                content=content,
            )

        participant.last_read_message = message
        participant.save(update_fields=["last_read_message", "updated_at"])
        conversation.save(update_fields=["updated_at"])
        payload = ChatMessageSerializer(message).data

        # Realtime fan-out for recipients when message is sent via REST.
        participant_user_ids = list(
            ConversationParticipant.objects.filter(conversation=conversation)
            .exclude(user=request.user)
            .values_list("user_id", flat=True)
        )
        sender_name = request.user.get_full_name().strip() or request.user.username
        ws_message = {
            "conversation_id": conversation.id,
            "message_id": message.id,
            "sender_id": request.user.id,
            "sender_name": sender_name,
            "content": message.content,
            "created_at": message.created_at.isoformat(),
        }
        if created and participant_user_ids:
            _broadcast_rest_message_async(participant_user_ids, ws_message)

        return Response(payload, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
