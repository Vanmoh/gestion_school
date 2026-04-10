from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("common", "0001_activitylog"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="activitylog",
            index=models.Index(fields=["-created_at"], name="actlog_created_desc_idx"),
        ),
        migrations.AddIndex(
            model_name="activitylog",
            index=models.Index(fields=["user", "-created_at"], name="actlog_user_created_idx"),
        ),
        migrations.AddIndex(
            model_name="activitylog",
            index=models.Index(fields=["module", "-created_at"], name="actlog_module_created_idx"),
        ),
        migrations.AddIndex(
            model_name="activitylog",
            index=models.Index(fields=["success", "-created_at"], name="actlog_success_created_idx"),
        ),
    ]
