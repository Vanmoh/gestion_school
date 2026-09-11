"""Ce qu'une archive emporte, et ce qu'elle pese.

Ecrit a part de la vue: le parcours des medias sert a deux moments qui ne
doivent pas diverger -- l'estimation affichee avant l'ecriture, et l'ecriture
elle-meme. Deux boucles separees finiraient par ne plus selectionner les
memes fichiers, et la barre de progression mentirait.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

# Les documents de la bibliotheque, tels que `library_document_path` les
# range. C'est le fonds d'annales importe: plusieurs giga-octets de PDF
# identiques d'une ecole a l'autre, qui se reconstituent par un
# `manage.py import_bkalan` sans qu'aucune donnee saisie ne soit en jeu.
# Les emporter faisait peser une sauvegarde mille fois le poids de ce
# qu'elle protege vraiment.
DOSSIER_BIBLIOTHEQUE = "library_docs"


@dataclass(frozen=True)
class FichierMedia:
    """Un fichier du dossier media retenu pour l'archive."""

    chemin: Path
    # Chemin relatif a MEDIA_ROOT: c'est lui qui devient le nom dans le ZIP,
    # et c'est sous ce nom que la restauration le repose au bon endroit.
    relatif: Path
    octets: int

    @property
    def nom_dans_l_archive(self) -> str:
        return str(Path("media") / self.relatif)


def est_un_document_de_bibliotheque(relatif: Path) -> bool:
    """Vrai si le chemin relatif tombe sous le dossier de la bibliotheque."""
    parties = relatif.parts
    return bool(parties) and parties[0] == DOSSIER_BIBLIOTHEQUE


def fichiers_a_archiver(media_root, *, avec_bibliotheque: bool) -> list[FichierMedia]:
    """Les fichiers medias que l'archive doit emporter, tries.

    Le tri rend l'archive reproductible: deux sauvegardes du meme etat
    donnent le meme ordre d'entrees, ce qui aide a les comparer.

    Un fichier efface entre le listage et l'ecriture disparait sans faire
    echouer la sauvegarde: `stat()` echoue ici, on l'ignore.
    """
    racine = Path(media_root)
    if not racine.exists() or not racine.is_dir():
        return []

    retenus: list[FichierMedia] = []
    for item in racine.rglob("*"):
        if not item.is_file():
            continue
        relatif = item.relative_to(racine)
        if not avec_bibliotheque and est_un_document_de_bibliotheque(relatif):
            continue
        try:
            octets = item.stat().st_size
        except OSError:
            continue
        retenus.append(FichierMedia(chemin=item, relatif=relatif, octets=octets))

    retenus.sort(key=lambda fichier: str(fichier.relatif))
    return retenus


def poids_total(fichiers) -> int:
    return sum(fichier.octets for fichier in fichiers)


def volume_de_la_bibliotheque(media_root) -> int:
    """Ce que la bibliotheque pese, pour le dire avant d'archiver."""
    racine = Path(media_root) / DOSSIER_BIBLIOTHEQUE
    if not racine.exists() or not racine.is_dir():
        return 0

    total = 0
    for item in racine.rglob("*"):
        if not item.is_file():
            continue
        try:
            total += item.stat().st_size
        except OSError:
            continue
    return total
