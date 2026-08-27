"""Taches de fond du module scolaire.

Le catalogue du fonds documentaire vit ici et non dans `entrypoint.sh`: le
service web y lisait neuf pages chez bkalan.ml a chaque reveil du conteneur,
sur les 0,1 CPU du plan gratuit, au moment precis ou quelqu'un attendait sa
premiere reponse. Le worker Celery, lui, ne sert aucune requete: une source
lente n'y coute le temps de personne.
"""

from celery import shared_task
from django.core.management import call_command


@shared_task
def import_library_catalogue(si_vide=True):
    """Catalogue le fonds documentaire, sans rapatrier aucun fichier.

    `si_vide` par defaut: la tache est declenchee au demarrage de chaque
    conteneur, et Render reveille le service bien plus souvent qu'il ne le
    deploie. Un catalogue deja present arrete la commande avant le premier
    appel reseau.

    Le rapatriement des PDF reste manuel et hors de cette tache: plusieurs
    gigaoctets n'ont rien a faire dans une file de travaux declenchee a chaque
    demarrage (voir docs/OPERATIONS_BIBLIOTHEQUE.md).
    """
    arguments = ["--catalogue-seul"]
    if si_vide:
        arguments.append("--si-vide")
    call_command("import_bkalan", *arguments)


@shared_task
def signaler_les_seances_non_assurees(jour=None):
    """Previent la direction des cours que personne n'a assures la veille.

    L'ecart entre l'emploi du temps et l'emargement ne se voyait qu'en
    ouvrant l'ecran de rapprochement -- c'est-a-dire en se doutant deja qu'il
    y avait quelque chose a voir. Une classe laissee sans professeur pendant
    deux heures merite mieux qu'une decouverte en fin de mois, sur la fiche
    de paie.

    La veille et non le jour meme: un cours de l'apres-midi n'est pas encore
    manque a midi, et pointer une absence avant l'heure du cours serait faux.
    """
    call_command("signaler_seances_non_assurees", *(["--jour", jour] if jour else []))


@shared_task
def signaler_le_stock_bas():
    """Previent l'intendance des articles passes sous leur seuil.

    Le champ `is_low_stock` existait depuis toujours sans que rien ne le
    lise: la rupture se decouvrait le jour ou l'on cherchait la craie.
    """
    call_command("signaler_stock_bas")
