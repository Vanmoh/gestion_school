from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="ActivityLog",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("role", models.CharField(blank=True, max_length=20)),
                ("action", models.CharField(max_length=120)),
                ("method", models.CharField(max_length=10)),
                ("path", models.CharField(max_length=255)),
                ("module", models.CharField(blank=True, max_length=80)),
                ("target", models.CharField(blank=True, max_length=120)),
                ("status_code", models.PositiveIntegerField(default=0)),
                ("success", models.BooleanField(default=True)),
                ("ip_address", models.CharField(blank=True, max_length=45)),
                ("user_agent", models.CharField(blank=True, max_length=255)),
                ("details", models.TextField(blank=True)),
                (
                    "user",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at", "-id"],
            },
        ),
    ]
