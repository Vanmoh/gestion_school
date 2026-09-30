"""Combler l'annee scolaire des lignes datees qui n'en avaient pas.

Quarante-quatre lignes de la base reelle etaient dans ce cas: 9 absences,
1 incident de discipline, 10 depenses et 24 fiches de paie. Le pointage des
enseignants n'en comptait aucune, mais sa colonne est nullable comme les autres:
il est traite ici aussi, pour qu'une base restauree d'un dump plus ancien soit
comblee de la meme facon. Aucune n'etait
fausse -- elles etaient simplement invisibles. L'application envoie l'en-tete
`X-Academic-Year-Id` sur toutes ses requetes, les vues filtrent alors sur
`academic_year=<annee>`, et `NULL` ne repond pas a ce filtre. Une absence
qu'on ne voit pas est une absence qu'on ne peut pas retirer.

Le rattachement se deduit de la date, puisque deux annees d'un meme
etablissement ne peuvent pas se chevaucher. La logique vit dans
`apps.school.rattachement_a_l_annee`, mais elle est recopiee ici: une
migration ne doit pas dependre du code applicatif d'aujourd'hui, qui aura
change quand on rejouera l'historique sur une base neuve.

Les lignes dont la date ne tombe dans aucune annee -- une depense d'aout, une
paie de juillet -- restent sans rattachement. C'est exact et non un oubli:
elles n'appartiennent a aucune annee scolaire.
"""

from django.db import migrations


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


def etablissement_de_l_eleve(eleve):
    if eleve is None:
        return None
    if eleve.etablissement_id is not None:
        return eleve.etablissement_id
    classe = eleve.classroom
    if classe is None or classe.academic_year is None:
        return None
    return classe.academic_year.etablissement_id


def ranger(apps, schema_editor):
    AcademicYear = apps.get_model("school", "AcademicYear")

    Attendance = apps.get_model("school", "Attendance")
    for ligne in Attendance.objects.filter(academic_year__isnull=True).select_related(
        "student__classroom__academic_year"
    ):
        annee = annee_couvrant(
            AcademicYear, etablissement_de_l_eleve(ligne.student), ligne.date
        )
        if annee is not None:
            Attendance.objects.filter(pk=ligne.pk).update(academic_year_id=annee)

    DisciplineIncident = apps.get_model("school", "DisciplineIncident")
    for ligne in DisciplineIncident.objects.filter(
        academic_year__isnull=True
    ).select_related("student__classroom__academic_year"):
        annee = annee_couvrant(
            AcademicYear, etablissement_de_l_eleve(ligne.student), ligne.incident_date
        )
        if annee is not None:
            DisciplineIncident.objects.filter(pk=ligne.pk).update(
                academic_year_id=annee
            )

    Expense = apps.get_model("school", "Expense")
    for ligne in Expense.objects.filter(academic_year__isnull=True):
        annee = annee_couvrant(AcademicYear, ligne.etablissement_id, ligne.date)
        if annee is not None:
            Expense.objects.filter(pk=ligne.pk).update(academic_year_id=annee)

    # Zero orpheline sur la base reelle, mais la colonne est nullable comme les
    # autres: une base restauree d'un dump plus ancien peut en porter.
    TeacherAttendance = apps.get_model("school", "TeacherAttendance")
    for ligne in TeacherAttendance.objects.filter(
        academic_year__isnull=True
    ).select_related("teacher"):
        annee = annee_couvrant(
            AcademicYear,
            getattr(ligne.teacher, "etablissement_id", None),
            ligne.date,
        )
        if annee is not None:
            TeacherAttendance.objects.filter(pk=ligne.pk).update(
                academic_year_id=annee
            )

    TeacherPayroll = apps.get_model("school", "TeacherPayroll")
    for ligne in TeacherPayroll.objects.filter(
        academic_year__isnull=True
    ).select_related("teacher"):
        etablissement_id = getattr(ligne.teacher, "etablissement_id", None)
        annee = annee_couvrant(AcademicYear, etablissement_id, ligne.month)
        if annee is not None:
            TeacherPayroll.objects.filter(pk=ligne.pk).update(academic_year_id=annee)


def ne_rien_defaire(apps, schema_editor):
    """Le retour en arriere ne vide pas les annees posees.

    On ne saurait pas lesquelles venaient de cette migration et lesquelles
    etaient deja la. Vider les quatre colonnes rendrait invisibles des milliers
    de lignes correctes pour recreer quarante-quatre orphelines: le remede
    serait pire que le mal.
    """


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0071_une_matiere_un_enseignant"),
    ]

    operations = [
        migrations.RunPython(ranger, ne_rien_defaire),
    ]
