from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("chat", "0003_chatmessage_client_message_id"),
    ]

    operations = [
        migrations.AddField(
            model_name="chatmessage",
            name="attachment",
            field=models.FileField(blank=True, null=True, upload_to="chat_attachments/"),
        ),
        migrations.AddField(
            model_name="chatmessage",
            name="attachment_mime_type",
            field=models.CharField(blank=True, max_length=120),
        ),
        migrations.AddField(
            model_name="chatmessage",
            name="attachment_name",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name="chatmessage",
            name="attachment_size",
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="chatmessage",
            name="message_type",
            field=models.CharField(
                choices=[("text", "Texte"), ("file", "Fichier")],
                default="text",
                max_length=10,
            ),
        ),
        migrations.AlterField(
            model_name="chatmessage",
            name="content",
            field=models.TextField(blank=True),
        ),
    ]