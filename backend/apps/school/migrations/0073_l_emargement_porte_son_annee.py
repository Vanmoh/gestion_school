"""L'emargement porte enfin son annee scolaire.

`TeacherTimeEntry` ne portait qu'une date, et sa vue n'etait pas bornee. Sur
IFP-OBK, qui a deux annees ouvertes, la liste rendait donc **1 593**
emargements -- 751 pour 2025-2026 et 842 pour 2026-2027 -- **quelle que soit
l'annee demandee**: les trois cas (annee active, annee suivante, aucun
en-tete) donnaient le meme chiffre. La feuille d'emargement et les tableaux de
bord d'enseignant comptaient deux exercices en un.

C'est le dernier modele date de cette famille. Les quatre autres -- absences,
incidents, depenses, fiches de paie -- ont ete combles par la migration 0072;
celui-ci n'avait meme pas le champ.

Le calcul de paie, lui, n'etait pas touche: `_teacher_hours_worked` borne les
emargements au mois paye, et un mois n'appartient qu'a une annee. Ce sont les
**listes** qui melangeaient.

Le rattachement se deduit de `entry_date`, puisque deux annees d'un meme
etablissement ne peuvent pas se chevaucher. Les lignes dont la date ne tombe
dans aucune annee restent sans rattachement: 1 180 de la base reelle sont dans
ce cas -- septembre 2026, pour trois ecoles qui n'ont pas encore ouvert
2026-2027. Les ranger de force dans l'annee close serait plus faux que de les
laisser en attente, et `controler_la_dotation` les signale.
"""

import django.db.models.deletion
from django.db import migrations, models


def annee_couvrant(AcademicYear, etablissement_id, date):
    if etablissement_id is None or date is None:
        return None
    return (
        AcademicYear.objects.filter(
            etablissement_id=etablissement_id,
            start_date__lte=date,
            end_date__gte=date,
        )
        .order_by("-is_active", "-start_date", "-id")
        .values_list("id", flat=True)
        .first()
    )


def ranger(apps, schema_editor):
    AcademicYear = apps.get_model("school", "AcademicYear")
    TeacherTimeEntry = apps.get_model("school", "TeacherTimeEntry")

    # `etablissement` d'abord, `teacher.etablissement` en repli: la colonne est
    # nullable sur les deux, et une ligne importee sans ecole reste localisable
    # par l'enseignant qu'elle designe.
    for ligne in TeacherTimeEntry.objects.filter(
        academic_year__isnull=True
    ).select_related("teacher"):
        etablissement_id = ligne.etablissement_id or getattr(
            ligne.teacher, "etablissement_id", None
        )
        annee = annee_couvrant(AcademicYear, etablissement_id, ligne.entry_date)
        if annee is not None:
            TeacherTimeEntry.objects.filter(pk=ligne.pk).update(
                academic_year_id=annee
            )


def ne_rien_defaire(apps, schema_editor):
    """Le retour en arriere retire la colonne, ce qui emporte les valeurs.

    Rien a defaire ici: c'est `RemoveField` qui s'en charge.
    """


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0072_ranger_les_lignes_datees_dans_leur_annee"),
    ]

    operations = [
        migrations.AddField(
            model_name="teachertimeentry",
            name="academic_year",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="%(class)ss",
                to="school.academicyear",
            ),
        ),
        migrations.RunPython(ranger, ne_rien_defaire),
    ]
