"""La bibliotheque numerique s'ouvre au televersement.

Jusqu'ici le fonds n'entrait que par la commande d'import: un catalogue
commun a toutes les ecoles, ou `source_url` portait l'unicite. Un document
depose depuis l'application n'a pas de source -- il arrive avec son fichier.
L'unicite passe donc en contrainte conditionnelle, et l'etagere se cloisonne:
`etablissement` vide reste le fonds commun, renseigne il designe une ecole.
"""

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


def marquer_le_fonds_existant_comme_importe(apps, schema_editor):
    """Tout ce qui est deja en base vient de l'import, par construction.

    La colonne `origin` naît avec « upload » pour defaut -- c'est le cas de
    tout ce qui arrivera par l'API. Les lignes anterieures, elles, ne
    peuvent venir que de la commande: sans cette reprise, les 1257 documents
    du fonds commun s'annonceraient comme deposes par une ecole.
    """
    LibraryDocument = apps.get_model("school", "LibraryDocument")
    LibraryDocument.objects.update(origin="import")


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0033_alter_librarydocument_file'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='librarycollection',
            name='etablissement',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='library_collections', to='school.etablissement'),
        ),
        migrations.AddField(
            model_name='librarydocument',
            name='description',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='librarydocument',
            name='etablissement',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='library_documents', to='school.etablissement'),
        ),
        migrations.AddField(
            model_name='librarydocument',
            name='origin',
            field=models.CharField(choices=[('import', 'Fonds importé'), ('upload', "Ajouté par l'établissement")], default='upload', max_length=10),
        ),
        migrations.AddField(
            model_name='librarydocument',
            name='uploaded_by',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='library_documents', to=settings.AUTH_USER_MODEL),
        ),
        migrations.RunPython(
            marquer_le_fonds_existant_comme_importe,
            migrations.RunPython.noop,
        ),
        migrations.AlterField(
            model_name='librarycollection',
            name='code',
            field=models.CharField(max_length=40),
        ),
        migrations.AlterField(
            model_name='librarydocument',
            name='source_url',
            field=models.URLField(blank=True, max_length=500),
        ),
        migrations.AddConstraint(
            model_name='librarycollection',
            constraint=models.UniqueConstraint(condition=models.Q(('etablissement__isnull', True)), fields=('code',), name='library_collection_code_unique_commun'),
        ),
        migrations.AddConstraint(
            model_name='librarycollection',
            constraint=models.UniqueConstraint(condition=models.Q(('etablissement__isnull', False)), fields=('etablissement', 'code'), name='library_collection_code_unique_par_etablissement'),
        ),
        migrations.AddConstraint(
            model_name='librarydocument',
            constraint=models.UniqueConstraint(condition=models.Q(('source_url', ''), _negated=True), fields=('source_url',), name='library_document_source_url_unique'),
        ),
    ]
