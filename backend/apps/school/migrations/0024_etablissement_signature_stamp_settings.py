from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0023_remove_level_model"),
    ]

    operations = [
        migrations.AddField(
            model_name="etablissement",
            name="cashier_signature_image",
            field=models.ImageField(blank=True, null=True, upload_to="etablissements/signatures/"),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="cashier_signature_label",
            field=models.CharField(blank=True, default="Signature caissier", max_length=120),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="parent_signature_label",
            field=models.CharField(blank=True, default="Signature parent / eleve", max_length=120),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="principal_signature_image",
            field=models.ImageField(blank=True, null=True, upload_to="etablissements/signatures/"),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="principal_signature_label",
            field=models.CharField(blank=True, default="Le Principal", max_length=120),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="principal_signature_position",
            field=models.CharField(
                choices=[("left", "Gauche"), ("center", "Centre"), ("right", "Droite")],
                default="right",
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="principal_signature_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[MinValueValidator(40), MaxValueValidator(200)],
            ),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="stamp_image",
            field=models.ImageField(blank=True, null=True, upload_to="etablissements/stamps/"),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="stamp_position",
            field=models.CharField(
                choices=[("left", "Gauche"), ("center", "Centre"), ("right", "Droite")],
                default="right",
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name="etablissement",
            name="stamp_scale",
            field=models.PositiveSmallIntegerField(
                default=100,
                validators=[MinValueValidator(40), MaxValueValidator(200)],
            ),
        ),
    ]
