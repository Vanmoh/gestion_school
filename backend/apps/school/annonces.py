"""Qui lit une annonce -- la regle vit ici, et nulle part ailleurs.

L'ecran Communication offrait un champ « Audience (all, parents,
teachers...) » libre, ou le censeur tapait sa cible a la main. Le champ
existait bien en base, mais **personne ne le lisait**: ni le modele, qui
n'avait aucun `choices`, ni `AnnouncementViewSet.get_queryset`, qui ne
restreignait qu'a l'etablissement. Une annonce ecrite « teachers » -- une
reunion pedagogique, une consigne de correction -- partait donc a tout le
monde, familles comprises: la matrice ouvre `communication` en `L*` au
parent et a l'eleve.

Deux defauts en un: une promesse que l'ecran ne tenait pas, et une fuite
par le chemin le plus ordinaire, la liste des annonces.

La regle tient en une phrase: **une annonce se lit si son audience contient
le role du lecteur**, avec deux tolerances explicites plus bas.

Ce que ce module ne fait pas: il ne touche pas aux notifications. Une
notification porte son destinataire (`recipient`), c'est-a-dire une personne
et non un public; elle n'a donc pas d'audience a filtrer.
"""

from django.db.models import Q

from apps.accounts.models import UserRole

# Le personnel qui pilote l'etablissement relit ce qui y est publie.
#
# Sans cette tolerance, un directeur ne verrait pas l'annonce qu'un censeur
# vient d'adresser aux familles, et n'aurait aucun moyen de la corriger --
# alors que la matrice lui donne le niveau « A » sur le module.
ROLES_QUI_VOIENT_TOUT = frozenset(
    {UserRole.SUPER_ADMIN, UserRole.PROMOTER, UserRole.DIRECTOR}
)

# Ce que chaque role lit, en plus de « tout l'etablissement ».
#
# L'enseignant ne recoit pas les annonces de l'administration et le comptable
# ne recoit pas celles de la salle des profs: c'est tout l'interet d'une
# audience. Un role absent de cette table ne lit que « all ».
AUDIENCES_PAR_ROLE = {
    UserRole.PARENT: frozenset({"families"}),
    UserRole.STUDENT: frozenset({"families"}),
    UserRole.TEACHER: frozenset({"teachers"}),
    UserRole.CENSOR: frozenset({"staff", "teachers"}),
    UserRole.SUPERVISOR: frozenset({"staff"}),
    UserRole.ACCOUNTANT: frozenset({"staff"}),
}


def audiences_lisibles_par(role) -> frozenset:
    """Les audiences qu'un role a le droit de lire.

    « all » y figure toujours: une annonce a tout l'etablissement s'adresse
    aussi a celui qui la lit.
    """
    return frozenset({"all"}) | AUDIENCES_PAR_ROLE.get(role, frozenset())


def annonces_lisibles_par(user, queryset):
    """Restreint `queryset` aux annonces que `user` a le droit de lire.

    L'auteur retrouve toujours ce qu'il a publie, meme adresse a un public
    dont il ne fait pas partie -- sinon un surveillant qui ecrit aux familles
    perdrait de vue son propre message aussitot enregistre.
    """
    role = getattr(user, "role", None)
    if role in ROLES_QUI_VOIENT_TOUT:
        return queryset

    return queryset.filter(
        Q(audience__in=audiences_lisibles_par(role)) | Q(author=user)
    )
