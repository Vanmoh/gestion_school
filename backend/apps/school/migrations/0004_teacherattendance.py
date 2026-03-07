from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0003_canteen_models"),
    ]

    operations = [
        migrations.CreateModel(
            name="TeacherAttendance",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("date", models.DateField()),
                ("is_absent", models.BooleanField(default=False)),
                ("is_late", models.BooleanField(default=False)),
                ("reason", models.CharField(blank=True, max_length=255)),
                ("proof", models.FileField(blank=True, null=True, upload_to="teacher_attendance_proofs/")),
                (
                    "teacher",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="attendances",
                        to="school.teacher",
                    ),
                ),
            ],
            options={"abstract": False},
        ),
    ]
