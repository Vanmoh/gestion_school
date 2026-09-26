"""L'annonce porte enfin le public auquel elle s'adresse.

Le champ etait libre et personne ne le lisait: la base contient donc ce que
les utilisateurs ont bien voulu y taper, sans qu'aucune de ces valeurs n'ait
jamais eu le moindre effet. La reprise reconnait les graphies courantes du
francais et de l'anglais, et renvoie tout le reste sur « tout
l'etablissement » -- qui est exactement ce que ces annonces faisaient
jusqu'ici, faute de filtre.
"""

from django.db import migrations, models


# Les graphies qu'on trouve quand un champ texte a ete rempli a la main.
#
# Rien n'est devine au-dela de cette table: une valeur inconnue devient
# « all », le comportement que l'annonce avait deja. Elargir la cible d'une
# annonce par erreur ne fait perdre aucun message; la rescinder en silence,
# si.
GRAPHIES = {
    "families": "families",
    "family": "families",
    "familles": "families",
    "famille": "families",
    "parents": "families",
    "parent": "families",
    "students": "families",
    "student": "families",
    "eleves": "families",
    "eleve": "families",
    "élèves": "families",
    "élève": "families",
    "teachers": "teachers",
    "teacher": "teachers",
    "enseignants": "teachers",
    "enseignant": "teachers",
    "profs": "teachers",
    "staff": "staff",
    "administration": "staff",
    "admin": "staff",
    "personnel": "staff",
    "direction": "staff",
}


def audience_normalisee(brute) -> str:
    """Ramene une saisie libre a l'un des quatre publics fermes."""
    if not brute:
        return "all"
    return GRAPHIES.get(str(brute).strip().lower(), "all")


def normaliser_les_audiences(apps, schema_editor):
    Announcement = apps.get_model("school", "Announcement")

    corrigees = 0
    for annonce in Announcement.objects.all().only("id", "audience").iterator():
        cible = audience_normalisee(annonce.audience)
        if cible != annonce.audience:
            Announcement.objects.filter(pk=annonce.pk).update(audience=cible)
            corrigees += 1

    if corrigees:
        print(f"  {corrigees} annonce(s) dont le public a ete normalise.")


def rien_a_defaire(apps, schema_editor):
    """Les quatre valeurs fermees restent lisibles par un champ libre."""


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0068_unicite_par_epreuve"),
    ]

    operations = [
        migrations.RunPython(normaliser_les_audiences, rien_a_defaire),
        migrations.AlterField(
            model_name="announcement",
            name="audience",
            field=models.CharField(
                choices=[
                    ("all", "Tout l'etablissement"),
                    ("families", "Familles (parents et eleves)"),
                    ("teachers", "Enseignants"),
                    ("staff", "Administration"),
                ],
                default="all",
                max_length=50,
            ),
        ),
    ]
