from django.db import migrations, models


def _table_exists(connection, table_name):
    with connection.cursor() as cursor:
        return table_name in connection.introspection.table_names(cursor)


def _column_exists(connection, table_name, column_name):
    if not _table_exists(connection, table_name):
        return False
    with connection.cursor() as cursor:
        columns = connection.introspection.get_table_description(cursor, table_name)
    return any(column.name == column_name for column in columns)


def _constraint_exists(connection, table_name, constraint_name):
    if not _table_exists(connection, table_name):
        return False
    with connection.cursor() as cursor:
        constraints = connection.introspection.get_constraints(cursor, table_name)
    return constraint_name in constraints


def add_homework_scores_column_if_missing(apps, schema_editor):
    connection = schema_editor.connection
    table_name = "school_grade"
    column_name = "homework_scores"

    if _column_exists(connection, table_name, column_name):
        return

    if connection.vendor != "mysql":
        Grade = apps.get_model("school", "Grade")
        field = models.JSONField(blank=True, default=list)
        field.set_attributes_from_name(column_name)
        schema_editor.add_field(Grade, field)
        return

    quoted_table = schema_editor.quote_name(table_name)
    quoted_column = schema_editor.quote_name(column_name)

    # JSON defaults are not consistently supported across MySQL versions,
    # so add nullable first, backfill, then enforce NOT NULL.
    schema_editor.execute(
        f"ALTER TABLE {quoted_table} ADD COLUMN {quoted_column} JSON NULL"
    )
    schema_editor.execute(
        f"UPDATE {quoted_table} SET {quoted_column} = JSON_ARRAY() WHERE {quoted_column} IS NULL"
    )
    schema_editor.execute(
        f"ALTER TABLE {quoted_table} MODIFY COLUMN {quoted_column} JSON NOT NULL"
    )


def add_exam_result_unique_constraint_if_missing(apps, schema_editor):
    connection = schema_editor.connection
    table_name = "school_examresult"
    constraint_name = "uniq_exam_result_session_student_subject"

    if _constraint_exists(connection, table_name, constraint_name):
        return

    quoted_table = schema_editor.quote_name(table_name)
    quoted_constraint = schema_editor.quote_name(constraint_name)
    quoted_session = schema_editor.quote_name("session_id")
    quoted_student = schema_editor.quote_name("student_id")
    quoted_subject = schema_editor.quote_name("subject_id")

    if connection.vendor == "sqlite":
        schema_editor.execute(
            "CREATE UNIQUE INDEX IF NOT EXISTS "
            f"{quoted_constraint} "
            "ON "
            f"{quoted_table} "
            "("
            f"{quoted_session}, {quoted_student}, {quoted_subject}"
            ")"
        )
        return

    schema_editor.execute(
        "ALTER TABLE "
        f"{quoted_table} "
        "ADD CONSTRAINT "
        f"{quoted_constraint} "
        "UNIQUE ("
        f"{quoted_session}, {quoted_student}, {quoted_subject}"
        ")"
    )


def noop_reverse(apps, schema_editor):
    return


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0016_multi_etablissement_communication_stock"),
        ("school", "9999_insert_etablissements"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(
                    add_homework_scores_column_if_missing,
                    reverse_code=noop_reverse,
                ),
            ],
            state_operations=[
                migrations.AddField(
                    model_name="grade",
                    name="homework_scores",
                    field=models.JSONField(blank=True, default=list),
                ),
            ],
        ),
        migrations.SeparateDatabaseAndState(
            database_operations=[
                migrations.RunPython(
                    add_exam_result_unique_constraint_if_missing,
                    reverse_code=noop_reverse,
                ),
            ],
            state_operations=[
                migrations.AddConstraint(
                    model_name="examresult",
                    constraint=models.UniqueConstraint(
                        fields=("session", "student", "subject"),
                        name="uniq_exam_result_session_student_subject",
                    ),
                ),
            ],
        ),
    ]
