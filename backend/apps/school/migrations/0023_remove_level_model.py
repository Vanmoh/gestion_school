from django.db import migrations


def rename_duplicate_classrooms_before_level_drop(apps, schema_editor):
    ClassRoom = apps.get_model("school", "ClassRoom")

    grouped = {}
    for classroom in ClassRoom.objects.all().order_by("id"):
        key = (classroom.name, classroom.academic_year_id, classroom.etablissement_id)
        grouped.setdefault(key, []).append(classroom)

    fields_to_update = ["name", "updated_at"]
    for classrooms in grouped.values():
        if len(classrooms) <= 1:
            continue

        for index, classroom in enumerate(classrooms, start=1):
            if index == 1:
                continue
            suffix = f" {index}"
            max_len = 50 - len(suffix)
            classroom.name = f"{classroom.name[:max_len]}{suffix}"

        ClassRoom.objects.bulk_update(classrooms[1:], fields_to_update)


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0022_remove_section_model"),
    ]

    operations = [
        migrations.RunPython(
            rename_duplicate_classrooms_before_level_drop,
            migrations.RunPython.noop,
        ),
        migrations.AlterUniqueTogether(
            name="classroom",
            unique_together={("name", "academic_year", "etablissement")},
        ),
        migrations.RemoveField(
            model_name="classroom",
            name="level",
        ),
        migrations.DeleteModel(
            name="Level",
        ),
    ]
