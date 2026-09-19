"""Ce qu'une archive emporte en fichiers, et ou ces fichiers se trouvent.

Ecrit a part de la vue: le parcours des medias sert a deux moments qui ne
doivent pas diverger -- l'estimation affichee avant l'ecriture, et l'ecriture
elle-meme. Deux boucles separees finiraient par ne plus selectionner les
memes fichiers, et la barre de progression mentirait.

Le parcours passe par le stockage que Django utilise, et non par le dossier
`media` du conteneur. C'est le meme code pour un disque local et pour un
stockage objet -- en production, les fichiers vivent chez Supabase.

Ce detail n'en etait pas un: la sauvegarde lisait le disque du conteneur,
qui est vide en production. Une sauvegarde faite la-bas n'emportait donc
aucune photo d'eleve, aucune piece jointe, aucun logo, alors que la case
« inclure les medias » etait cochee. Et une archive faite en local deposait
ses images sur ce disque, ou rien ne va les chercher et que le prochain
deploiement efface.
"""

from __future__ import annotations

from dataclasses import dataclass

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage

# Les documents de la bibliotheque, tels que `library_document_path` les
# range. C'est le fonds d'annales importe: plusieurs giga-octets de PDF
# identiques d'une ecole a l'autre, qui se reconstituent par un
# `manage.py import_bkalan` sans qu'aucune donnee saisie ne soit en jeu.
# Les emporter faisait peser une sauvegarde mille fois le poids de ce
# qu'elle protege vraiment.
DOSSIER_BIBLIOTHEQUE = "library_docs"

# Garde-fou du parcours: un stockage objet rend ses dossiers par requete, et
# une arborescence inattendue ne doit pas faire tourner la sauvegarde
# indefiniment.
PROFONDEUR_MAXIMALE = 12


@dataclass(frozen=True)
class FichierMedia:
    """Un fichier du stockage retenu pour l'archive."""

    # Le nom tel que le stockage le connait: « students/photo.jpg ». C'est
    # lui qui sert a le relire, et a le reposer au meme endroit.
    nom: str

    # Connu quand le stockage le donne sans surcout. Nul sinon: la taille
    # exacte ne vaut pas une requete par fichier vers un stockage distant.
    octets: int | None = None

    @property
    def nom_dans_l_archive(self) -> str:
        return f"media/{self.nom}"


def _stockage(storage=None):
    return storage or default_storage


def est_un_document_de_bibliotheque(nom: str) -> bool:
    """Vrai si le nom tombe sous le dossier de la bibliotheque."""
    return nom == DOSSIER_BIBLIOTHEQUE or nom.startswith(f"{DOSSIER_BIBLIOTHEQUE}/")


def _parcourir(storage, prefixe: str, profondeur: int, *, sauter_bibliotheque: bool):
    """Les noms de fichiers sous ce prefixe, dossier par dossier."""
    if profondeur > PROFONDEUR_MAXIMALE:
        return
    try:
        dossiers, fichiers = storage.listdir(prefixe)
    except (OSError, NotImplementedError):
        # Dossier absent, ou stockage qui ne sait pas lister: on n'invente
        # rien, et la sauvegarde des donnees continue sans les medias.
        return

    for nom in fichiers:
        if not nom:
            continue
        yield f"{prefixe}/{nom}" if prefixe else nom

    for dossier in dossiers:
        if not dossier:
            continue
        chemin = f"{prefixe}/{dossier}" if prefixe else dossier
        if sauter_bibliotheque and est_un_document_de_bibliotheque(chemin):
            continue
        yield from _parcourir(
            storage, chemin, profondeur + 1, sauter_bibliotheque=sauter_bibliotheque
        )


def fichiers_a_archiver(storage=None, *, avec_bibliotheque: bool) -> list[FichierMedia]:
    """Les fichiers que l'archive doit emporter, tries.

    Le tri rend l'archive reproductible: deux sauvegardes du meme etat
    donnent le meme ordre d'entrees, ce qui aide a les comparer.

    La taille n'est pas relevee ici: sur un stockage objet, ce serait une
    requete par fichier. Elle est connue au moment ou le fichier est copie.
    """
    storage = _stockage(storage)

    noms = _parcourir(storage, "", 0, sauter_bibliotheque=not avec_bibliotheque)
    return [FichierMedia(nom=nom) for nom in sorted(set(noms))]


def poids_total(fichiers) -> int:
    """La somme des tailles connues. Zero quand le stockage ne les donne pas."""
    return sum(fichier.octets or 0 for fichier in fichiers)


def mesurer(fichiers, storage=None, *, plafond: int = 2000) -> list[FichierMedia]:
    """Releve la taille de chaque fichier, dans la limite du plafond.

    Le plafond protege du stockage distant: une requete par fichier reste
    supportable sur quelques centaines de medias, pas sur les dizaines de
    milliers de la bibliotheque. Au-dela, les tailles restent inconnues et
    l'ecran suit l'avancement au nombre de fichiers.
    """
    storage = _stockage(storage)
    if len(fichiers) > plafond:
        return list(fichiers)

    mesures = []
    for fichier in fichiers:
        try:
            mesures.append(FichierMedia(nom=fichier.nom, octets=storage.size(fichier.nom)))
        except (OSError, NotImplementedError):
            mesures.append(fichier)
    return mesures


def volume_de_la_bibliotheque(storage=None, *, plafond: int = 2000) -> int:
    """Ce que la bibliotheque pese, pour le dire avant d'archiver.

    Rend zero quand elle compte trop de fichiers pour etre mesuree sans
    peser plus lourd que la sauvegarde elle-meme.
    """
    storage = _stockage(storage)
    fichiers = [
        FichierMedia(nom=nom)
        for nom in _parcourir(storage, DOSSIER_BIBLIOTHEQUE, 1, sauter_bibliotheque=False)
    ]
    return poids_total(mesurer(fichiers, storage, plafond=plafond))


def lire(fichier: FichierMedia, storage=None):
    """Ouvre le fichier dans le stockage, pour le copier dans l'archive."""
    return _stockage(storage).open(fichier.nom, "rb")


def reposer(nom: str, contenu: bytes, storage=None) -> None:
    """Repose un fichier a son nom d'origine, en ecrasant ce qui s'y trouve.

    L'effacement precede l'ecriture: un stockage objet configure pour ne pas
    ecraser renommerait le fichier (« logo_a1b2c3.png »), et la fiche qui le
    reference pointerait alors dans le vide.
    """
    storage = _stockage(storage)
    try:
        if storage.exists(nom):
            storage.delete(nom)
    except (OSError, NotImplementedError):
        pass
    storage.save(nom, ContentFile(contenu))
