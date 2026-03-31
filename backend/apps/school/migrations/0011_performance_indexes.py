from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("school", "9999_insert_etablissements"),
    ]

    operations = [
        migrations.AddIndex(
            model_name="student",
            index=models.Index(fields=["etablissement", "-created_at"], name="student_etab_created_idx"),
        ),
        migrations.AddIndex(
            model_name="student",
            index=models.Index(fields=["classroom", "is_archived"], name="student_class_arch_idx"),
        ),
        migrations.AddIndex(
            model_name="student",
            index=models.Index(fields=["parent"], name="student_parent_idx"),
        ),
        migrations.AddIndex(
            model_name="attendance",
            index=models.Index(fields=["student", "date"], name="attendance_student_date_idx"),
        ),
        migrations.AddIndex(
            model_name="attendance",
            index=models.Index(fields=["date", "is_absent"], name="attendance_date_abs_idx"),
        ),
        migrations.AddIndex(
            model_name="teacherattendance",
            index=models.Index(fields=["teacher", "date"], name="teachatt_teacher_date_idx"),
        ),
        migrations.AddIndex(
            model_name="teacherattendance",
            index=models.Index(fields=["date", "is_absent"], name="teachatt_date_abs_idx"),
        ),
        migrations.AddIndex(
            model_name="disciplineincident",
            index=models.Index(fields=["student", "-incident_date"], name="discipline_student_date_idx"),
        ),
        migrations.AddIndex(
            model_name="disciplineincident",
            index=models.Index(fields=["status", "-incident_date"], name="discipline_status_date_idx"),
        ),
        migrations.AddIndex(
            model_name="studentfee",
            index=models.Index(fields=["student", "-due_date"], name="studentfee_student_due_idx"),
        ),
        migrations.AddIndex(
            model_name="studentfee",
            index=models.Index(fields=["academic_year", "-due_date"], name="studentfee_year_due_idx"),
        ),
        migrations.AddIndex(
            model_name="payment",
            index=models.Index(fields=["etablissement", "-created_at"], name="payment_etab_created_idx"),
        ),
        migrations.AddIndex(
            model_name="payment",
            index=models.Index(fields=["fee", "-created_at"], name="payment_fee_created_idx"),
        ),
        migrations.AddIndex(
            model_name="payment",
            index=models.Index(fields=["method"], name="payment_method_idx"),
        ),
    ]
