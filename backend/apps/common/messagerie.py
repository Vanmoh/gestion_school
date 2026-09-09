"""Les deux autres canaux vers les familles: le courriel et le SMS.

Le module Communication promettait trois canaux; seul le push etait branche.
Les notifications de courriel et de SMS restaient en attente, ce qui etait
honnete -- les marquer envoyees aurait ete mentir -- mais laissait les
familles sans nouvelles.

Le courriel part par Django, dont le backend se regle par variables
d'environnement. Le SMS part par la passerelle que l'ecole a declaree dans
`SmsProviderConfig`: une URL, un jeton, un identifiant d'expediteur. Les
operateurs maliens (Orange, Malitel) et les agregateurs exposent tous une API
HTTP de cette forme; ce qui change d'un fournisseur a l'autre est le nom des
champs, d'ou la petite table de correspondance plus bas.

Comme pour le push: sans configuration, l'envoi echoue proprement et la
notification reste en base pour un envoi ulterieur. Une ecole doit pouvoir
tourner sans aucun de ces canaux.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

import requests
from django.conf import settings
from django.core.mail import EmailMessage, get_connection

logger = logging.getLogger(__name__)

# Au-dela, le reseau de l'ecole ne repond pas: mieux vaut rendre la main et
# reessayer au prochain passage que d'immobiliser un worker.
DELAI_ENVOI_SECONDES = 15


@dataclass
class ResultatMessage:
    envoye: bool = False
    erreur: str = ""


# --- Courriel --------------------------------------------------------------


def courriel_configure() -> bool:
    """Vrai quand un serveur d'envoi est renseigne.

    Le backend « console » de developpement ne compte pas comme configure: il
    affiche le message dans les logs, il ne l'envoie a personne. Le dire
    permet au controle de deploiement de le signaler plutot que de laisser
    croire que le courrier part.
    """
    backend = str(getattr(settings, "EMAIL_BACKEND", "") or "")
    if "smtp" not in backend:
        return False
    return bool(str(getattr(settings, "EMAIL_HOST", "") or "").strip())


def envoyer_un_courriel(
    *, destinataire: str, sujet: str, message: str
) -> ResultatMessage:
    """Un courriel a une adresse, ou un echec explicite."""
    adresse = str(destinataire or "").strip()
    if not adresse:
        return ResultatMessage(erreur="Destinataire sans adresse de courriel.")

    if not courriel_configure():
        return ResultatMessage(
            erreur=(
                "Courriel non configure: renseignez EMAIL_HOST, EMAIL_HOST_USER "
                "et EMAIL_HOST_PASSWORD."
            )
        )

    try:
        connexion = get_connection(timeout=DELAI_ENVOI_SECONDES)
        courrier = EmailMessage(
            subject=sujet,
            body=message,
            from_email=getattr(settings, "DEFAULT_FROM_EMAIL", None) or None,
            to=[adresse],
            connection=connexion,
        )
        partis = courrier.send(fail_silently=False)
    except Exception as erreur:  # pragma: no cover - reseau
        logger.warning("Courriel non parti vers %s: %s", adresse, erreur)
        return ResultatMessage(erreur=str(erreur)[:255])

    if not partis:
        return ResultatMessage(erreur="Le serveur de courriel n'a rien accepte.")
    return ResultatMessage(envoye=True)


# --- SMS -------------------------------------------------------------------

# Ce qui change d'un fournisseur a l'autre est le nom des champs, pas la
# forme de l'appel. Cette table couvre les conventions les plus repandues;
# un fournisseur exotique se traite en ajoutant une entree, sans toucher au
# reste.
CHAMPS_PAR_FOURNISSEUR = {
    # Convention la plus courante (Orange, Twilio-like, la plupart des
    # agregateurs ouest-africains).
    "defaut": {"destinataire": "to", "texte": "message", "expediteur": "from"},
    "twilio": {"destinataire": "To", "texte": "Body", "expediteur": "From"},
    "nexmo": {"destinataire": "to", "texte": "text", "expediteur": "from"},
    "vonage": {"destinataire": "to", "texte": "text", "expediteur": "from"},
}


def _champs(nom_du_fournisseur: str) -> dict:
    cle = re.sub(r"[^a-z]", "", str(nom_du_fournisseur or "").lower())
    for connu, champs in CHAMPS_PAR_FOURNISSEUR.items():
        if connu != "defaut" and connu in cle:
            return champs
    return CHAMPS_PAR_FOURNISSEUR["defaut"]


def passerelle_sms(etablissement):
    """La passerelle active de cet etablissement, ou None.

    Chaque ecole a la sienne: le contrat est signe par l'etablissement, pas
    par l'editeur.
    """
    from apps.school.models import SmsProviderConfig

    if etablissement is None:
        return None
    return (
        SmsProviderConfig.objects.filter(etablissement=etablissement, is_active=True)
        .order_by("-id")
        .first()
    )


def envoyer_un_sms(*, passerelle, numero: str, message: str) -> ResultatMessage:
    """Un SMS par la passerelle declaree par l'ecole.

    Le numero est envoye tel qu'il est enregistre: il a deja ete normalise a
    la saisie (apps/school/phone_utils.py), et le renormaliser ici risquerait
    d'en changer la forme attendue par le fournisseur.
    """
    if passerelle is None:
        return ResultatMessage(
            erreur=(
                "Aucune passerelle SMS active: declarez-en une dans "
                "Communication > Fournisseurs SMS."
            )
        )

    destinataire = str(numero or "").strip()
    if not destinataire:
        return ResultatMessage(erreur="Destinataire sans numero de telephone.")

    champs = _champs(passerelle.provider_name)
    charge = {
        champs["destinataire"]: destinataire,
        champs["texte"]: message,
    }
    if passerelle.sender_id:
        charge[champs["expediteur"]] = passerelle.sender_id

    try:
        reponse = requests.post(
            passerelle.api_url,
            json=charge,
            headers={"Authorization": f"Bearer {passerelle.api_token}"},
            timeout=DELAI_ENVOI_SECONDES,
        )
    except requests.RequestException as erreur:
        return ResultatMessage(erreur=str(erreur)[:255])

    if 200 <= reponse.status_code < 300:
        return ResultatMessage(envoye=True)

    # Le corps de la reponse porte la raison du refus -- credit epuise,
    # numero invalide, expediteur non declare -- et c'est elle qui permet a
    # l'ecole d'agir. La tronquer, pas la perdre.
    return ResultatMessage(
        erreur=f"Passerelle {reponse.status_code}: {reponse.text[:180]}"
    )
