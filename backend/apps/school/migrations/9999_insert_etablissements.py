from django.db import migrations

def create_etablissements(apps, schema_editor):
    Etablissement = apps.get_model('school', 'Etablissement')
    etablissements = [
        {"name": "Lycée Technique Oumar Bah (LTOB)"},
        {"name": "Lycée Technique Oumar Bah (LOBK)"},
        {"name": "IFP-OBK"},
        {"name": "Complexe Scolaire Omar Bah (CSOB)"},
    ]
    for etab in etablissements:
        Etablissement.objects.get_or_create(name=etab["name"])

class Migration(migrations.Migration):
    dependencies = [
        ('school', '0010_etablissement_book_etablissement_and_more'),
    ]
    operations = [
        migrations.RunPython(create_etablissements),
    ]