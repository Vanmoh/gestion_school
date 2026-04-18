from django.contrib.auth import get_user_model
from django.db.models import Q
from django.utils import timezone
from datetime import timedelta
from rest_framework import serializers

from apps.school.models import Etablissement

from .models import ChatMessage, ChatPresence, Conversation, ConversationParticipant

User = get_user_model()


def _requested_chat_etablissement_id(request):
    raw_value = request.headers.get("X-Etablissement-Id") or request.query_params.get("etablissement")
    if raw_value in (None, ""):
        return None
    try:
        parsed = int(raw_value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def _requested_chat_etablissement_name(request):
    raw_name = request.headers.get("X-Etablissement-Name") or request.query_params.get("etablissement_name")
    if raw_name is None:
        return None
    cleaned = str(raw_name).strip()
    return cleaned or None


def _requested_chat_etablissement(request):
    requested_id = _requested_chat_etablissement_id(request)
    if requested_id:
        etablissement = Etablissement.objects.filter(id=requested_id).first()
        if etablissement is not None:
            return etablissement

    requested_name = _requested_chat_etablissement_name(request)
    if not requested_name:
        return None

    etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
    if etablissement is not None:
        return etablissement

    return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()


def _chat_scope_etablissement(request):
    user = request.user
    if getattr(user, "role", "") != "super_admin":
        return getattr(user, "etablissement", None)
    requested_etablissement = _requested_chat_etablissement(request)
    if requested_etablissement is not None:
        return requested_etablissement
    return getattr(user, "etablissement", None)


def _presence_is_online(presence):
    if presence is None:
        return False
    if getattr(presence, "connection_count", 0) > 0:
        return True
    stamp = getattr(presence, "last_seen_at", None) or getattr(presence, "updated_at", None)
    if stamp is None:
        return False
    return (timezone.now() - stamp) <= timedelta(seconds=90)


class ChatUserLiteSerializer(serializers.ModelSerializer):
    full_name = serializers.SerializerMethodField()
    online = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "username", "full_name", "role", "etablissement", "online"]

    def get_full_name(self, obj):
        full_name = obj.get_full_name().strip()
        return full_name or obj.username

    def get_online(self, obj):
        presence = getattr(obj, "chat_presence", None)
        return _presence_is_online(presence)


class ChatMessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()
    attachment_url = serializers.SerializerMethodField()

    class Meta:
        model = ChatMessage
        fields = [
            "id",
            "conversation",
            "sender",
            "sender_name",
            "message_type",
            "content",
            "created_at",
            "client_message_id",
            "attachment_url",
            "attachment_name",
            "attachment_size",
            "attachment_mime_type",
        ]

    def get_sender_name(self, obj):
        return obj.sender.get_full_name().strip() or obj.sender.username

    def get_attachment_url(self, obj):
        attachment = getattr(obj, "attachment", None)
        if not attachment:
            return None
        try:
            url = attachment.url
        except Exception:
            return None

        request = self.context.get("request") if isinstance(self.context, dict) else None
        if request is None:
            return url
        return request.build_absolute_uri(url)


class ConversationSerializer(serializers.ModelSerializer):
    counterpart = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()
    is_group_admin = serializers.SerializerMethodField()
    group_participants = serializers.SerializerMethodField()
    other_last_read_message_id = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = [
            "id",
            "is_group",
            "title",
            "etablissement",
            "updated_at",
            "counterpart",
            "last_message",
            "unread_count",
            "is_group_admin",
            "group_participants",
            "other_last_read_message_id",
        ]

    def _current_participant(self, obj):
        user = self.context["request"].user
        return obj.participants.filter(user=user).select_related("last_read_message").first()

    def _counterpart_user(self, obj):
        user = self.context["request"].user
        return (
            User.objects.select_related("chat_presence")
            .filter(chat_participations__conversation=obj)
            .exclude(id=user.id)
            .distinct()
            .first()
        )

    def get_counterpart(self, obj):
        if obj.is_group:
            return None
        counterpart = self._counterpart_user(obj)
        if counterpart is None:
            return None
        return ChatUserLiteSerializer(counterpart).data

    def get_last_message(self, obj):
        message = obj.messages.select_related("sender").order_by("-id").first()
        if not message:
            return None
        return ChatMessageSerializer(message).data

    def get_unread_count(self, obj):
        participant = self._current_participant(obj)
        user = self.context["request"].user
        if participant is None:
            return 0

        query = ChatMessage.objects.filter(conversation=obj).exclude(sender=user)
        if participant.last_read_message_id:
            query = query.filter(id__gt=participant.last_read_message_id)
        return query.count()

    def get_is_group_admin(self, obj):
        if not obj.is_group:
            return False
        participant = self._current_participant(obj)
        return bool(participant and participant.is_admin)

    def get_group_participants(self, obj):
        if not obj.is_group:
            return []
        users = (
            User.objects.select_related("chat_presence")
            .filter(chat_participations__conversation=obj)
            .distinct()
            .order_by("first_name", "last_name", "username")
        )
        participant_admins = {
            row.user_id: row.is_admin
            for row in obj.participants.all()
        }
        payload = []
        for user in users:
            payload.append(
                {
                    "id": user.id,
                    "username": user.username,
                    "full_name": user.get_full_name().strip() or user.username,
                    "online": _presence_is_online(getattr(user, "chat_presence", None)),
                    "is_admin": bool(participant_admins.get(user.id, False)),
                }
            )
        return payload

    def get_other_last_read_message_id(self, obj):
        user = self.context["request"].user
        participant_ids = list(
            obj.participants.exclude(user=user).values_list("last_read_message_id", flat=True)
        )
        participant_ids = [value for value in participant_ids if value is not None]
        if not participant_ids:
            return None
        return max(participant_ids)


class DirectConversationCreateSerializer(serializers.Serializer):
    user_id = serializers.IntegerField(min_value=1)

    def validate(self, attrs):
        request_user = self.context["request"].user
        target_id = attrs["user_id"]
        if request_user.id == target_id:
            raise serializers.ValidationError("Impossible de discuter avec soi-meme.")

        target = User.objects.select_related("etablissement").filter(id=target_id).first()
        if target is None:
            raise serializers.ValidationError("Utilisateur introuvable.")

        target_etablissement = _chat_scope_etablissement(self.context["request"])
        if target_etablissement is not None and target.etablissement_id != target_etablissement.id:
            raise serializers.ValidationError("Utilisateur hors etablissement.")

        attrs["target_user"] = target
        return attrs


class GroupConversationCreateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=120)
    participant_ids = serializers.ListField(
        child=serializers.IntegerField(min_value=1),
        allow_empty=False,
    )

    def validate(self, attrs):
        request_user = self.context["request"].user
        title = str(attrs.get("title", "")).strip()
        if not title:
            raise serializers.ValidationError("Le titre du groupe est obligatoire.")
        attrs["title"] = title

        participant_ids = list({int(v) for v in attrs.get("participant_ids", []) if int(v) != request_user.id})
        if not participant_ids:
            raise serializers.ValidationError("Ajoutez au moins un participant.")

        query = User.objects.filter(id__in=participant_ids)
        target_etablissement = _chat_scope_etablissement(self.context["request"])
        if target_etablissement is not None:
            query = query.filter(etablissement=target_etablissement)
        elif getattr(request_user, "role", "") != "super_admin":
            query = query.none()

        users = list(query)
        if len(users) != len(participant_ids):
            raise serializers.ValidationError("Certains participants sont invalides ou hors etablissement.")

        attrs["participants"] = users
        return attrs


class GroupConversationRenameSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=120)

    def validate_title(self, value):
        cleaned = str(value).strip()
        if not cleaned:
            raise serializers.ValidationError("Le titre du groupe est obligatoire.")
        return cleaned


class GroupParticipantMutationSerializer(serializers.Serializer):
    user_id = serializers.IntegerField(min_value=1)
