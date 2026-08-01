from django.db import migrations, models
from django.db.models import Q


class Migration(migrations.Migration):

    dependencies = [
        ("chat", "0002_conversationparticipant_is_admin"),
    ]

    operations = [
        migrations.AddField(
            model_name="chatmessage",
            name="client_message_id",
            field=models.CharField(blank=True, max_length=64, null=True),
        ),
        migrations.AddConstraint(
            model_name="chatmessage",
            constraint=models.UniqueConstraint(
                condition=Q(client_message_id__isnull=False) & ~Q(client_message_id=""),
                fields=("conversation", "sender", "client_message_id"),
                name="uniq_chatmsg_conv_sender_clientmsg",
            ),
        ),
    ]
