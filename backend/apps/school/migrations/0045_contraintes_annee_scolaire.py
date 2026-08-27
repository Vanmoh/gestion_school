"""Les garde-fous de l'annee scolaire, poses apres la reprise de donnees.

Ils vivaient dans la migration precedente, avec l'eclatement par
etablissement. Mais celle-ci supprime l'ancienne annee partagee une fois
videe, et un DELETE laisse des declencheurs de cle etrangere en attente:
Postgres refuse alors de creer un index dans la meme transaction
(« cannot CREATE INDEX because it has pending trigger events »).
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0044_academic_year_par_etablissement'),
    ]

    operations = [
        migrations.AddConstraint(
            model_name='academicyear',
            constraint=models.UniqueConstraint(
                condition=models.Q(('is_active', True)),
                fields=('etablissement',),
                name='une_seule_annee_active_par_etablissement',
            ),
        ),
        migrations.AddConstraint(
            model_name='academicyear',
            constraint=models.CheckConstraint(
                condition=models.Q(('end_date__gt', models.F('start_date'))),
                name='annee_scolaire_fin_apres_debut',
            ),
        ),
    ]
