"""Preparation de l'envoi d'un bulletin a la famille, par WhatsApp.

Ce module ne parle a aucune passerelle. Il fabrique ce qu'il faut pour qu'un
bulletin parte: le PDF, un lien de telechargement qui expire, le texte du
message, et le lien `wa.me` qui ouvre WhatsApp deja rempli.

Pourquoi un lien plutot que le fichier joint. Joindre un PDF a une
conversation WhatsApp exige la Cloud API de Meta, donc un compte business
verifie, un numero dedie, un modele de message approuve et une facturation
par conversation. Le lien, lui, fonctionne aujourd'hui, sans compte, sans
delai d'approbation et sans cout -- et il apprend en prime si la famille a
ouvert le bulletin, ce qu'une piece jointe ne dit pas. Le jour ou la
passerelle sera ouverte, `CANAL_CLOUD_API` prendra le relais sans que rien
d'autre ne bouge ici.

Le lien porte une signature HMAC et une date d'expiration parce qu'il voyage
hors de toute session: un parent n'a pas de compte, et l'URL doit donc se
suffire a elle-meme. Comme pour la carte scolaire, la signature derive de
SECRET_KEY -- une rotation de cette cle invalide les liens deja envoyes, ce
qui est ici sans gravite: ils durent trois jours.
"""

from __future__ import annotations

import hashlib
import hmac
from urllib.parse import quote

from django.conf import settings
from django.utils import timezone

_SEL = "bulletin-partage.v1"

# Assez long pour qu'un lien ne se devine pas par tatonnement, sans rendre
# l'URL illisible dans une conversation: 32 caracteres hexadecimaux valent
# 128 bits.
LONGUEUR_SIGNATURE = 32


def _empreinte(student_id: int, academic_year_id: int, term: str, expire: int) -> str:
    message = f"{_SEL}:{int(student_id)}:{int(academic_year_id)}:{term}:{int(expire)}".encode("utf-8")
    cle = str(settings.SECRET_KEY).encode("utf-8")
    return hmac.new(cle, message, hashlib.sha256).hexdigest()[:LONGUEUR_SIGNATURE]


def duree_de_validite_heures() -> int:
    try:
        heures = int(getattr(settings, "BULLETIN_LINK_TTL_HOURS", 72))
    except (TypeError, ValueError):
        heures = 72
    return max(1, heures)


def signer(student_id: int, academic_year_id: int, term: str, expire: int) -> str:
    """Signature du lien de telechargement d'un bulletin."""
    return _empreinte(student_id, academic_year_id, term, expire)


def signature_valide(student_id: int, academic_year_id: int, term: str, expire: int, signature: str) -> bool:
    """Vrai si la signature correspond, sans se prononcer sur l'expiration.

    `compare_digest` plutot que `==`: la comparaison naive s'arrete au premier
    caractere different, et le temps de reponse revele alors combien de
    caracteres etaient justes.
    """
    if not signature:
        return False
    attendue = _empreinte(student_id, academic_year_id, term, expire)
    return hmac.compare_digest(attendue, str(signature))


def lien_expire(expire: int) -> bool:
    try:
        echeance = int(expire)
    except (TypeError, ValueError):
        return True
    return echeance < int(timezone.now().timestamp())


def horodatage_d_expiration(heures: int | None = None) -> int:
    """Date limite du lien, en secondes depuis l'epoque."""
    duree = duree_de_validite_heures() if heures is None else max(1, int(heures))
    return int(timezone.now().timestamp()) + duree * 3600


def base_publique(request=None) -> str:
    """Racine des URL envoyees aux familles.

    Le reglage l'emporte sur la requete: le lien est fabrique par une requete
    de l'application, qui peut arriver par une adresse interne ou un tunnel
    de developpement -- inatteignable depuis le telephone d'un parent.
    """
    configuree = str(getattr(settings, "PUBLIC_BASE_URL", "") or "").strip().rstrip("/")
    if configuree:
        return configuree
    if request is not None:
        return request.build_absolute_uri("/").rstrip("/")
    return ""


def chemin_de_partage(student_id: int, academic_year_id: int, term: str, expire: int, signature: str) -> str:
    return (
        f"/api/reports/bulletin-partage/{int(student_id)}/{int(academic_year_id)}/"
        f"{quote(str(term), safe='')}/{int(expire)}/{signature}/"
    )


def lien_de_telechargement(
    *,
    student_id: int,
    academic_year_id: int,
    term: str,
    request=None,
    expire: int | None = None,
) -> str:
    """URL complete, signee et datee, du bulletin."""
    echeance = horodatage_d_expiration() if expire is None else int(expire)
    signature = signer(student_id, academic_year_id, term, echeance)
    return base_publique(request) + chemin_de_partage(
        student_id, academic_year_id, term, echeance, signature
    )


def generer_pdf_bulletin(*, student, academic_year_id: int, normalized_term: str) -> bytes:
    """Le bulletin en PDF, hors de toute requete HTTP.

    Import differe: `apps.reports.views` importe ce module pour servir les
    endpoints d'envoi, et l'importer ici a la racine fermerait le cycle. Le
    rendu n'est volontairement pas duplique -- un bulletin envoye au parent
    qui differerait de celui imprime au secretariat serait pire que pas
    d'envoi du tout.
    """
    from fpdf import FPDF

    from apps.reports.views import _build_bulletin_payload, _render_bulletin_page

    payload = _build_bulletin_payload(
        student=student,
        academic_year_id=academic_year_id,
        normalized_term=normalized_term,
    )

    pdf = FPDF(orientation="L", format="A4")
    pdf.set_auto_page_break(auto=False)
    pdf.add_page()
    _render_bulletin_page(pdf, payload)
    return bytes(pdf.output())


def nom_de_fichier_bulletin(student, term: str) -> str:
    matricule = str(getattr(student, "matricule", "") or getattr(student, "id", "") or "eleve")
    periode = str(term or "periode").replace("/", "-")
    return f"bulletin_{matricule}_{periode}.pdf"


def texte_du_message(
    *,
    nom_eleve: str,
    nom_classe: str,
    periode: str,
    annee: str,
    nom_ecole: str,
    lien: str,
) -> str:
    """Le message que lira le parent.

    Il nomme l'eleve et l'ecole avant le lien: un message qui s'ouvre sur une
    URL ressemble a une arnaque, et se fait ignorer par ceux-la memes qu'il
    faut joindre. La duree de validite y figure pour qu'un parent qui ouvre
    le message une semaine plus tard comprenne pourquoi le lien ne repond
    plus, au lieu d'appeler l'ecole.
    """
    lignes = [
        f"Bonjour, voici le bulletin de {nom_eleve}"
        + (f" ({nom_classe})" if nom_classe else "")
        + f" — {periode}, année scolaire {annee}.",
        "",
        lien,
        "",
        f"Ce lien reste valable {duree_de_validite_heures()} heures.",
    ]
    if nom_ecole:
        lignes.append(nom_ecole)
    return "\n".join(lignes)


def lien_wa_me(numero_e164: str, message: str) -> str:
    """Lien qui ouvre WhatsApp avec le message deja ecrit.

    `wa.me` n'accepte pas le « + » de la forme E.164, seulement les chiffres.
    """
    chiffres = str(numero_e164 or "").lstrip("+")
    return f"https://wa.me/{chiffres}?text={quote(message)}"
