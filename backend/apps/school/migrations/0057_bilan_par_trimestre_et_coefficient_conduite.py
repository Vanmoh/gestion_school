"""Le bilan academique gagne sa periode, et la conduite son coefficient.

Les lignes deja en base restent sur `term` vide, c'est-a-dire le bilan de
l'annee entiere. C'est le choix le moins faux: elles ont ete ecrites par la
derniere cloture ou par une promotion, et rien ne permet de dire retrospective-
ment de quel trimestre elles parlent. Un bulletin ancien affichera donc « - »
au lieu d'un rang, jusqu'a ce que `manage.py recalculer_rangs` reconstruise
les bilans trimestriels -- mieux vaut pas de rang qu'un rang faux.
"""

import django.core.validators
from django.db import migrations, models


def deduplique_les_bilans(apps, schema_editor):
    """Ecarte les doublons que l'absence de contrainte laissait passer.

    `update_or_create` ne protege de rien sans unicite en base: deux clotures
    simultanees sur la meme classe pouvaient inserer deux lignes pour un meme
    eleve. La contrainte ajoutee juste apres refuserait de se poser dessus.

    La plus recemment mise a jour l'emporte: c'est la derniere que
    l'etablissement a vue a l'ecran.
    """
    Historique = apps.get_model("school", "StudentAcademicHistory")

    vus = set()
    a_supprimer = []
    for ligne in Historique.objects.order_by("-updated_at", "-id").values(
        "id", "student_id", "academic_year_id", "classroom_id", "term"
    ):
        cle = (
            ligne["student_id"],
            ligne["academic_year_id"],
            ligne["classroom_id"],
            ligne["term"],
        )
        if cle in vus:
            a_supprimer.append(ligne["id"])
            continue
        vus.add(cle)

    if a_supprimer:
        Historique.objects.filter(id__in=a_supprimer).delete()


def ne_rien_defaire(apps, schema_editor):
    """Rien a restaurer: les doublons supprimes etaient des copies perimees."""


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0056_photo_de_couverture'),
    ]

    operations = [
        migrations.AddField(
            model_name='etablissement',
            name='conduite_coefficient',
            field=models.DecimalField(decimal_places=2, default=2, max_digits=4, validators=[django.core.validators.MinValueValidator(0), django.core.validators.MaxValueValidator(10)]),
        ),
        migrations.AddField(
            model_name='studentacademichistory',
            name='term',
            field=models.CharField(blank=True, default='', max_length=20),
        ),
        migrations.RunPython(deduplique_les_bilans, ne_rien_defaire),
        migrations.AddIndex(
            model_name='studentacademichistory',
            index=models.Index(fields=['classroom', 'academic_year', 'term'], name='histo_class_year_term_idx'),
        ),
        migrations.AddConstraint(
            model_name='studentacademichistory',
            constraint=models.UniqueConstraint(fields=('student', 'academic_year', 'classroom', 'term'), name='historique_unique_par_periode'),
        ),
    ]
