from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0018_promotionrun_promotiondecision"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name="teacher",
            name="hourly_rate",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=12),
        ),
        migrations.AddField(
            model_name="teacherpayroll",
            name="hours_attributed",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=8),
        ),
        migrations.AddField(
            model_name="teacherpayroll",
            name="hours_worked",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=8),
        ),
        migrations.AddField(
            model_name="teacherpayroll",
            name="hourly_rate",
            field=models.DecimalField(decimal_places=2, default=0, max_digits=12),
        ),
        migrations.AddField(
            model_name="teacherpayroll",
            name="notes",
            field=models.TextField(blank=True),
        ),
        migrations.AlterField(
            model_name="teacherpayroll",
            name="paid_on",
            field=models.DateField(blank=True, null=True),
        ),
        migrations.CreateModel(
            name="TeacherTimeEntry",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("entry_date", models.DateField()),
                ("check_in_time", models.TimeField()),
                ("check_out_time", models.TimeField()),
                ("worked_hours", models.DecimalField(decimal_places=2, default=0, max_digits=8)),
                ("notes", models.CharField(blank=True, max_length=255)),
                (
                    "etablissement",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="teacher_time_entries",
                        to="school.etablissement",
                    ),
                ),
                (
                    "recorded_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="recorded_teacher_time_entries",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "teacher",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="time_entries",
                        to="school.teacher",
                    ),
                ),
            ],
        ),
        migrations.AddIndex(
            model_name="teachertimeentry",
            index=models.Index(fields=["teacher", "entry_date"], name="ttentry_teacher_date_idx"),
        ),
        migrations.AddIndex(
            model_name="teachertimeentry",
            index=models.Index(fields=["etablissement", "entry_date"], name="ttentry_etab_date_idx"),
        ),
    ]
