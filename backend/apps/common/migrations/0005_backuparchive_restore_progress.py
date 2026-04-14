from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("common", "0004_backuparchive"),
    ]

    operations = [
        migrations.AddField(
            model_name="backuparchive",
            name="restore_phase",
            field=models.CharField(blank=True, max_length=120),
        ),
        migrations.AddField(
            model_name="backuparchive",
            name="restore_progress",
            field=models.PositiveSmallIntegerField(default=0),
        ),
    ]
