"""Les eleves inscrits sans matricule en recoivent un.

Le champ tolere le vide, et rien ne l'exigeait a l'inscription: des eleves
existent sans identifiant, alors que c'est lui qui sert a les retrouver sur
un bulletin, une liste d'appel ou un recu.

Seuls les matricules **vides** sont combles. Ceux qui existent deja ne sont
pas retouches, meme les « GS-2025-00001 » produits par l'ancien repli quand
le genre manquait: un matricule circule sur des cartes et des documents
signes, le changer sous les pieds de l'ecole ferait plus de degats que la
forme irreguliere qu'il corrige.
"""

from django.db import migrations


def combler_les_matricules(apps, schema_editor):
    from apps.school import matricule as service

    Student = apps.get_model("school", "Student")

    manquants = (
        Student.objects.filter(matricule="")
        .select_related("classroom", "classroom__academic_year", "etablissement")
        .order_by("id")
    )

    for eleve in manquants:
        # `generer` lit la fiche et interroge le modele passe en argument:
        # celui d'ici est le modele historique de la migration, pas celui
        # qu'importerait le service.
        eleve.matricule = service.generer(eleve, modele_eleve=Student)
        eleve.save(update_fields=["matricule"])


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0047_etablissement_code"),
    ]

    operations = [
        migrations.RunPython(combler_les_matricules, migrations.RunPython.noop),
    ]
