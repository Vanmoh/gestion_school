"""Le catalogue papier gagne de quoi retrouver un ouvrage en rayon.

Editeur, annee d'edition, matiere et cote: tous facultatifs, tous vides pour
l'existant. Une fiche ne portait que titre, auteur et ISBN, et « l'edition de
2019 rangee etagere B » ne se retrouvait qu'en connaissant le fonds par
coeur.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0035_etablissement_library_penalty_per_day_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='book',
            name='published_year',
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='book',
            name='publisher',
            field=models.CharField(blank=True, max_length=120),
        ),
        migrations.AddField(
            model_name='book',
            name='shelf_location',
            field=models.CharField(blank=True, max_length=60),
        ),
        migrations.AddField(
            model_name='book',
            name='subject',
            field=models.CharField(blank=True, max_length=120),
        ),
    ]
