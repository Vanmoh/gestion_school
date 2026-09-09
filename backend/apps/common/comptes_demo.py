"""Les comptes de demonstration, nommes en un seul endroit.

`seed_demo_data` les cree avec des mots de passe connus, ecrits dans le
depot. C'est ce qu'on veut d'un environnement de developpement, et c'est une
porte ouverte partout ailleurs: le premier deploiement cloud a seme cette
base telle quelle, et `superadmin` y a donc existe avec le mot de passe que
le README publiait.

Trois choses s'appuient sur cette liste, et doivent parler des memes comptes:
la commande qui les cree, celle qui les purge, et le controle de deploiement
qui signale leur presence en production.
"""

# Le mot de passe n'est volontairement pas ici: cette liste est lue par des
# controles qui tournent en production, et n'a aucune raison de transporter
# un secret, meme de developpement.
NOMS_DES_COMPTES_DE_DEMONSTRATION = (
    "superadmin",
    "directeur",
    "comptable",
    "enseignant1",
    "parent1",
    "surveillant1",
    "eleve1",
    "eleve2",
)


def comptes_de_demonstration_presents():
    """Les comptes de demonstration qui existent reellement en base.

    Rend un queryset, pas une liste: l'appelant decide s'il compte, affiche
    ou supprime.
    """
    from apps.accounts.models import User

    return User.objects.filter(username__in=NOMS_DES_COMPTES_DE_DEMONSTRATION)
