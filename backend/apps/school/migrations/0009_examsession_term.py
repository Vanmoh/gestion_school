from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0008_timetablepublication"),
    ]

    operations = [
        migrations.AddField(
            model_name="examsession",
            name="term",
            field=models.CharField(default="T1", max_length=2),
        ),
    ]
