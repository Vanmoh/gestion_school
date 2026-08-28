"""Les codes de classe distinguent enfin les classes voisines.

Le code gardait le mot generique et tronquait a six caracteres. Deux degats:

- les cinq classes de premiere annee d'une ecole -- DB1, DB2, EM1, EM2, TC --
  recevaient toutes « 1ANNEE », et leurs eleves des matricules ou la classe
  n'apparaissait plus;
- « 12eme TSECO1 » et « 12eme TSECO2 » se reduisaient tous deux a « 12TSEC ».

La regle ecarte desormais le mot generique quand une filiere le suit, et
laisse huit caracteres au reste. « 1ere Annee DB1 » donne « 1DB1 », « 3eme
Annee » -- qui n'a pas de filiere -- garde « 3AN ».

Les matricules dont le prefixe change sont regeneres, dans l'ordre de leur
numero actuel pour que la nouvelle numerotation suive l'ancienne. Ceux dont
le code ne bouge pas -- « 10CT », « 10CG1 » -- ne sont pas touches.
"""

from django.db import migrations


def uniformiser(apps, schema_editor):
    from apps.school import matricule as service

    Student = apps.get_model("school", "Student")

    eleves = (
        Student.objects.select_related(
            "classroom", "classroom__academic_year", "etablissement"
        )
        .exclude(classroom__isnull=True)
        .order_by("matricule", "id")
    )

    changes = 0
    for eleve in eleves:
        annee_scolaire = getattr(eleve.classroom, "academic_year", None)
        debut = getattr(annee_scolaire, "start_date", None)
        annee = debut.year if debut else (
            eleve.enrollment_date.year if eleve.enrollment_date else 0
        )
        attendu = service.prefixe(
            eleve.etablissement or eleve.classroom.etablissement,
            eleve.classroom,
            annee,
        )
        if eleve.matricule.startswith(attendu):
            continue

        ancien = eleve.matricule
        eleve.matricule = service.generer(eleve, modele_eleve=Student)
        eleve.save(update_fields=["matricule"])
        changes += 1
        if changes <= 40:
            print(f"    {ancien} → {eleve.matricule}")

    if changes:
        if changes > 40:
            print(f"    … et {changes - 40} autre(s).")
        print(f"  {changes} matricule(s) uniformisé(s).\n")
    else:
        print("  Aucun matricule à uniformiser.")


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0051_matricules_hors_format"),
    ]

    operations = [
        migrations.RunPython(uniformiser, migrations.RunPython.noop),
    ]
