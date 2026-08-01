from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0002_user_etablissement"),
    ]

    operations = [
        migrations.AlterField(
            model_name="user",
            name="role",
            field=models.CharField(
                choices=[
                    ("super_admin", "Super Admin"),
                    ("director", "Directeur/Proviseur"),
                    ("promoter", "Promoteur"),
                    ("censor", "Censeur"),
                    ("accountant", "Comptable"),
                    ("teacher", "Enseignant"),
                    ("supervisor", "Surveillant"),
                    ("parent", "Parent"),
                    ("student", "Élève"),
                ],
                max_length=20,
            ),
        ),
    ]
