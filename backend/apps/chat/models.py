from django.conf import settings
from django.db import models

from apps.common.models import TimeStampedModel


class Conversation(TimeStampedModel):
    etablissement = models.ForeignKey(
        "school.Etablissement",
        on_delete=models.PROTECT,
        related_name="chat_conversations",
        null=True,
        blank=True,
    )
    is_group = models.BooleanField(default=False)
    title = models.CharField(max_length=120, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["etablissement", "-updated_at"], name="chatconv_etab_updated_idx"),
        ]


class ConversationParticipant(TimeStampedModel):
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name="participants",
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="chat_participations",
    )
    last_read_message = models.ForeignKey(
        "ChatMessage",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="read_by_participants",
    )
    is_admin = models.BooleanField(default=False)

    class Meta:
        unique_together = ("conversation", "user")
        indexes = [
            models.Index(fields=["user", "-updated_at"], name="chatpart_user_updated_idx"),
        ]


class ChatMessage(TimeStampedModel):
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name="messages",
    )
    sender = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="chat_messages",
    )
    content = models.TextField()
    client_message_id = models.CharField(max_length=64, blank=True, null=True)

    class Meta:
        ordering = ["id"]
        constraints = [
            models.UniqueConstraint(
                fields=["conversation", "sender", "client_message_id"],
                condition=models.Q(client_message_id__isnull=False) & ~models.Q(client_message_id=""),
                name="uniq_chatmsg_conv_sender_clientmsg",
            )
        ]
        indexes = [
            models.Index(fields=["conversation", "-id"], name="chatmsg_conv_id_desc_idx"),
            models.Index(fields=["sender", "-created_at"], name="chatmsg_sender_created_idx"),
        ]


class ChatPresence(TimeStampedModel):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="chat_presence",
    )
    is_online = models.BooleanField(default=False)
    connection_count = models.PositiveIntegerField(default=0)
    last_seen_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["is_online", "-updated_at"], name="chatpres_on_upd_idx"),
        ]
