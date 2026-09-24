"""Admettre un eleve: son compte, sa fiche, et sa famille, d'un seul bloc.

Nomme `admission` et non `inscription`: ce dernier module porte deja une
autre question, celle du reglement des frais d'inscription.

L'ecran faisait deux appels -- creer le compte, puis la fiche -- et rattrapait
l'echec du second en supprimant le premier. Un rattrapage qui echoue laisse un
compte orphelin, et avec la famille on serait passe a quatre appels, donc
quatre occasions d'en laisser. Tout se fait ici dans une transaction: ou
l'eleve, son parent et leurs deux comptes existent, ou rien n'a ete ecrit.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils import timezone

from apps.school import matricule as service_matricule
from apps.school.models import ClassRoom, Etablissement, ParentProfile, Student
from apps.school.phone_utils import normaliser_numero

User = get_user_model()

# Le mot de passe se lit a voix haute au guichet et se recopie a la main sur
# un cahier: il doit rester assez long pour la regle des huit caracteres sans
# devenir impossible a dicter.
LONGUEUR_MINIMALE = 8
_REMPLISSAGE = "2025"


@dataclass
class Identifiants:
    """Ce qu'on remet a la famille en fin d'inscription."""

    username: str
    mot_de_passe: str


@dataclass
class ResultatInscription:
    eleve: Student
    identifiants_eleve: Identifiants
    parent: ParentProfile
    identifiants_parent: Identifiants | None
    parent_cree: bool


def _sans_accent(valeur: str) -> str:
    decompose = unicodedata.normalize("NFKD", str(valeur or ""))
    return "".join(c for c in decompose if not unicodedata.combining(c))


def modele_de_mot_de_passe(etablissement: Etablissement | None) -> str:
    """Le modele de cette ecole, ou celui de la maison.

    L'ecole ne remplit son champ que si sa regle differe: un groupe n'a pas a
    choisir entre une regle unique et quatre reglages a tenir a jour.
    """
    propre = str(getattr(etablissement, "mot_de_passe_eleve_modele", "") or "").strip()
    if propre:
        return propre

    from apps.common.models import PersonnalisationPlateforme

    reglages = PersonnalisationPlateforme.objects.filter(
        pk=PersonnalisationPlateforme.SINGLETON_PK
    ).first()
    modele = str(getattr(reglages, "mot_de_passe_eleve_modele", "") or "").strip()
    return modele or PersonnalisationPlateforme.MOT_DE_PASSE_ELEVE_DEFAUT


def modele_de_mot_de_passe_parent(etablissement: Etablissement | None) -> str:
    """Le modele du parent: celui de cette ecole, ou celui de la maison.

    Meme mecanique que pour l'eleve, et pour la meme raison: un groupe ne
    remplit sur la fiche de chaque ecole que ce qui differe de la regle
    commune.
    """
    propre = str(getattr(etablissement, "mot_de_passe_parent_modele", "") or "").strip()
    if propre:
        return propre

    from apps.common.models import PersonnalisationPlateforme

    reglages = PersonnalisationPlateforme.objects.filter(
        pk=PersonnalisationPlateforme.SINGLETON_PK
    ).first()
    modele = str(getattr(reglages, "mot_de_passe_parent_modele", "") or "").strip()
    return modele or PersonnalisationPlateforme.MOT_DE_PASSE_PARENT_DEFAUT


def changement_impose() -> bool:
    from apps.common.models import PersonnalisationPlateforme

    reglages = PersonnalisationPlateforme.objects.filter(
        pk=PersonnalisationPlateforme.SINGLETON_PK
    ).first()
    if reglages is None:
        return True
    return bool(reglages.imposer_changement_mot_de_passe)


def composer_le_mot_de_passe(
    modele: str,
    *,
    etablissement: Etablissement | None,
    prenom: str,
    nom: str,
    matricule: str = "",
    telephone: str = "",
) -> str:
    """Applique le modele, puis garantit la longueur minimale.

    Un modele qui ne produirait que « ba » -- un nom court, rien d'autre --
    donnerait un mot de passe refuse par la regle des huit caracteres, et
    l'inscription echouerait au guichet sans que personne comprenne pourquoi.

    Les deux jetons d'identite cohabitent: l'eleve a un matricule, le parent
    un numero, et une ecole peut vouloir la meme phrase pour les deux --
    « {sigle}{annee} ». Celui qui ne s'applique pas reste vide plutot
    qu'absent: un modele qui le nomme produit alors un mot de passe court,
    que le remplissage rattrape, au lieu de faire echouer l'inscription.
    """
    annee = timezone.now().year
    # Le numero sans ses separateurs: il est dicte au guichet puis retape,
    # et « 76 12 34 56 » ne se retape jamais deux fois pareil.
    chiffres = re.sub(r"\D", "", str(telephone or ""))
    valeurs = {
        "matricule": matricule,
        "telephone": chiffres,
        "annee": str(annee),
        "sigle": _sans_accent(getattr(etablissement, "code", "") or "").upper(),
        "nom": _sans_accent(nom).replace(" ", ""),
        "prenom": _sans_accent(prenom).replace(" ", ""),
    }
    # Ce qui identifie cette personne, et sur quoi on retombe si le modele
    # est mal ecrit ou ne produit rien.
    repli = matricule or chiffres or _sans_accent(f"{prenom}{nom}").replace(" ", "")

    try:
        compose = modele.format(**valeurs)
    except (KeyError, IndexError, ValueError):
        # Un modele mal ecrit ne doit pas fermer le guichet: on retombe sur
        # l'identite, et le changement impose fait le reste.
        compose = repli

    compose = compose.strip() or repli or "motdepasse"
    while len(compose) < LONGUEUR_MINIMALE:
        compose = f"{compose}{_REMPLISSAGE}"
    return compose


def _identifiant_libre(base: str, *, longueur_max: int = 150) -> str:
    """`base`, ou `base-2`, `base-3`... si le nom est deja pris."""
    racine = (base or "").strip()[:longueur_max] or "compte"
    if not User.objects.filter(username__iexact=racine).exists():
        return racine

    suffixe = 2
    while True:
        candidat = f"{racine[: longueur_max - len(str(suffixe)) - 1]}-{suffixe}"
        if not User.objects.filter(username__iexact=candidat).exists():
            return candidat
        suffixe += 1


def identifiant_du_parent(telephone: str, nom: str, prenom: str) -> str:
    """Le numero du parent: c'est ce qu'il connait par coeur.

    Sans numero exploitable, on retombe sur son nom. Un parent qui ne peut
    pas retenir son identifiant ne se connectera jamais.
    """
    chiffres = re.sub(r"\D", "", str(telephone or ""))
    if len(chiffres) >= 6:
        return _identifiant_libre(chiffres)

    nom_compose = _sans_accent(f"{prenom}.{nom}").lower()
    nom_compose = re.sub(r"[^a-z0-9.]+", "", nom_compose).strip(".")
    return _identifiant_libre(nom_compose or "parent")


def chercher_les_parents(etablissement_id, *, telephone: str = "", texte: str = ""):
    """Les parents deja enregistres qui pourraient etre celui-ci.

    Le telephone d'abord: c'est le seul critere qui distingue reellement deux
    familles. Trois freres inscrits separement donnaient trois comptes
    parents, et le pere recevait trois acces pour voir ses trois enfants.
    """
    profils = ParentProfile.objects.select_related("user").filter(
        user__is_active=True
    )
    if etablissement_id:
        profils = profils.filter(etablissement_id=etablissement_id)

    numero = str(telephone or "").strip()
    if numero:
        chiffres = re.sub(r"\D", "", numero)
        if len(chiffres) >= 6:
            # Les six derniers chiffres: un meme numero est note « 76 12 34 56 »,
            # « +22376123456 » ou « 00223 76123456 » selon qui l'a saisi.
            fin = chiffres[-6:]
            return profils.filter(
                user__phone__contains=fin
            ) | profils.filter(whatsapp_phone__contains=fin)

    recherche = str(texte or "").strip()
    if recherche:
        return profils.filter(
            user__last_name__icontains=recherche
        ) | profils.filter(user__first_name__icontains=recherche)

    return profils.none()


def _matricule_neuf(eleve_provisoire: Student) -> str:
    """Le matricule, calcule avant que le compte existe.

    Il l'etait dans `Student.save()`, donc apres la creation du compte -- or
    c'est lui qui donne desormais son identifiant a l'eleve. Le service ne
    demande pas une fiche enregistree: il lit la classe, le genre et l'annee.
    """
    return service_matricule.generer(eleve_provisoire)


@transaction.atomic
def inscrire(
    *,
    classroom: ClassRoom,
    etablissement: Etablissement | None,
    prenom: str,
    nom: str,
    genre: str,
    date_naissance=None,
    date_inscription=None,
    email: str = "",
    telephone: str = "",
    photo=None,
    parent_existant: ParentProfile | None = None,
    parent_nouveau: dict | None = None,
    lien_parente: str = "",
) -> ResultatInscription:
    """Cree la famille et l'eleve, ou ne cree rien.

    L'ordre compte: le parent d'abord, parce qu'un eleve sans parent n'est
    plus admis a l'inscription et qu'on ne veut pas d'eleve a moitie inscrit
    si la creation du parent echoue.
    """
    etablissement = etablissement or getattr(classroom, "etablissement", None)
    identifiants_parent = None
    parent_cree = False

    if parent_existant is not None:
        parent = parent_existant
    else:
        donnees = dict(parent_nouveau or {})
        parent_nom = str(donnees.get("last_name") or "").strip()
        parent_prenom = str(donnees.get("first_name") or "").strip()
        parent_tel = str(donnees.get("phone") or "").strip()

        identifiant = identifiant_du_parent(parent_tel, parent_nom, parent_prenom)
        # La regle de l'ecole, et non plus « les chiffres du numero » ecrit
        # en dur ici. Par defaut elle vaut exactement cela -- le parent
        # retient son numero, pas une suite inventee -- et le changement
        # impose a la premiere connexion la rend sans danger.
        mot_de_passe = composer_le_mot_de_passe(
            modele_de_mot_de_passe_parent(etablissement),
            etablissement=etablissement,
            prenom=parent_prenom,
            nom=parent_nom,
            telephone=parent_tel,
        )

        compte_parent = User(
            username=identifiant,
            first_name=parent_prenom,
            last_name=parent_nom,
            email=str(donnees.get("email") or "").strip(),
            phone=parent_tel,
            role="parent",
            etablissement=etablissement,
            doit_changer_mot_de_passe=changement_impose(),
        )
        compte_parent.set_password(mot_de_passe)
        compte_parent.save()

        whatsapp = normaliser_numero(donnees.get("whatsapp_phone") or "") or ""
        consent = bool(donnees.get("whatsapp_consent"))
        parent = ParentProfile.objects.create(
            user=compte_parent,
            etablissement=etablissement,
            whatsapp_phone=whatsapp,
            # Le consentement n'est enregistre que si un numero le porte:
            # coche sans numero, il ne consentirait a rien.
            whatsapp_consent=consent and bool(whatsapp),
        )
        identifiants_parent = Identifiants(identifiant, mot_de_passe)
        parent_cree = True

    # L'eleve. Le matricule d'abord: il devient son identifiant.
    provisoire = Student(
        classroom=classroom,
        etablissement=etablissement,
        gender=genre,
        enrollment_date=date_inscription or timezone.now().date(),
    )

    derniere_erreur = None
    for _ in range(5):
        matricule = _matricule_neuf(provisoire)
        mot_de_passe_eleve = composer_le_mot_de_passe(
            modele_de_mot_de_passe(etablissement),
            matricule=matricule,
            etablissement=etablissement,
            prenom=prenom,
            nom=nom,
        )
        identifiant_eleve = _identifiant_libre(matricule)

        try:
            # Un point de reprise par tentative: deux inscriptions au meme
            # instant tirent le meme numero de sequence, et la seconde doit
            # pouvoir recommencer sans emporter le parent deja cree.
            with transaction.atomic():
                compte_eleve = User(
                    username=identifiant_eleve,
                    first_name=prenom,
                    last_name=nom,
                    email=str(email or "").strip(),
                    phone=str(telephone or "").strip(),
                    role="student",
                    etablissement=etablissement,
                    doit_changer_mot_de_passe=changement_impose(),
                )
                compte_eleve.set_password(mot_de_passe_eleve)
                compte_eleve.save()

                eleve = Student(
                    user=compte_eleve,
                    matricule=matricule,
                    classroom=classroom,
                    etablissement=etablissement,
                    gender=genre,
                    birth_date=date_naissance,
                    enrollment_date=date_inscription or timezone.now().date(),
                    parent=parent,
                    lien_parente=lien_parente or "",
                )
                if photo is not None:
                    eleve.photo = photo
                eleve.save()

            return ResultatInscription(
                eleve=eleve,
                identifiants_eleve=Identifiants(identifiant_eleve, mot_de_passe_eleve),
                parent=parent,
                identifiants_parent=identifiants_parent,
                parent_cree=parent_cree,
            )
        except IntegrityError as exc:
            derniere_erreur = exc
            continue

    raise derniere_erreur or IntegrityError("Inscription impossible.")
