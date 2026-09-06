"""Normalisation des numeros de telephone au format international E.164.

Le repertoire de l'ecole est saisi a la main, sur trente ans d'habitudes
differentes: « 76 12 34 56 », « 0022376123456 », « +223 76-12-34-56 » et
« 76123456 » designent la meme famille. Tant que ces numeros ne servaient
qu'a etre lus par un humain, la divergence ne genait personne.

Elle devient bloquante des qu'un programme compose: une passerelle WhatsApp
n'accepte qu'une seule forme, sans espace ni indicatif national implicite.

Ce module ne devine jamais. Il normalise ce qui est certain et refuse le
reste -- un bulletin scolaire envoye au mauvais numero ne se rattrape pas.
"""

from __future__ import annotations

import re

from django.conf import settings

# Tout ce qu'un humain intercale pour rendre un numero lisible.
_SEPARATEURS = re.compile(r"[\s.\-() ]+")

# E.164: un « + », un indicatif qui ne commence pas par zero, et de 8 a 15
# chiffres en tout. La borne haute est celle de la norme; la borne basse
# ecarte les numeros courts (services, urgences) qui ne recoivent rien.
_E164 = re.compile(r"^\+[1-9]\d{7,14}$")

# Deux numeros dans une seule case (« 76 12 34 56 / 66 74 22 32 ») est la
# forme la plus courante des fiches papier. On ne tranche pas a leur place.
_MULTIPLE = re.compile(r"[/,;]|\bou\b", re.IGNORECASE)


def indicatif_par_defaut() -> str:
    """Indicatif applique a un numero saisi sans lui, sans le « + »."""
    brut = str(getattr(settings, "DEFAULT_PHONE_COUNTRY_CODE", "") or "").strip()
    return brut.lstrip("+")


def longueur_nationale() -> int:
    """Nombre de chiffres d'un numero du pays par defaut, 0 si indifferent.

    Sans ce controle, un numero recopie a moitie (« 76 12 34 ») passait: la
    seule regle E.164 se contente de huit chiffres tous indicatifs confondus,
    et « +223761234 » lui convient. Un tel numero n'est pas invalide en
    theorie -- il est simplement inexistant, et l'envoi partait dans le vide
    sans que personne ne s'en apercoive.
    """
    try:
        longueur = int(getattr(settings, "NATIONAL_PHONE_LENGTH", 8))
    except (TypeError, ValueError):
        return 0
    return max(0, longueur)


def normaliser_numero(brut, indicatif_defaut: str | None = None) -> str | None:
    """Renvoie le numero au format E.164, ou None s'il est inexploitable.

    None n'est pas un echec silencieux: l'appelant l'affiche a l'ecole comme
    « numero a corriger ». C'est la seule issue honnete face a une saisie
    ambigue, la ou un choix arbitraire enverrait le bulletin d'un eleve chez
    quelqu'un d'autre.
    """
    texte = str(brut or "").strip()
    if not texte:
        return None

    # Deux numeros dans la meme case: lequel des deux est celui du tuteur?
    # Personne ici ne peut le savoir.
    if _MULTIPLE.search(texte):
        return None

    # « 00223... » est la forme internationale composee depuis un poste fixe.
    if texte.startswith("00"):
        texte = "+" + texte[2:]

    plus_en_tete = texte.startswith("+")
    chiffres = _SEPARATEURS.sub("", texte).lstrip("+")
    if not chiffres.isdigit():
        return None

    if plus_en_tete:
        candidat = "+" + chiffres
    else:
        indicatif = (indicatif_defaut if indicatif_defaut is not None else indicatif_par_defaut()).lstrip("+")
        if not indicatif:
            # Sans indicatif de reference, un numero national reste
            # inexploitable: « 76123456 » n'existe pas hors de son pays.
            return None
        if chiffres.startswith(indicatif) and len(chiffres) > len(indicatif):
            # L'indicatif etait deja la, sans le « + ».
            candidat = "+" + chiffres
        else:
            candidat = "+" + indicatif + chiffres.lstrip("0")

    if not _E164.match(candidat):
        return None

    # Controle de longueur sur le seul pays que l'on connaisse: celui par
    # defaut. Pour un numero etranger explicite, la regle E.164 generique est
    # tout ce dont on dispose -- inventer une longueur par pays serait un
    # annuaire mondial a maintenir.
    indicatif_connu = indicatif_par_defaut()
    attendue = longueur_nationale()
    if indicatif_connu and attendue:
        national = candidat.lstrip("+")
        if national.startswith(indicatif_connu):
            if len(national) - len(indicatif_connu) != attendue:
                return None

    return candidat


def est_au_format_e164(valeur) -> bool:
    """Vrai si la valeur est deja un E.164 valide, sans transformation."""
    return bool(_E164.match(str(valeur or "")))
