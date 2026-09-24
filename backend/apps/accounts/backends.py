"""Ce qu'une famille tape dans le champ « identifiant ».

L'ecole remet a l'eleve son matricule et au parent son numero de telephone:
c'est ce qui est imprime sur la carte scolaire, dicte au guichet et recopie
sur un cahier. L'admission en fait effectivement l'identifiant du compte --
mais seulement depuis qu'elle existe.

Les comptes ouverts avant elle portent autre chose: « ousmane.bagayoko »
pour un eleve, « awa.traore » pour un parent, parce que la creation d'alors
composait l'identifiant a partir du nom. Ces familles-la tapaient le
matricule qu'on leur avait remis et lisaient « identifiants invalides »,
sans qu'aucun ecran puisse leur dire lequel des deux etait le bon.

Renommer les comptes aurait ferme la porte a ceux qui utilisent deja leur
identifiant actuel. On ouvre l'autre porte a la place: le matricule et le
numero ouvrent le compte au meme titre que son identifiant, et le mot de
passe reste seul a faire office de secret.
"""

from __future__ import annotations

import re

from django.contrib.auth import get_user_model
from django.contrib.auth.backends import ModelBackend
from django.db.models import Q

User = get_user_model()

# Assez de chiffres pour designer quelqu'un: en dessous, « 12 » ramenerait
# tous les numeros de l'ecole.
CHIFFRES_MINIMUM = 6


def _normaliser(valeur: str) -> str:
    """Casse et separateurs ne distinguent pas deux ecritures d'un matricule.

    Le matricule est recopie d'une carte plastifiee: les espaces et les
    tirets s'y ajoutent ou s'y perdent d'une main a l'autre.
    """
    return re.sub(r"[\s.\-_/]+", "", str(valeur or "")).lower()


def _chiffres(valeur: str) -> str:
    return re.sub(r"\D", "", str(valeur or ""))


def comptes_pour_identifiant(identifiant: str):
    """Les comptes que cette saisie peut designer, du plus sur au moins sur.

    Renvoie une liste: l'appelant refuse lui-meme quand elle en contient
    plusieurs. Deviner entre deux comptes ouvrirait celui qu'on n'a pas
    demande -- et un mot de passe juste sur le mauvais compte est pire
    qu'un refus.
    """
    saisie = str(identifiant or "").strip()
    if not saisie:
        return []

    # 1. L'identifiant du compte, tel quel puis a la casse pres. Il passe
    #    avant tout le reste: un compte ne doit jamais se faire prendre son
    #    nom par le matricule d'un autre.
    exact = list(User.objects.filter(username=saisie)[:2])
    if exact:
        return exact

    insensible = list(User.objects.filter(username__iexact=saisie)[:2])
    if insensible:
        return insensible

    # 2. Le matricule de l'eleve. Deux egalites exactes plutot qu'un
    #    `icontains`: le matricule est unique et indexe, et cette route est
    #    la seule qu'un visiteur anonyme peut marteler -- un balayage de
    #    table a chaque tentative ratee en ferait un levier de deni de
    #    service. La forme generee ne porte aucun separateur, la saisie
    #    normalisee suffit donc a couvrir « IO1-EM1-25E0028M ».
    from apps.school.models import Student

    normalisee = _normaliser(saisie)
    if normalisee:
        eleves = list(
            Student.objects.select_related("user")
            .filter(Q(matricule__iexact=saisie) | Q(matricule__iexact=normalisee))
            .exclude(user__isnull=True)[:2]
        )
        if eleves:
            return [eleve.user for eleve in eleves]

    # 3. Le numero du parent -- ou de l'eleve majeur qui a donne le sien.
    #
    # La comparaison porte sur les derniers chiffres: un meme numero est
    # note « 76 12 34 56 », « +223 76 12 34 56 » ou « 0022376123456 » selon
    # qui l'a saisi.
    #
    # `parent_profile.whatsapp_phone` d'abord, parce que c'est le seul des
    # deux champs qui n'admette qu'une forme -- E.164, compose par un
    # programme. `User.phone` est un champ de repertoire rempli a la main,
    # ou « 76 12 34 56 » et « 76123456 » coexistent: le comparer chiffre a
    # chiffre demanderait de relire toute la table a chaque tentative
    # ratee, sur la seule route qu'un anonyme peut marteler. Un signal le
    # recopie de toute facon dans le champ normalise des qu'il est lisible
    # (voir `_propager_le_telephone_au_numero_whatsapp`).
    chiffres = _chiffres(saisie)
    if len(chiffres) >= CHIFFRES_MINIMUM:
        fin = chiffres[-8:]
        par_numero = list(
            User.objects.filter(
                Q(parent_profile__whatsapp_phone__contains=fin)
                | Q(phone__contains=fin)
            ).distinct()[:2]
        )
        if par_numero:
            return par_numero

    return []


class IdentifiantsDeLEcole(ModelBackend):
    """`ModelBackend`, mais l'identifiant peut etre un matricule ou un numero.

    Tout le reste -- verification du mot de passe, compte desactive,
    permissions -- reste celui de Django: on ne se substitue qu'a la
    facon de retrouver le compte.
    """

    def authenticate(self, request, username=None, password=None, **kwargs):
        if username is None:
            username = kwargs.get(User.USERNAME_FIELD)

        comptes = comptes_pour_identifiant(username) if username else []

        if len(comptes) != 1:
            # Le meme temps de calcul que pour un compte trouve: sans cela,
            # la duree de la reponse dirait a un visiteur si un identifiant
            # existe. C'est la precaution que prend `ModelBackend`, et la
            # deleguer a super() ne marcherait pas -- il ne trouverait rien
            # a comparer non plus, mais seulement apres sa propre requete.
            User().set_password(password)
            return None

        compte = comptes[0]
        if not compte.check_password(password) or not self.user_can_authenticate(
            compte
        ):
            return None
        return compte
