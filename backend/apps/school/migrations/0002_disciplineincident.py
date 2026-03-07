from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("school", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="DisciplineIncident",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("incident_date", models.DateField()),
                ("category", models.CharField(max_length=120)),
                ("description", models.TextField()),
                (
                    "severity",
                    models.CharField(
                        choices=[("low", "Faible"), ("medium", "Moyenne"), ("high", "Élevée")],
                        default="medium",
                        max_length=10,
                    ),
                ),
                ("sanction", models.TextField(blank=True)),
                (
                    "status",
                    models.CharField(
                        choices=[("open", "Ouvert"), ("resolved", "Traité")],
                        default="open",
                        max_length=10,
                    ),
                ),
                ("parent_notified", models.BooleanField(default=False)),
                (
                    "reported_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="discipline_reports",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "student",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="discipline_incidents",
                        to="school.student",
                    ),
                ),
            ],
            options={
                "abstract": False,
            },
        ),
    ]
