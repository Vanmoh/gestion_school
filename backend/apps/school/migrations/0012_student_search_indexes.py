from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0011_performance_indexes"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="student",
            index=models.Index(
                fields=["etablissement", "is_archived", "classroom"],
                name="student_etab_arch_class_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="student",
            index=models.Index(
                fields=["enrollment_date"],
                name="student_enroll_date_idx",
            ),
        ),
    ]
