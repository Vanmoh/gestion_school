from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0019_teacher_hourly_pointage_payroll"),
    ]

    operations = [
        migrations.AlterField(
            model_name="subject",
            name="code",
            field=models.CharField(max_length=20),
        ),
        migrations.AddField(
            model_name="subject",
            name="classroom",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="subjects",
                to="school.classroom",
            ),
        ),
        migrations.AddConstraint(
            model_name="subject",
            constraint=models.UniqueConstraint(
                fields=("classroom", "code"),
                name="uniq_subject_code_per_classroom",
            ),
        ),
    ]
