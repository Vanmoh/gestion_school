"""Verification d'une carte scolaire scannee.

Une carte sans preuve ne prouve rien: celle de 2019 est indiscernable de celle
de l'annee en cours, et rien n'empeche d'en fabriquer une. Le QR imprime porte
donc une signature que seul le serveur peut produire.

La page de verification n'affiche aucune identite. Une carte perdue, ramassee
et scannee par un inconnu ne doit rien apprendre sur l'eleve: elle repond
« valide », nomme l'ecole et l'annee, et montre la photo pour que celui qui
controle compare un visage. C'est ce qu'il faut au portail, et rien de plus.

Consequence a connaitre avant de toucher a la configuration: la signature
derive de SECRET_KEY. Une rotation de cette cle -- le premier reflexe apres
une fuite -- invalide toutes les cartes deja imprimees, qui ne sont pas des
jetons qu'on renouvelle mais des cartons en poche. Il faudrait alors les
reimprimer toutes. Si ce couplage devient genant, faire deriver la signature
d'une cle dediee que l'on puisse garder pendant qu'on change l'autre.
"""

from __future__ import annotations

import hashlib
import hmac

from django.conf import settings

# Assez court pour tenir dans un QR lisible a 15 mm de cote, assez long pour
# qu'une carte ne se falsifie pas par tatonnement: 16 caracteres hexadecimaux
# valent 64 bits, soit 1,8 x 10^19 essais.
LONGUEUR_SIGNATURE = 16

_SEL = "carte-scolaire.v1"


def _empreinte(student_id: int, annee: str) -> str:
    message = f"{_SEL}:{int(student_id)}:{annee}".encode("utf-8")
    cle = str(settings.SECRET_KEY).encode("utf-8")
    return hmac.new(cle, message, hashlib.sha256).hexdigest()[:LONGUEUR_SIGNATURE]


def signer(student_id: int, annee: str) -> str:
    """Signature a imprimer dans le QR de la carte."""
    return _empreinte(student_id, annee)


def signature_valide(student_id: int, annee: str, signature: str) -> bool:
    """Vrai si la signature correspond a cet eleve pour cette annee.

    `compare_digest` plutot que `==`: la comparaison naive s'arrete au premier
    caractere different, et le temps de reponse revele alors combien de
    caracteres etaient justes.
    """
    if not signature:
        return False
    return hmac.compare_digest(_empreinte(student_id, annee), str(signature))
