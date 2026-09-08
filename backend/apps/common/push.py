"""L'envoi des notifications push, par Firebase Cloud Messaging.

Le module Communication enregistrait ses notifications en base avec
`is_sent=False`, et rien ne le repassait jamais a True: aucune passerelle
n'existait. Les familles ne recevaient donc rien -- ni push, ni SMS, ni
courriel -- alors que c'est la raison d'etre du module.

Ce fichier ferme la premiere de ces trois portes.

Ce qu'il faut pour qu'il fonctionne
-----------------------------------
Un projet Firebase, et le compte de service qui va avec:

    FCM_PROJECT_ID=mon-projet
    FCM_CREDENTIALS_FILE=/chemin/vers/compte-de-service.json

ou, sur un hebergeur qui ne monte pas de fichier:

    FCM_CREDENTIALS_JSON={"type":"service_account",...}

Sans ces variables, `envoyer_a_des_appareils` rend un echec explicite au lieu
de lever: une ecole doit pouvoir tourner sans push, et une notification non
partie doit rester en base pour un envoi ulterieur.

Pourquoi HTTP v1 et non l'ancienne API a cle serveur: Google a ferme
l'endpoint « legacy » en 2024. La v1 signe chaque appel avec un jeton OAuth2
derive du compte de service, ce que `google-auth` fait pour nous.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field

import requests
from django.conf import settings

logger = logging.getLogger(__name__)

PORTEE_FCM = "https://www.googleapis.com/auth/firebase.messaging"

# Au-dela, le reseau de l'ecole est probablement coupe: mieux vaut rendre la
# main et reessayer au prochain passage que d'immobiliser un worker.
DELAI_ENVOI_SECONDES = 10


@dataclass
class ResultatEnvoi:
    """Ce qu'un envoi a produit, jeton par jeton.

    `jetons_invalides` est ce qui compte le plus a l'usage: un telephone
    reinitialise ou une application desinstallee rendent un jeton mort, et
    l'appelant doit pouvoir le retirer de la base plutot que de reessayer
    chaque nuit.
    """

    envoyes: int = 0
    echecs: int = 0
    jetons_invalides: list[str] = field(default_factory=list)
    erreur: str = ""

    @property
    def a_reussi(self) -> bool:
        return self.envoyes > 0 and not self.erreur


def _identifiants():
    """Les identifiants du compte de service, ou None s'ils manquent.

    Le fichier et la variable JSON sont acceptes tous les deux: un serveur
    d'ecole monte un fichier, un hebergeur cloud passe le contenu en
    variable d'environnement.
    """
    try:
        from google.oauth2 import service_account
    except ImportError:  # pragma: no cover - dependance absente
        logger.warning("google-auth n'est pas installe: push desactive.")
        return None

    contenu = str(getattr(settings, "FCM_CREDENTIALS_JSON", "") or "").strip()
    if contenu:
        try:
            donnees = json.loads(contenu)
        except json.JSONDecodeError:
            logger.error("FCM_CREDENTIALS_JSON n'est pas un JSON valide.")
            return None
        return service_account.Credentials.from_service_account_info(
            donnees, scopes=[PORTEE_FCM]
        )

    chemin = str(getattr(settings, "FCM_CREDENTIALS_FILE", "") or "").strip()
    if not chemin:
        return None
    try:
        return service_account.Credentials.from_service_account_file(
            chemin, scopes=[PORTEE_FCM]
        )
    except (OSError, ValueError) as erreur:
        logger.error("Compte de service FCM illisible: %s", erreur)
        return None


def _jeton_d_acces():
    identifiants = _identifiants()
    if identifiants is None:
        return None
    try:
        from google.auth.transport.requests import Request

        identifiants.refresh(Request())
    except Exception as erreur:  # pragma: no cover - reseau
        logger.error("Jeton OAuth2 FCM refuse: %s", erreur)
        return None
    return identifiants.token


def push_configure() -> bool:
    """Vrai quand le projet et les identifiants sont renseignes.

    Sert au controle de deploiement et a l'ecran de configuration: repondre
    « non configure » vaut mieux qu'un echec d'envoi silencieux.
    """
    return bool(
        str(getattr(settings, "FCM_PROJECT_ID", "") or "").strip()
        and (
            str(getattr(settings, "FCM_CREDENTIALS_JSON", "") or "").strip()
            or str(getattr(settings, "FCM_CREDENTIALS_FILE", "") or "").strip()
        )
    )


def _jeton_est_mort(reponse) -> bool:
    """Vrai quand le refus vise l'appareil, et non le message.

    404 (UNREGISTERED) est le signal franc: l'application a ete desinstallee
    ou le telephone reinitialise.

    400 demande de la prudence. FCM le rend aussi bien pour un jeton
    illisible que pour un message mal forme -- un titre trop long, une
    valeur `data` non conforme. Fermer les jetons sur un simple 400
    reviendrait, le jour ou une notification serait mal construite, a
    couper les notifications de toute l'ecole en une passe. On ne ferme donc
    que si le corps de la reponse designe explicitement le jeton.
    """
    if reponse.status_code == 404:
        return True
    if reponse.status_code != 400:
        return False

    try:
        corps = reponse.json()
    except ValueError:
        return False

    erreur = corps.get("error", {}) if isinstance(corps, dict) else {}
    details = erreur.get("details") or []
    for detail in details:
        if not isinstance(detail, dict):
            continue
        if detail.get("errorCode") == "UNREGISTERED":
            return True
        for violation in detail.get("fieldViolations") or []:
            if isinstance(violation, dict) and "token" in str(
                violation.get("field", "")
            ):
                return True
    return False


def envoyer_a_des_appareils(
    jetons, *, titre: str, message: str, donnees: dict | None = None
) -> ResultatEnvoi:
    """Envoie une notification a une liste de jetons d'appareil.

    FCM v1 n'accepte qu'un destinataire par appel: la boucle est donc dans
    notre camp. C'est acceptable ici -- une notification vise une famille,
    rarement plus de deux ou trois appareils.
    """
    jetons = [str(jeton).strip() for jeton in jetons if str(jeton or "").strip()]
    resultat = ResultatEnvoi()
    if not jetons:
        return resultat

    if not push_configure():
        resultat.erreur = (
            "Push non configure: renseignez FCM_PROJECT_ID et le compte de "
            "service (FCM_CREDENTIALS_FILE ou FCM_CREDENTIALS_JSON)."
        )
        return resultat

    jeton_acces = _jeton_d_acces()
    if not jeton_acces:
        resultat.erreur = "Identifiants FCM refuses."
        return resultat

    projet = str(settings.FCM_PROJECT_ID).strip()
    url = f"https://fcm.googleapis.com/v1/projects/{projet}/messages:send"
    entetes = {
        "Authorization": f"Bearer {jeton_acces}",
        "Content-Type": "application/json; UTF-8",
    }

    for jeton in jetons:
        charge = {
            "message": {
                "token": jeton,
                "notification": {"title": titre, "body": message},
                # Les valeurs doivent etre des chaines: FCM refuse l'entier.
                "data": {
                    cle: str(valeur) for cle, valeur in (donnees or {}).items()
                },
            }
        }
        try:
            reponse = requests.post(
                url, headers=entetes, json=charge, timeout=DELAI_ENVOI_SECONDES
            )
        except requests.RequestException as erreur:
            resultat.echecs += 1
            resultat.erreur = str(erreur)[:255]
            continue

        if reponse.status_code == 200:
            resultat.envoyes += 1
            continue

        resultat.echecs += 1
        if _jeton_est_mort(reponse):
            resultat.jetons_invalides.append(jeton)
        if not resultat.erreur:
            resultat.erreur = f"FCM {reponse.status_code}: {reponse.text[:180]}"

    return resultat
