from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0014_student_conduite"),
    ]

    operations = [
        migrations.CreateModel(
            name="TeacherAvailabilitySlot",
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
                (
                    "etablissement",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="teacher_availability_slots",
                        to="school.etablissement",
                    ),
                ),
                (
                    "teacher",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="availability_slots",
                        to="school.teacher",
                    ),
                ),
            ],
            options={
                "ordering": ("day_of_week", "start_time", "end_time", "id"),
                "unique_together": {("etablissement", "day_of_week", "start_time", "end_time")},
            },
        ),
        migrations.AddIndex(
            model_name="teacheravailabilityslot",
            index=models.Index(
                fields=["etablissement", "day_of_week", "start_time", "end_time"],
                name="teacheravail_etab_day_time_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="teacheravailabilityslot",
            index=models.Index(fields=["teacher", "day_of_week"], name="teacheravail_teacher_day_idx"),
        ),
    ]
