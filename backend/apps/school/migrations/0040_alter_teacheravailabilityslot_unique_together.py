"""Une disponibilite se partage, elle ne se reserve pas.

L'unicite portait sur (etablissement, jour, debut, fin) -- sans l'enseignant.
Le premier a declarer « lundi 08:00-10:00 » devenait donc proprietaire
exclusif de ce creneau pour toute son ecole, et le suivant se heurtait a une
erreur d'integrite en base. Dans un etablissement de vingt enseignants, le
module cessait d'etre utilisable des le deuxieme repondant.

Or dix enseignants sont disponibles le lundi a huit heures, et c'est
exactement ce que l'administration a besoin de savoir pour arbitrer son
planning. L'unicite passe donc sur (enseignant, jour, debut, fin): chacun ne
declare pas deux fois le meme creneau, et ne prive personne du sien.

La nouvelle contrainte est plus permissive que l'ancienne: aucune ligne
existante ne peut la violer, il n'y a rien a reprendre.
"""

from django.db import migrations


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0039_teacherpayroll_hours_missed_and_more'),
    ]

    operations = [
        migrations.AlterUniqueTogether(
            name='teacheravailabilityslot',
            unique_together={('teacher', 'day_of_week', 'start_time', 'end_time')},
        ),
    ]
