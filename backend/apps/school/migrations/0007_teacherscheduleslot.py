from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0006_gradevalidation"),
    ]

    operations = [
        migrations.CreateModel(
            name="TeacherScheduleSlot",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "day_of_week",
                    models.CharField(
                        choices=[
                            ("MON", "Lundi"),
                            ("TUE", "Mardi"),
                            ("WED", "Mercredi"),
                            ("THU", "Jeudi"),
                            ("FRI", "Vendredi"),
                            ("SAT", "Samedi"),
                        ],
                        max_length=3,
                    ),
                ),
                ("start_time", models.TimeField()),
                ("end_time", models.TimeField()),
                ("room", models.CharField(blank=True, max_length=60)),
                (
                    "assignment",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="schedule_slots",
                        to="school.teacherassignment",
                    ),
                ),
            ],
            options={
                "ordering": ("day_of_week", "start_time", "end_time", "id"),
            },
        ),
        migrations.AlterUniqueTogether(
            name="teacherscheduleslot",
            unique_together={("assignment", "day_of_week", "start_time", "end_time")},
        ),
    ]
