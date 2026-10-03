"""Semer les quatre ecoles reelles sur une base neuve.

Cette migration etait la premiere de trois descriptions concurrentes des memes
quatre ecoles. Elle creait « Lycee Technique Oumar Bah (LTOB) », « Lycee
Technique Oumar Bah (LOBK) », « IFP-OBK » et « Complexe Scolaire Omar Bah
(CSOB) » -- avec « Omar » sans u -- tandis que la commande
`insert_etablissements` creait « LTOB », « LOBK », « IFP-OBK » et « Complexe
Scolaire Oumar Bah ».

Un seul nom etait commun: « IFP-OBK ». Lancer la migration puis la commande
creait donc **sept** etablissements pour quatre ecoles. La commande fusionnait
ensuite ses alias et en supprimait trois, laissant quatre ecoles portant les
identifiants 3, 5, 7 et 11 -- et une base ou rien n'expliquait les trous.

Les noms et codes viennent desormais de `apps.school.etablissements_reels`, qui
les decrit une seule fois. Ils sont recopies ici et non importes: une migration
doit se rejouer a l'identique dans dix ans, alors que le module vivra. C'est
`test_etablissements_reels` qui interdit aux deux listes de divergerA nouveau.

Les codes, eux, ne sont pas poses ici: `Etablissement.code` n'existe pas encore
a ce point du graphe, et `0011` comme `0017` dependent de ce semis -- dependre
de `0047` creerait un cycle. C'est `0047` qui les derive des initiales, et les
quatre noms ci-dessous donnent exactement LT, LO, IO et CS.
"""

from django.db import migrations

# Copie figee des noms de `ETABLISSEMENTS_REELS`, dans le meme ordre: sur une
# base neuve les identifiants suivent donc 1, 2, 3, 4.
#
# Les noms seuls, sans les codes: `Etablissement.code` n'existe pas encore a ce
# point du graphe. Cette migration doit rester avant `0011` et `0017`, qui en
# dependent, tandis que le champ n'arrive qu'en `0047` -- y ajouter une
# dependance creerait un cycle.
#
# Ce n'est pas un manque: `0047` derive le code des initiales des deux premiers
# mots, et ces quatre noms donnent exactement LT, LO, IO et CS.
# `test_etablissements_reels` le verifie, sans quoi un nom retouche ici
# changerait silencieusement le code d'une ecole -- et les matricules avec lui.
ETABLISSEMENTS = [
    "Lycée Technique Oumar Bah (LTOB)",
    "Lycée Oumar Bah (LOBK)",
    "IFP-OBK",
    "Complexe Scolaire Oumar Bah (CSOB)",
]


def creer_les_etablissements(apps, schema_editor):
    Etablissement = apps.get_model("school", "Etablissement")

    # Sur une base deja peuplee, cette migration ne rejoue pas: elle n'insere
    # donc que sur une base neuve, ou la table est vide. Le garde-fou reste,
    # pour qu'un `migrate --fake` suivi d'un vrai ne double rien.
    if Etablissement.objects.exists():
        return

    for nom in ETABLISSEMENTS:
        Etablissement.objects.create(name=nom)


def ne_rien_defaire(apps, schema_editor):
    """Supprimer ces ecoles emporterait toute la base avec elles.

    Classes, eleves, notes, paiements: vingt-six cles etrangeres y pendent. Un
    retour en arriere ne les recreerait pas.
    """


class Migration(migrations.Migration):
    dependencies = [
        ("school", "0010_etablissement_book_etablissement_and_more"),
    ]
    operations = [
        migrations.RunPython(creer_les_etablissements, ne_rien_defaire),
    ]
