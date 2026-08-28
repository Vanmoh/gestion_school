"""Les matricules hors format, ramenes au format de l'ecole.

Un eleve dont le genre n'etait pas renseigne recevait « GS-2025-00001 » -- une
forme etrangere au `RC15CG25E3566F` de l'etablissement, produite par un repli
du generateur. Le genre entrant dans le matricule, il fallait bien lui donner
quelque chose.

Deux temps, dans cet ordre:

1. les eleves sans genre en recoivent un. Le tirage est **pseudo-aleatoire et
   reproductible**: la graine est l'identifiant de l'eleve, si bien qu'un
   rejeu de la migration -- sur une copie, une preproduction, une
   restauration -- donne exactement le meme resultat. Un tirage franc
   donnerait des matricules differents a chaque execution, et deux copies de
   la meme base cesseraient de se correspondre;
2. les matricules qui ne suivent pas le format sont regeneres.

Le tirage ecrit une donnee que personne n'a verifiee. La commande en dresse
donc la liste dans les logs, pour que l'ecole puisse corriger les fiches --
c'est le prix demande pour des matricules coherents.
"""

import random

from django.db import migrations


def regulariser(apps, schema_editor):
    from apps.school import matricule as service

    Student = apps.get_model("school", "Student")

    sans_genre = list(
        Student.objects.filter(gender__isnull=True).order_by("id")
    ) + list(Student.objects.filter(gender="").order_by("id"))

    for eleve in sans_genre:
        # Graine par eleve: reproductible d'une execution a l'autre.
        eleve.gender = random.Random(eleve.pk).choice(["M", "F"])
        eleve.save(update_fields=["gender"])

    if sans_genre:
        print(
            f"\n  {len(sans_genre)} élève(s) ont reçu un genre tiré au sort — "
            "à vérifier :"
        )
        for eleve in sans_genre[:50]:
            print(f"    - #{eleve.pk} {eleve.matricule or '(sans matricule)'} → {eleve.gender}")
        if len(sans_genre) > 50:
            print(f"    … et {len(sans_genre) - 50} autre(s).")

    a_regenerer = [
        eleve
        for eleve in Student.objects.select_related(
            "classroom", "classroom__academic_year", "etablissement"
        ).order_by("id")
        if not service.est_conforme(eleve.matricule)
    ]

    for eleve in a_regenerer:
        ancien = eleve.matricule
        eleve.matricule = service.generer(eleve, modele_eleve=Student)
        eleve.save(update_fields=["matricule"])
        print(f"    matricule {ancien or '(vide)'} → {eleve.matricule}")

    if a_regenerer:
        print(f"  {len(a_regenerer)} matricule(s) régénéré(s).\n")


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0050_stock_derive_des_mouvements"),
    ]

    operations = [
        migrations.RunPython(regulariser, migrations.RunPython.noop),
    ]
