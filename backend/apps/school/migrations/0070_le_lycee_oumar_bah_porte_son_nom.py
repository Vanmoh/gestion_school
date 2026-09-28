"""Deux ecoles distinctes portaient presque le meme nom.

`9999_insert_etablissements` inserait « Lycee Technique Oumar Bah (LTOB) » et
« Lycee Technique Oumar Bah (LOBK) »: seul le sigle entre parenthese les
separait. Le second s'appelle en realite **Lycee Oumar Bah**, sans
« Technique ».

Ce n'est pas qu'une question d'exactitude. Deux noms qui ne different que par
quatre lettres entre parentheses se confondent partout ou l'on choisit une
ecole -- le selecteur du portail, l'en-tete d'un bulletin, une liste de
classe. Et tout code qui rapproche un etablissement d'une liste par inclusion
de chaine donne l'un pour l'autre: la commande de peuplement a d'ailleurs
attribue au second les cinq classes du premier, alors qu'il en compte treize.

La migration d'insertion n'est pas retouchee -- elle est deja appliquee
partout, et la modifier ne changerait aucune base existante. C'est donc ici
que la correction se fait, pour les bases en place comme pour les neuves.
"""

from django.db import migrations

ANCIEN_NOM = "Lycée Technique Oumar Bah (LOBK)"
NOUVEAU_NOM = "Lycée Oumar Bah (LOBK)"
NOUVEAU_CODE = "LO"


def corriger_le_nom(apps, schema_editor):
    Etablissement = apps.get_model("school", "Etablissement")

    ecole = Etablissement.objects.filter(name=ANCIEN_NOM).first()
    if ecole is None:
        return

    # Si le nom corrige existe deja -- une base ou quelqu'un l'a renomme a la
    # main -- on ne cree pas de doublon: le nom est unique, et fusionner deux
    # ecoles ne se decide pas dans une migration.
    if Etablissement.objects.filter(name=NOUVEAU_NOM).exclude(pk=ecole.pk).exists():
        return

    ecole.name = NOUVEAU_NOM
    champs = ["name"]

    # Le code suit, s'il porte encore la valeur derivee de l'ancien nom.
    if (ecole.code or "").upper() in {"LT2", "LT", ""}:
        ecole.code = NOUVEAU_CODE
        champs.append("code")

    ecole.save(update_fields=champs)
    print(f"  « {ANCIEN_NOM} » renomme en « {NOUVEAU_NOM} ».")


def rendre_l_ancien_nom(apps, schema_editor):
    """Le retour en arriere reste possible, meme s'il retablit une confusion."""
    Etablissement = apps.get_model("school", "Etablissement")
    ecole = Etablissement.objects.filter(name=NOUVEAU_NOM).first()
    if ecole is None:
        return
    if Etablissement.objects.filter(name=ANCIEN_NOM).exclude(pk=ecole.pk).exists():
        return
    ecole.name = ANCIEN_NOM
    ecole.save(update_fields=["name"])


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0069_l_annonce_porte_son_public"),
    ]

    operations = [
        migrations.RunPython(corriger_le_nom, rendre_l_ancien_nom),
    ]
