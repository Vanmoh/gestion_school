"""Le planning garde la raison d'un placement hors disponibilite.

Les declarations des enseignants etaient collectees puis oubliees: rien dans
l'emploi du temps ne les consultait. Placer un cours en dehors reste une
decision de l'administration -- elle arbitre entre des contraintes que
l'enseignant ne connait pas --, mais elle laisse desormais une trace, et
c'est elle qui permet d'en rediscuter a la rentree suivante.

Vide sur tout l'existant: aucun creneau deja place n'est remis en cause.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0041_teacheravailabilityslot_kind_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='teacherscheduleslot',
            name='off_availability_reason',
            field=models.CharField(blank=True, max_length=255),
        ),
    ]
