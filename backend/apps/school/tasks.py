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
