from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0015_teacheravailabilityslot"),
    ]

    operations = [
        migrations.AddField(
            model_name="announcement",
            name="etablissement",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="announcements",
                to="school.etablissement",
            ),
        ),
        migrations.AddField(
            model_name="notification",
            name="etablissement",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="notifications",
                to="school.etablissement",
            ),
        ),
        migrations.AddField(
            model_name="smsproviderconfig",
            name="etablissement",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="sms_provider_configs",
                to="school.etablissement",
            ),
        ),
        migrations.AddField(
            model_name="supplier",
            name="etablissement",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="suppliers",
                to="school.etablissement",
            ),
        ),
        migrations.AddField(
            model_name="stockitem",
            name="etablissement",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="stock_items",
                to="school.etablissement",
            ),
        ),
    ]
