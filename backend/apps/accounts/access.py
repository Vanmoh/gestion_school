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


# --- Hierarchie d'administration des comptes -------------------------------
# Le rang ne dit pas ce qu'un role peut lire ou ecrire -- c'est le role de la
# matrice ci-dessous. Il repond a une autre question, qu'aucune colonne ne
# posait: sur QUI un compte peut agir quand il administre les utilisateurs.
#
# Sans cette echelle, "ecriture sur le module users" voulait dire ecriture sur
# n'importe quel compte, le sien et ceux au-dessus compris. Un directeur
# pouvait donc creer un super-administrateur, ou reinitialiser le mot de passe
# de celui qui existait, et obtenir d'un coup la restauration de la base, tous
# les etablissements et la passerelle SMS -- les trois choses que la matrice
# lui refuse par ailleurs.
#
# Les rangs egaux (censeur et comptable, surveillant et enseignant) sont
# voulus: aucun des deux n'administre l'autre.

ROLE_RANKS = {
    SUPER_ADMIN: 60,
    PROMOTER: 50,
    DIRECTOR: 40,
    CENSOR: 30,
    ACCOUNTANT: 30,
    SUPERVISOR: 20,
    TEACHER: 20,
    PARENT: 10,
    STUDENT: 10,
}


def role_rank(role: str) -> int:
    """Rang d'un role, 0 s'il est inconnu: on echoue ferme."""
    return ROLE_RANKS.get(role, 0)


def peut_administrer_compte(role_acteur: str, role_cible: str) -> bool:
    """Peut-on creer, modifier, ou reinitialiser un compte de ce role?

    Strictement en dessous de soi. Un directeur ne nomme donc pas un autre
    directeur -- c'est au super-administrateur de le faire. La regle est plus
    seche que necessaire dans le cas courant, mais c'est la seule qui ne
    laisse aucun chemin vers une promotion de soi-meme par personne
    interposee.
    """
    if role_acteur == SUPER_ADMIN:
        return True
    rang_acteur = role_rank(role_acteur)
    rang_cible = role_rank(role_cible)
    if rang_acteur == 0 or rang_cible == 0:
        return False
    return rang_acteur > rang_cible


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
    # Parent et eleve en L*: ils lisaient deja les notes, les absences, la
    # discipline et les frais de leur perimetre, mais pas la fiche elle-meme --
    # ni classe, ni matricule, ni contacts enregistres. Une erreur sur un
    # numero de telephone leur restait donc invisible.
    #
    # L'ouverture ne porte que la lecture: StudentViewSet.get_queryset() rend
    # a l'eleve son seul dossier et au parent ceux de ses enfants, et la
    # saisie comme la suppression restent hors de leur portee.
    "students": {
        "label": "Gestion des eleves",
        "group": "pedagogie",
        "access": _row("A", "L", "A", "L", "L", "L", "L*", "L*", "L*"),
    },
    # Ecran de consultation seule: on reprend exactement les colonnes de
    # "students" en retirant l'ecriture (A -> L). Personne n'y gagne un acces
    # qu'il n'avait pas, et le dossier reste cloisonne par
    # StudentViewSet.get_queryset() de toute facon.
    "student_lookup": {
        "label": "Recherche eleve",
        "group": "pedagogie",
        "access": _row("L", "L", "L", "L", "L", "L", "L*", "L*", "L*"),
    },
    "teachers": {
        "label": "Enseignants",
        "group": "pedagogie",
        "access": _row("A", "L", "A", "L", "L", "-", "-", "-", "-"),
    },
    # Deux colonnes ont ete resserrees apres relecture de l'etablissement.
    #
    # Le promoteur passe de la saisie a la lecture: il ne fait pas l'appel. La
    # colonne venait d'une liste de roles locale a AttendanceViewSet, remontee
    # telle quelle dans la matrice sans que personne ait verifie qu'elle
    # decrivait le travail reel.
    #
    # Le comptable perd la lecture: la facturation ne s'appuie pas sur les
    # absences, et savoir quel eleve manquait mardi ne le regarde pas.
    #
    # Valider et verrouiller une fiche demande l'ecriture sans portee
    # restreinte: l'enseignant (E*) saisit l'appel de ses classes mais ne
    # cloture pas, ce que la colonne dit deja sans niveau supplementaire.
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
    # Comptable et surveillant en lecture: l'ecran « Gestion des eleves »
    # charge les classes et les annees scolaires avant d'afficher quoi que ce
    # soit. Sans ce droit, il ne leur rendait que son message d'erreur -- une
    # entree de menu qui ne menait nulle part, et que personne n'avait
    # signalee.
    "academics": {
        "label": "Academique",
        "group": "academique",
        "access": _row("A", "L", "A", "E", "L", "L", "L", "-", "-"),
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
    # Le promoteur en lecture: proprietaire de l'etablissement, il ne voyait
    # pas qui y detenait un acces. Il consulte, il n'administre pas -- creer,
    # modifier et couper un compte restent a la direction.
    "users": {
        "label": "Gestion des utilisateurs",
        "group": "administration",
        "access": _row("A", "L", "E", "-", "-", "-", "-", "-", "-"),
    },
    # Le directeur en E*: le nom, l'adresse, le telephone, le logo et l'en-tete
    # imprime sur les bulletins ne se corrigeaient que par le
    # super-administrateur, ce qui immobilisait l'etablissement le temps d'une
    # demande. L'etoile n'est pas decorative ici: EtablissementViewSet refuse
    # la creation aux roles restreints et limite la modification a leur propre
    # etablissement. La suppression reste au niveau A, hors de leur portee.
    "etablissements": {
        "label": "Gestion etablissements",
        "group": "administration",
        "access": _row("A", "L", "E*", "-", "-", "-", "-", "-", "-"),
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
