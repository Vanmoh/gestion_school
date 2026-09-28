"""Une matiere ne se confie qu'a un enseignant a la fois.

C'est la regle de l'ecole, et elle n'etait ecrite nulle part.
`TeacherAssignment` portait `unique_together = ("teacher", "subject",
"classroom")`: cela interdit d'affecter deux fois le meme enseignant a la meme
matiere, mais laisse passer **deux enseignants differents**. Rien, ni dans le
modele ni dans l'API, ne s'y opposait.

Les consequences ne se voyaient pas la ou elles naissaient. Sur la base de
developpement, huit matieres par classe avaient deux titulaires -- heritees de
peuplements successifs -- et l'emploi du temps devenait infaisable: quatorze
matieres, vingt-deux affectations, chacune reclamant le volume horaire de sa
matiere. Trente-six heures posees pour une grille de trente-six places, plus
aucune marge, et trente et un enseignants qui finissaient l'annee sans une seule
heure de cours alors que chaque grille s'affichait « complete ». Un bulletin, lui,
ne dit pas qui enseigne: le defaut restait invisible.

La migration se fait en deux temps, et l'ordre est contraint: on ne peut pas
poser la contrainte sur une base qui la viole.

1. **on tranche entre les concurrents.** On garde celui qui enseigne reellement
   -- le plus d'heures a l'emploi du temps -- et, a egalite, le plus ancien: son
   affectation est le choix que l'ecole avait fait en premier. Les creneaux des
   autres tombent en cascade avec leur affectation, ce qui est voulu: un creneau
   d'un enseignant qui ne tient plus la matiere n'a pas de sens;
2. **on pose la contrainte**, pour que l'application ne puisse pas recreer
   demain ce qu'on nettoie aujourd'hui.

Le retour en arriere retire la contrainte et ne rend pas les affectations
supprimees -- il ne peut pas: leur trace n'existe plus. C'est la seule chose
qu'une migration de donnees ne sait pas defaire, et elle doit etre dite.
"""

from django.db import migrations, models
from django.db.models import Count


def trancher_entre_les_concurrents(apps, schema_editor):
    TeacherAssignment = apps.get_model("school", "TeacherAssignment")

    doublons = (
        TeacherAssignment.objects.values("subject_id", "classroom_id")
        .annotate(combien=Count("id"))
        .filter(combien__gt=1)
    )

    retirees = 0
    for groupe in doublons:
        concurrentes = list(
            TeacherAssignment.objects.filter(
                subject_id=groupe["subject_id"], classroom_id=groupe["classroom_id"]
            ).annotate(heures=Count("schedule_slots"))
        )
        # Le plus d'heures posees d'abord; a egalite, le plus petit `id`, donc la
        # plus ancienne. `-a.id` dans la cle de tri fait que `max` retient bien
        # la plus ancienne et non la plus recente.
        gardee = max(concurrentes, key=lambda a: (a.heures, -a.id))
        for affectation in concurrentes:
            if affectation.id != gardee.id:
                affectation.delete()
                retirees += 1

    if retirees:
        print(
            f"  {retirees} affectation(s) en doublon retiree(s): "
            "une matiere, un enseignant."
        )


def ne_rien_rendre(apps, schema_editor):
    """Le retour en arriere ne rend pas ce qui a ete supprime, et le dit."""
    return None


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0070_le_lycee_oumar_bah_porte_son_nom"),
    ]

    operations = [
        migrations.RunPython(trancher_entre_les_concurrents, ne_rien_rendre),
        migrations.AddConstraint(
            model_name="teacherassignment",
            constraint=models.UniqueConstraint(
                fields=["subject", "classroom"],
                name="une_matiere_un_enseignant",
            ),
        ),
    ]
