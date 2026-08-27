"""La fiche de paie decompose son ecart.

`hours_attributed` moins `hours_worked` se lisait sans qu'on sache d'ou
venait la difference: des seances planifiees que personne n'a assurees, ou
des heures faites hors planning. Les deux se pilotent autrement -- l'une
appelle un remplacant, l'autre une regularisation.

Vides sur les fiches deja emises: elles ont ete payees sur ce qu'elles
portaient, et les recalculer changerait un document valide. Les fiches
regenerees, elles, les porteront.
"""

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0038_etablissement_timesheet_late_tolerance_minutes_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='teacherpayroll',
            name='hours_missed',
            field=models.DecimalField(decimal_places=2, default=0, max_digits=8),
        ),
        migrations.AddField(
            model_name='teacherpayroll',
            name='hours_off_schedule',
            field=models.DecimalField(decimal_places=2, default=0, max_digits=8),
        ),
    ]
