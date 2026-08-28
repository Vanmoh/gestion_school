"""Le matricule eleve: son format, sa generation, sa verification.

    RC15    CG      25   E    3566     F
    ecole   classe  an   type sequence genre

Le format existait deja -- documente et fonctionnel -- mais il ne vivait que
dans `seed_ltob_data`, une commande de demonstration. Le flux d'inscription
reel n'en faisait rien: le matricule arrivait tel quel, saisi a la main ou
laisse vide, alors que c'est l'identifiant qui sert partout, de la recherche
au bulletin.

Il est global a la plateforme et non par etablissement: son prefixe porte
deja l'ecole, deux etablissements ne peuvent donc pas produire le meme.
"""

from __future__ import annotations

import re
import unicodedata

# Un chiffre pour l'annee sur deux positions, une lettre de type, quatre
# chiffres de sequence, une lettre de genre.
FORMAT_MATRICULE = re.compile(r"^[A-Z0-9]{2,8}[A-Z0-9]{2,6}\d{2}[A-Z]\d{4}[MFN]$")

# Marqueur du type d'inscription. « E » comme entree, seule valeur produite
# aujourd'hui; la position est reservee pour les cas qui viendront.
TYPE_ENTREE = "E"

# Genre inconnu: la fiche eleve tolere un genre vide, et un matricule doit
# pouvoir naitre quand meme.
GENRE_INCONNU = "N"


def _sans_accent(valeur: str) -> str:
    decompose = unicodedata.normalize("NFD", str(valeur or ""))
    return "".join(c for c in decompose if unicodedata.category(c) != "Mn")


def code_etablissement(etablissement) -> str:
    """Le prefixe de l'ecole: son code s'il en a un, ses initiales sinon.

    Le repli sur les initiales reproduit ce que faisait la commande de seed,
    le temps que chaque fiche recoive son code. Il n'est pas fiable -- deux
    ecoles peuvent partager des initiales -- d'ou le champ dedie.
    """
    if etablissement is None:
        return "GS"

    code = (getattr(etablissement, "code", "") or "").strip().upper()
    if code:
        return code

    mots = re.findall(r"[A-Z0-9]+", _sans_accent(etablissement.name).upper())
    if len(mots) >= 2:
        return "".join(mot[0] for mot in mots[:2])
    if mots:
        return mots[0][:2]
    return "GS"


# Mots qui n'apprennent rien sur la classe: ce qui la distingue de sa voisine
# est son rang et sa filiere, pas le mot « annee ».
MOTS_GENERIQUES = {"ANNEE", "ANNEES", "CLASSE", "CLASSES", "NIVEAU"}

# Huit caracteres: « 12TSECO1 » tient, et c'est le plus long des libelles
# reels. Tronquer plus court confondait « 12eme TSECO1 » et « 12eme TSECO2 ».
LONGUEUR_CODE_CLASSE = 8


def code_classe(classroom) -> str:
    """« 11ème CG » devient « 11CG », « 1ère Année DB1 » devient « 1DB1 ».

    Le code doit distinguer deux classes voisines, c'est sa seule raison
    d'etre. La regle precedente gardait le mot generique et tronquait a six
    caracteres: les cinq classes de premiere annee d'une ecole -- DB1, DB2,
    EM1, EM2, TC -- recevaient toutes « 1ANNEE », et « 12eme TSECO1 » ne se
    distinguait plus de « 12eme TSECO2 ».

    Le mot generique n'est ecarte que s'il reste autre chose: une classe qui
    s'appelle « 3eme Annee » tout court garde « 3AN », faute de quoi son code
    se reduirait au seul chiffre du rang.
    """
    if classroom is None:
        return "XX"

    brut = _sans_accent(classroom.name).upper()
    # « 11EME CG » -> « 11 CG ». Les ordinaux francais d'abord, sinon le
    # « E » de « EME » se retrouverait dans le code.
    brut = re.sub(r"(?<=\d)\s*(EME|ERE|ER|E)\b", " ", brut)

    mots = re.findall(r"[A-Z0-9]+", brut)
    utiles = [mot for mot in mots if mot not in MOTS_GENERIQUES]
    # Rien d'autre que le generique et un rang: on l'abrege plutot que de le
    # perdre, sinon « 3eme Annee » se reduirait a « 3 ».
    if not any(re.search(r"[A-Z]", mot) for mot in utiles):
        utiles = [
            mot[:2] if mot in MOTS_GENERIQUES else mot for mot in mots
        ]

    code = "".join(utiles)
    return code[:LONGUEUR_CODE_CLASSE] or "XX"


def code_genre(genre) -> str:
    valeur = (genre or "").strip().upper()
    return valeur if valeur in ("M", "F") else GENRE_INCONNU


def prefixe(etablissement, classroom, annee_entree: int) -> str:
    """Tout ce qui precede la sequence: ecole, classe, annee, type."""
    return (
        f"{code_etablissement(etablissement)}"
        f"{code_classe(classroom)}"
        f"{str(annee_entree)[-2:]}"
        f"{TYPE_ENTREE}"
    )


def prochaine_sequence(prefixe_vise: str, modele_eleve) -> int:
    """Le premier numero libre derriere ce prefixe.

    Lu depuis les matricules eux-memes et non depuis un compteur a part: un
    eleve supprime, un import repris, une reprise de donnees laissent un
    compteur separe mentir, alors que les matricules, eux, disent la verite.
    """
    existants = modele_eleve.objects.filter(
        matricule__startswith=prefixe_vise
    ).values_list("matricule", flat=True)

    maximum = 0
    longueur = len(prefixe_vise)
    for matricule in existants:
        reste = matricule[longueur:]
        if len(reste) >= 5 and reste[:4].isdigit():
            maximum = max(maximum, int(reste[:4]))
    return maximum + 1


def generer(student, modele_eleve=None) -> str:
    """Le matricule d'un eleve, deduit de sa fiche.

    `modele_eleve` permet a une migration de passer son propre modele
    historique, qui n'est pas celui importe ici.
    """
    if modele_eleve is None:
        from apps.school.models import Student as modele_eleve  # noqa: N813

    classroom = student.classroom
    etablissement = student.etablissement or getattr(classroom, "etablissement", None)

    # L'annee scolaire de la classe d'abord, la date d'inscription ensuite:
    # un eleve inscrit en janvier appartient a l'annee ouverte en septembre,
    # et c'est elle que son matricule doit porter.
    annee_scolaire = getattr(classroom, "academic_year", None)
    debut = getattr(annee_scolaire, "start_date", None)
    if debut is not None:
        annee = debut.year
    else:
        inscription = getattr(student, "enrollment_date", None)
        annee = inscription.year if inscription is not None else 0

    debut_matricule = prefixe(etablissement, classroom, annee)
    sequence = prochaine_sequence(debut_matricule, modele_eleve)
    return f"{debut_matricule}{sequence:04d}{code_genre(student.gender)}"


def est_conforme(matricule: str) -> bool:
    """Le matricule respecte-t-il la forme attendue.

    Volontairement tolerante sur la longueur des codes d'ecole et de classe:
    les etablissements n'ont pas tous des noms de meme calibre, et refuser un
    matricule deja imprime sur une carte scolaire ne rendrait service a
    personne.
    """
    return bool(FORMAT_MATRICULE.match((matricule or "").strip().upper()))
