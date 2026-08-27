"""La disponibilite gagne sa nuance et sa raison.

Un enseignant etait disponible, ou rien: le modele ne connaissait que des
creneaux positifs, et rien ne distinguait « je ne peux pas » de « je n'ai pas
repondu ». `kind` porte les trois etats, `note` la raison que l'enseignant
veut faire savoir.

L'existant prend « possible » par defaut: c'est exactement ce qu'une ligne
declaree signifiait jusqu'ici, ni plus ni moins. Personne ne se retrouve
promu volontaire ni declare indisponible par une migration.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0040_alter_teacheravailabilityslot_unique_together'),
    ]

    operations = [
        migrations.AddField(
            model_name='teacheravailabilityslot',
            name='kind',
            field=models.CharField(choices=[('preferred', 'Préférée'), ('possible', 'Possible'), ('unavailable', 'Indisponible')], default='possible', max_length=12),
        ),
        migrations.AddField(
            model_name='teacheravailabilityslot',
            name='note',
            field=models.CharField(blank=True, max_length=255),
        ),
    ]
