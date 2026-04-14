from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0017_grade_homework_scores_and_examresult_constraint"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="PromotionRun",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "status",
                    models.CharField(
                        choices=[("simulated", "Simulation"), ("executed", "Execute")],
                        default="simulated",
                        max_length=20,
                    ),
                ),
                ("min_average", models.DecimalField(decimal_places=2, default=10, max_digits=5)),
                ("min_conduite", models.DecimalField(decimal_places=2, default=10, max_digits=5)),
                ("total_students", models.PositiveIntegerField(default=0)),
                ("promoted_count", models.PositiveIntegerField(default=0)),
                ("repeated_count", models.PositiveIntegerField(default=0)),
                ("archived_count", models.PositiveIntegerField(default=0)),
                ("payload", models.JSONField(blank=True, default=dict)),
                (
                    "etablissement",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="promotion_runs",
                        to="school.etablissement",
                    ),
                ),
                (
                    "executed_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="promotion_runs",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "source_academic_year",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="promotion_runs_source",
                        to="school.academicyear",
                    ),
                ),
                (
                    "target_academic_year",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="promotion_runs_target",
                        to="school.academicyear",
                    ),
                ),
            ],
        ),
        migrations.CreateModel(
            name="PromotionDecision",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "decision",
                    models.CharField(
                        choices=[("promoted", "Promu"), ("repeated", "Redouble"), ("archived", "Archive")],
                        max_length=20,
                    ),
                ),
                ("average", models.DecimalField(decimal_places=2, default=0, max_digits=5)),
                ("conduite", models.DecimalField(decimal_places=2, default=0, max_digits=5)),
                ("rank", models.PositiveIntegerField(default=0)),
                ("reason", models.CharField(blank=True, max_length=255)),
                (
                    "run",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="decisions",
                        to="school.promotionrun",
                    ),
                ),
                (
                    "source_classroom",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="promotion_decisions_source",
                        to="school.classroom",
                    ),
                ),
                (
                    "student",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="promotion_decisions",
                        to="school.student",
                    ),
                ),
                (
                    "target_classroom",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="promotion_decisions_target",
                        to="school.classroom",
                    ),
                ),
            ],
            options={
                "unique_together": {("run", "student")},
            },
        ),
        migrations.AddIndex(
            model_name="promotionrun",
            index=models.Index(fields=["etablissement", "-created_at"], name="promrun_etab_created_idx"),
        ),
        migrations.AddIndex(
            model_name="promotionrun",
            index=models.Index(fields=["status", "-created_at"], name="promrun_status_created_idx"),
        ),
        migrations.AddIndex(
            model_name="promotiondecision",
            index=models.Index(fields=["run", "decision"], name="promdec_run_decision_idx"),
        ),
        migrations.AddIndex(
            model_name="promotiondecision",
            index=models.Index(fields=["source_classroom", "decision"], name="promdec_source_decision_idx"),
        ),
    ]
