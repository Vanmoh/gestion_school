from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0020_subject_class_scoped"),
    ]

    operations = [
        migrations.AlterField(
            model_name="classroom",
            name="section",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="classes",
                to="school.section",
            ),
        ),
    ]
