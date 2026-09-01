"""Qui peut ouvrir une conversation avec qui.

La messagerie s'ouvrait de tous vers tous a l'interieur de l'etablissement: un
eleve pouvait ecrire au comptable ou au promoteur, deux eleves pouvaient
correspondre entre eux sous couvert de l'ecole. L'appel d'attention, lui, etait
deja reserve au personnel -- parce qu'il interrompt. Le message ordinaire ne
l'etait pas, parce qu'il attend qu'on le lise; mais attendre n'est pas la seule
question, savoir qui s'adresse a qui en est une autre.

Eleves et parents ne joignent donc que le personnel pedagogique: ceux dont le
travail les concerne. La regle est symetrique, et c'est ce qui la rend
effective: si seul le premier geste etait filtre, le comptable ouvrirait la
conversation et l'eleve n'aurait plus qu'a repondre.

Ce module ne connait ni Django ni les modeles: il ne fait que trancher entre
deux roles, et se teste comme tel.
"""

from apps.accounts.access import (
    CENSOR,
    DIRECTOR,
    PARENT,
    STUDENT,
    SUPER_ADMIN,
    SUPERVISOR,
    TEACHER,
)

# Ceux dont le travail concerne directement un eleve et sa famille. Le
# comptable et le promoteur en sont absents a dessein: on ne discute pas
# scolarite avec la comptabilite par messagerie interne, on passe par
# l'administration.
ROLES_PEDAGOGIQUES = frozenset({SUPER_ADMIN, DIRECTOR, CENSOR, SUPERVISOR, TEACHER})

# Ceux dont la correspondance est limitee au personnel pedagogique.
ROLES_A_CORRESPONDANCE_LIMITEE = frozenset({STUDENT, PARENT})


def correspondance_limitee(role):
    return role in ROLES_A_CORRESPONDANCE_LIMITEE


def peut_correspondre(role_a, role_b):
    """Une conversation entre ces deux roles est-elle permise?

    Symetrique: peu importe lequel des deux l'ouvre.
    """
    if correspondance_limitee(role_a) and role_b not in ROLES_PEDAGOGIQUES:
        return False
    if correspondance_limitee(role_b) and role_a not in ROLES_PEDAGOGIQUES:
        return False
    return True


def roles_joignables_par(role):
    """Les roles avec qui ce role peut ouvrir une conversation.

    Rend None quand aucune restriction ne s'applique -- l'appelant n'a alors
    aucun filtre a poser.
    """
    if correspondance_limitee(role):
        return ROLES_PEDAGOGIQUES
    if role in ROLES_PEDAGOGIQUES:
        return None
    # Ni limite, ni pedagogique -- le comptable, le promoteur: ils joignent
    # tout le personnel, mais pas les eleves ni les familles.
    return None


def roles_exclus_pour(role):
    """Les roles que celui-ci ne peut pas joindre, quand la liste est plus
    courte que celle des roles permis."""
    if correspondance_limitee(role) or role in ROLES_PEDAGOGIQUES:
        return frozenset()
    return ROLES_A_CORRESPONDANCE_LIMITEE
