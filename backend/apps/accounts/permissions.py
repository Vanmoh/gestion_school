from rest_framework.permissions import BasePermission

from .access import (
    ADMIN,
    MODULES,
    READ,
    ROLE_LABELS,
    access_level,
    required_level,
)


# `IsRole` et `IsSuperAdmin` vivaient ici. Elles etaient les deux dernieres
# des treize classes de permission ad hoc que la matrice a remplacees, et plus
# aucune vue ne les appliquait -- seul un import oublie les gardait en vie.
# Les laisser, c'etait laisser a portee de main le moyen de recreer la
# divergence: une vue qui autorise selon sa propre liste, sans que la matrice
# ni /auth/permissions/ n'en sachent rien. Pour restreindre a un seul role,
# c'est une colonne de MODULES qu'il faut ecrire, ou un affinement.


class HasModuleAccess(BasePermission):
    """Autorise selon la matrice de access.py, pas selon une liste locale.

    La vue declare `access_module = "grades"`; la methode HTTP donne le niveau
    exige (lecture / ecriture / suppression). Une vue sans `access_module`
    est refusee: le defaut precedent laissait passer tout le personnel sur
    tout module non explicitement protege, c'est exactement ce qu'on corrige.
    """

    message = "Acces refuse par la matrice de droits."

    def _module(self, view):
        return getattr(view, "access_module", None)

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        module = self._module(view)
        if not module or module not in MODULES:
            self.message = "Ressource non rattachee a un module de droits."
            return False

        role = getattr(user, "role", "")
        # Certains exports lisent la base via POST (recus en lot): ils ne
        # doivent pas exiger le niveau ecriture du module.
        needed = READ if getattr(view, "access_read_only", False) else required_level(request.method)
        if access_level(role, module) >= needed:
            return True

        # DRF instancie la permission par requete: renseigner self.message ici
        # rend le refus lisible cote client au lieu d'un 403 muet.
        label = MODULES[module]["label"]
        role_label = ROLE_LABELS.get(role, role or "inconnu")
        granted = access_level(role, module)
        if granted <= 0:
            self.message = f"Module « {label} » non accessible au profil {role_label}."
        elif required_level(request.method) == ADMIN:
            self.message = f"Suppression sur « {label} » reservee a l'administration."
        else:
            self.message = f"Module « {label} » en lecture seule pour le profil {role_label}."
        return False


