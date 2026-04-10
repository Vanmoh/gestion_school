from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0015_teacheravailabilityslot"),
        ("common", "0002_activitylog_indexes"),
    ]

    operations = [
        migrations.AddField(
            model_name="activitylog",
            name="etablissement",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                to="school.etablissement",
            ),
        ),
        migrations.AddIndex(
            model_name="activitylog",
            index=models.Index(fields=["etablissement", "-created_at"], name="actlog_etab_created_idx"),
        ),
    ]
