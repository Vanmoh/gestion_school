"""Source unique des droits d'acces: un role, un module, un niveau.

Avant ce fichier, l'autorisation etait ecrite a trois endroits qui divergeaient:
treize classes de permission ad hoc, un defaut implicite sur BaseModelViewSet
qui ouvrait l'ecriture a tout le personnel, et une carte codee en dur dans le
frontend. Ajouter un role demandait treize editions et personne ne pouvait dire
qui accedait a quoi sans lire l'integralite des vues.

Ici la matrice est la seule verite: la permission DRF la lit, l'endpoint
/api/auth/permissions/ la sert au frontend, et les tests la verrouillent.
"""

from __future__ import annotations

# --- Roles -----------------------------------------------------------------
# Chaines litterales et non UserRole.*: ce module doit rester importable sans
# charger les modeles Django. Un test verifie qu'il ne derive pas de UserRole.

SUPER_ADMIN = "super_admin"
PROMOTER = "promoter"
DIRECTOR = "director"
CENSOR = "censor"
ACCOUNTANT = "accountant"
SUPERVISOR = "supervisor"
TEACHER = "teacher"
PARENT = "parent"
STUDENT = "student"

ROLES = (
    SUPER_ADMIN,
    PROMOTER,
    DIRECTOR,
    CENSOR,
    ACCOUNTANT,
    SUPERVISOR,
    TEACHER,
    PARENT,
    STUDENT,
)

ROLE_LABELS = {
    SUPER_ADMIN: "Super Admin",
    PROMOTER: "Promoteur",
    DIRECTOR: "Directeur/Proviseur",
    CENSOR: "Censeur",
    ACCOUNTANT: "Comptable",
    SUPERVISOR: "Surveillant",
    TEACHER: "Enseignant",
    PARENT: "Parent",
    STUDENT: "Eleve",
}


# --- Niveaux ---------------------------------------------------------------

NONE = 0
READ = 1
WRITE = 2
ADMIN = 3

LEVEL_NAMES = {NONE: "none", READ: "read", WRITE: "write", ADMIN: "admin"}

# Codes de la matrice. Le suffixe "*" documente une portee restreinte (ses
# classes, ses enfants, soi) deja appliquee par le get_queryset de la vue: il
# n'ouvre ni ne ferme un niveau, il informe le frontend.
_CODES = {
    "-": NONE,
    "L": READ,
    "E": WRITE,
    "A": ADMIN,
}

# Methode HTTP -> niveau exige. DELETE demande ADMIN: c'est ce qui distingue
# "peut saisir" de "peut supprimer", la seule nuance qui manquait avant.
SAFE_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
WRITE_METHODS = frozenset({"POST", "PUT", "PATCH"})


def required_level(method: str) -> int:
    method = (method or "").upper()
    if method in SAFE_METHODS:
        return READ
    if method in WRITE_METHODS:
        return WRITE
    return ADMIN


# --- Modules ---------------------------------------------------------------

MODULE_GROUPS = (
    ("pilotage", "Pilotage"),
    ("pedagogie", "Pedagogie"),
    ("academique", "Academique"),
    ("finances", "Finances"),
    ("administration", "Administration"),
    ("ressources", "Ressources"),
)


def _row(sa, pro, dr, cen, cpt, sur, ens, par, elv):
    return {
        SUPER_ADMIN: sa,
        PROMOTER: pro,
        DIRECTOR: dr,
        CENSOR: cen,
        ACCOUNTANT: cpt,
        SUPERVISOR: sur,
        TEACHER: ens,
        PARENT: par,
        STUDENT: elv,
    }


# Colonnes:      SA   PRO  DIR  CEN  CPT  SUR  ENS  PAR  ELV
MODULES = {
    "dashboard": {
        "label": "Tableau de bord",
        "group": "pilotage",
        "access": _row("L", "L", "L", "L", "L", "L", "L*", "L*", "L*"),
    },
    "students": {
        "label": "Gestion des eleves",
        "group": "pedagogie",
        "access": _row("A", "L", "A", "L", "L", "L", "L*", "-", "-"),
    },
    # Ecran de consultation seule: on reprend exactement les colonnes de
    # "students" en retirant l'ecriture (A -> L). Personne n'y gagne un acces
    # qu'il n'avait pas, et le dossier reste cloisonne par
    # StudentViewSet.get_queryset() de toute facon.
    "student_lookup": {
        "label": "Recherche eleve",
        "group": "pedagogie",
        "access": _row("L", "L", "L", "L", "L", "L", "L*", "-", "-"),
    },
    "teachers": {
        "label": "Enseignants",
        "group": "pedagogie",
        "access": _row("A", "L", "A", "L", "L", "-", "-", "-", "-"),
    },
    "attendance": {
        "label": "Absences",
        "group": "pedagogie",
        "access": _row("A", "L", "A", "E", "-", "E", "E*", "L*", "L*"),
    },
    # Separation des taches deja en place avant la matrice: la direction lit
    # l'emargement mais ne le saisit pas, le censeur l'arbitre, l'enseignant
    # pointe pour lui-meme. Ne pas aplatir cette regle.
    "teacher_timesheet": {
        "label": "Emargement enseignants",
        "group": "pedagogie",
        "access": _row("A", "L", "L", "E", "L", "-", "E*", "-", "-"),
    },
    "discipline": {
        "label": "Discipline",
        "group": "pedagogie",
        "access": _row("A", "L", "A", "E", "-", "E", "E*", "L*", "L*"),
    },
    # Module d'API sans entree de menu: l'enseignant declare ses propres
    # creneaux, la direction les arbitre.
    "teacher_availability": {
        "label": "Disponibilites enseignants",
        "group": "pedagogie",
        "access": _row("A", "L", "A", "E", "-", "-", "E*", "-", "-"),
    },
    "academics": {
        "label": "Academique",
        "group": "academique",
        "access": _row("A", "L", "A", "E", "-", "-", "L", "-", "-"),
    },
    "academic_imports": {
        "label": "Imports academiques",
        "group": "academique",
        "access": _row("A", "-", "A", "E", "-", "-", "-", "-", "-"),
    },
    "grades": {
        "label": "Notes & Bulletins",
        "group": "academique",
        "access": _row("A", "L", "A", "E", "-", "-", "E*", "L*", "L*"),
    },
    "promotion": {
        "label": "Passation & Archivage",
        "group": "academique",
        "access": _row("A", "L", "A", "L", "-", "-", "-", "-", "-"),
    },
    "exams": {
        "label": "Examens",
        "group": "academique",
        "access": _row("A", "L", "A", "E", "-", "L", "E*", "L*", "L*"),
    },
    "timetable": {
        "label": "Emploi du temps",
        "group": "academique",
        "access": _row("A", "L", "A", "E", "L", "L", "L*", "L*", "L*"),
    },
    "finance": {
        "label": "Finances",
        "group": "finances",
        "access": _row("A", "L", "A", "-", "A", "-", "-", "L*", "L*"),
    },
    # Double validation: le censeur genere et valide au niveau 1, le comptable
    # valide au niveau 2. Les deux ecrivent, la direction controle en lecture.
    "payroll": {
        "label": "Paie enseignants",
        "group": "finances",
        "access": _row("A", "L", "L", "E", "E", "-", "L*", "-", "-"),
    },
    "communication": {
        "label": "Communication",
        "group": "administration",
        "access": _row("A", "L", "A", "E", "L", "L", "L", "L*", "L*"),
    },
    # Separe de "communication": l'objet porte le jeton d'API du fournisseur
    # SMS en clair. Le fondre dans la communication l'exposait en lecture a
    # l'enseignant, au comptable et au surveillant.
    "sms_config": {
        "label": "Passerelle SMS",
        "group": "administration",
        "access": _row("A", "-", "A", "-", "-", "-", "-", "-", "-"),
    },
    # Ouvert a tous: la messagerie s'autorise objet par objet (membre de la
    # conversation, administrateur du groupe). La matrice ne fait ici
    # qu'ouvrir le module, elle ne remplace pas ces controles.
    "chat": {
        "label": "Messagerie",
        "group": "administration",
        "access": _row("A", "A", "A", "A", "A", "A", "A", "A*", "A*"),
    },
    "reports": {
        "label": "Rapports",
        "group": "administration",
        "access": _row("A", "L", "A", "L", "L", "L", "L*", "L*", "L*"),
    },
    "users": {
        "label": "Gestion des utilisateurs",
        "group": "administration",
        "access": _row("A", "-", "E", "-", "-", "-", "-", "-", "-"),
    },
    "etablissements": {
        "label": "Gestion etablissements",
        "group": "administration",
        "access": _row("A", "L", "L", "-", "-", "-", "-", "-", "-"),
    },
    "activity_logs": {
        "label": "Logs activites",
        "group": "administration",
        "access": _row("A", "L", "L", "-", "-", "-", "-", "-", "-"),
    },
    "backup_restore": {
        "label": "Backup & Restore",
        "group": "administration",
        "access": _row("A", "-", "L", "-", "-", "-", "-", "-", "-"),
    },
    "library": {
        "label": "Bibliotheque",
        "group": "ressources",
        "access": _row("A", "L", "A", "L", "-", "E", "L", "L*", "L*"),
    },
    "canteen": {
        "label": "Cantine",
        "group": "ressources",
        "access": _row("A", "L", "A", "-", "E", "E", "-", "L*", "L*"),
    },
    "stock": {
        "label": "Stock & Fournitures",
        "group": "ressources",
        "access": _row("A", "L", "A", "-", "E", "L", "-", "-", "-"),
    },
}

MODULE_KEYS = tuple(MODULES.keys())


# --- Lecture de la matrice -------------------------------------------------


class UnknownModule(KeyError):
    """Un module interroge ne figure pas dans la matrice."""


def _cell(role: str, module: str) -> str:
    try:
        row = MODULES[module]["access"]
    except KeyError as exc:  # pragma: no cover - garde-fou de developpement
        raise UnknownModule(module) from exc
    return row.get(role, "-")


def access_level(role: str, module: str) -> int:
    """Niveau accorde, 0 si le role est inconnu: on echoue ferme."""
    return _CODES[_cell(role, module).rstrip("*")]


def is_scoped(role: str, module: str) -> bool:
    """True si l'acces est limite au perimetre personnel du role."""
    return _cell(role, module).endswith("*")


def can_read(role: str, module: str) -> bool:
    return access_level(role, module) >= READ


def can_write(role: str, module: str) -> bool:
    return access_level(role, module) >= WRITE


def can_delete(role: str, module: str) -> bool:
    return access_level(role, module) >= ADMIN


def allows(role: str, module: str, method: str) -> bool:
    return access_level(role, module) >= required_level(method)


def role_payload(role: str) -> dict:
    """Matrice d'un role, telle que servie au frontend.

    Les modules sans acces sont inclus avec level "none": le client doit
    pouvoir distinguer "module masque" de "module inconnu de cette version".
    """
    modules = {}
    for key, spec in MODULES.items():
        level = access_level(role, key)
        modules[key] = {
            "label": spec["label"],
            "group": spec["group"],
            "level": LEVEL_NAMES[level],
            "read": level >= READ,
            "write": level >= WRITE,
            "delete": level >= ADMIN,
            "scoped": is_scoped(role, key),
        }
    return {
        "role": role,
        "role_label": ROLE_LABELS.get(role, role),
        "groups": [{"key": key, "label": label} for key, label in MODULE_GROUPS],
        "modules": modules,
    }
