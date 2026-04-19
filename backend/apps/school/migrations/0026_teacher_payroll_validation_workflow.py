from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0025_attendancesheetvalidation"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name="teacherpayroll",
            name="level_one_validated_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="teacherpayroll",
            name="level_one_validated_by",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="teacher_payroll_level_one_validations",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name="teacherpayroll",
            name="level_two_validated_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="teacherpayroll",
            name="level_two_validated_by",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="teacher_payroll_level_two_validations",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name="teachertimeentry",
            name="auto_closed_reason",
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name="teachertimeentry",
            name="is_auto_closed",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="teachertimeentry",
            name="late_minutes",
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="teachertimeentry",
            name="tolerated_late_minutes",
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AlterField(
            model_name="teachertimeentry",
            name="check_out_time",
            field=models.TimeField(blank=True, null=True),
        ),
    ]
