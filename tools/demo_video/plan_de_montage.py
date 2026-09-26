"""Des journaux de prise au plan de montage, sans toucher a ffmpeg.

Ce module ne monte rien: il calcule. Il lit ce que les pilotes ont journalise
pendant le tournage et rend le plan que `monter_la_video.py` executera -- les
sous-titres avec leurs horodatages, les encadres avec leurs coordonnees, les
chapitres avec leurs bornes.

Il est separe de l'execution pour une raison pratique: ffmpeg n'existe pas sur
la machine de developpement, alors que ce calcul-la, lui, s'eprouve par des
tests ordinaires. La partie du montage ou l'on peut se tromper sans le voir est
donc la partie testable.

Deux conventions qui traversent tout le fichier:

- **Le temps du journal est absolu**, en millisecondes depuis l'epoque. Celui de
  la video part de zero. La conversion retranche `t0`, l'instant ou la capture a
  commence a ecrire des images -- et non l'instant ou ffmpeg a ete appele, qui
  precede de cent a trois cents millisecondes.
- **Les coordonnees viennent de Flutter**, via `tester.getRect`. On leur ajoute
  le decalage vertical mesure sur la fenetre, jamais un decalage suppose.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

# La geometrie de la video. Elle suit la fenetre que l'embedder GTK ouvre.
LARGEUR = 1280
HAUTEUR = 720
IMAGES_PAR_SECONDE = 25

# Les neuf chapitres, dans l'ordre de la video.
#
# Recopies du cote Dart (`chapitresDeLaDemonstration`) parce que le montage doit
# connaitre l'ordre et les titres **sans executer les pilotes**: un chapitre
# manquant devient alors un carton qui le dit, au lieu d'un trou silencieux.
CHAPITRES = (
    (1, "super_admin", "SUPER ADMIN", "Il installe l'école et garde les clés."),
    (2, "promoter", "PROMOTEUR", "Le propriétaire voit tout et ne touche à rien."),
    (
        3,
        "director",
        "DIRECTEUR",
        "Il ouvre l'année, compose les emplois du temps et publie.",
    ),
    (4, "censor", "CENSEUR", "Il arbitre la pédagogie et vise la paie en premier."),
    (5, "accountant", "COMPTABLE", "Il encaisse, justifie, et vise la paie en second."),
    (
        6,
        "supervisor",
        "SURVEILLANT",
        "Il fait l'appel, note la conduite et tient les épreuves.",
    ),
    (7, "teacher", "ENSEIGNANT", "Il corrige et saisit — publier n'est pas son geste."),
    (8, "parent", "PARENT", "Il suit son enfant, et rien que son enfant."),
    (
        9,
        "student",
        "ÉLÈVE",
        "Il lit ses notes, son emploi du temps et son fil de classe.",
    ),
)

FILIGRANE = "DONNÉES FICTIVES — DÉMONSTRATION"


@dataclass
class Annotation:
    """Un sous-titre ou un encadre, ramene au temps de la video."""

    genre: str
    debut: float
    fin: float
    texte: str = ""
    cadre: tuple[float, float, float, float] | None = None

    @property
    def duree(self) -> float:
        return max(0.0, self.fin - self.debut)


@dataclass
class ChapitrePlanifie:
    """Un chapitre, avec son rush s'il existe et ses annotations."""

    rang: int
    role: str
    titre: str
    mission: str
    rush: Path | None = None
    duree: float = 0.0
    annotations: list[Annotation] = field(default_factory=list)
    manquant: bool = False
    motif: str = ""

    @property
    def sous_titres(self) -> list[Annotation]:
        return [a for a in self.annotations if a.genre == "sousTitre"]

    @property
    def cadres(self) -> list[Annotation]:
        return [a for a in self.annotations if a.genre == "cadre" and a.cadre]


def lire_le_journal(contenu: str) -> list[dict]:
    """Relit un journal de prise, ligne par ligne.

    Les lignes illisibles sont ignorees: une prise interrompue en pleine
    ecriture laisse une ligne tronquee, et ce qui precede reste exploitable.
    """
    evenements = []
    for ligne in contenu.splitlines():
        propre = ligne.strip()
        if not propre:
            continue
        try:
            decode = json.loads(propre)
        except json.JSONDecodeError:
            continue
        if isinstance(decode, dict) and "type" in decode:
            evenements.append(decode)
    return evenements


def prise_complete(evenements: list[dict]) -> bool:
    """Vrai si la prise s'est terminee normalement.

    Un journal sans `fin` decrit une prise coupee. Le montage prefere alors un
    carton honnete a un chapitre tronque: le spectateur sait qu'il manque
    quelque chose, au lieu de croire que le logiciel s'arrete la.
    """
    if not evenements:
        return False
    return (
        any(e.get("type") == "chapitre" for e in evenements)
        and evenements[-1].get("type") == "fin"
    )


def convertir_en_annotations(
    evenements: list[dict],
    t0_ms: int,
    decalage_vertical: float,
    duree_du_rush: float,
) -> list[Annotation]:
    """Ramene les evenements au temps de la video et borne leurs durees.

    Une annotation dont le debut tombe apres la fin du rush est ecartee: elle
    decrirait un moment que la capture n'a pas enregistre.
    """
    annotations: list[Annotation] = []
    for evenement in evenements:
        genre = evenement.get("type")
        if genre not in {"sousTitre", "cadre"}:
            continue

        debut = (evenement.get("epoch_ms", 0) - t0_ms) / 1000.0
        if debut < 0:
            # Un evenement journalise avant la premiere image: on le colle au
            # debut plutot que de le perdre.
            debut = 0.0
        if duree_du_rush and debut >= duree_du_rush:
            continue

        duree = max(0.5, evenement.get("duree_ms", 4000) / 1000.0)
        fin = debut + duree
        if duree_du_rush:
            fin = min(fin, duree_du_rush)

        cadre = None
        brut = evenement.get("cadre")
        if isinstance(brut, list) and len(brut) == 4:
            x, y, largeur, hauteur = (float(v) for v in brut)
            cadre = _borner_le_cadre(x, y + decalage_vertical, largeur, hauteur)

        annotations.append(
            Annotation(
                genre=genre,
                debut=debut,
                fin=fin,
                texte=str(evenement.get("texte", "")),
                cadre=cadre,
            )
        )
    return annotations


def _borner_le_cadre(
    x: float, y: float, largeur: float, hauteur: float
) -> tuple[float, float, float, float] | None:
    """Ramene un rectangle dans l'image, ou l'ecarte s'il n'y est pas.

    Un widget partiellement hors champ existe: une liste qui depasse le bas de
    l'ecran, par exemple. `drawbox` accepte des coordonnees hors cadre, mais le
    resultat est un trait colle au bord qui ne designe rien.
    """
    x = max(0.0, x)
    y = max(0.0, y)
    largeur = min(largeur, LARGEUR - x)
    hauteur = min(hauteur, HAUTEUR - y)
    if largeur <= 2 or hauteur <= 2:
        return None
    return (round(x), round(y), round(largeur), round(hauteur))


def lire_le_decalage(contenu_geometrie: str) -> float:
    """Le decalage vertical mesure sur la fenetre, ou zero.

    La barre de titre GTK n'a pas de hauteur garantie: elle depend du theme du
    systeme. Le script d'enregistrement la mesure et l'ecrit; ici on la relit.
    """
    for ligne in contenu_geometrie.splitlines():
        if ligne.startswith("decalage_vertical="):
            try:
                return float(ligne.split("=", 1)[1].strip())
            except ValueError:
                return 0.0
    return 0.0


def horodatage_srt(secondes: float) -> str:
    """Un instant au format que libass attend: HH:MM:SS,mmm."""
    secondes = max(0.0, secondes)
    heures = int(secondes // 3600)
    minutes = int((secondes % 3600) // 60)
    reste = secondes % 60
    entier = int(reste)
    millisecondes = int(round((reste - entier) * 1000))
    if millisecondes == 1000:
        entier += 1
        millisecondes = 0
    return f"{heures:02d}:{minutes:02d}:{entier:02d},{millisecondes:03d}"


def ecrire_le_srt(annotations: list[Annotation]) -> str:
    """Les sous-titres d'un chapitre, en SRT.

    Un vrai fichier de sous-titres plutot que du texte incruste par `drawtext`:
    les accents et les apostrophes francaises demandent un triple echappement
    dans un filtre ffmpeg, et le resultat reste indexable et desactivable.
    """
    lignes = []
    for rang, annotation in enumerate(
        [a for a in annotations if a.genre == "sousTitre" and a.texte.strip()],
        start=1,
    ):
        lignes.append(str(rang))
        lignes.append(
            f"{horodatage_srt(annotation.debut)} --> {horodatage_srt(annotation.fin)}"
        )
        lignes.append(annotation.texte.strip())
        lignes.append("")
    return "\n".join(lignes)


def filtre_des_cadres(annotations: list[Annotation]) -> str:
    """Les encadres, en filtres `drawbox`.

    Deux passes par encadre: un contour net, puis un voile leger a l'interieur.
    C'est l'effet le plus fiable de tout l'habillage -- aucune interpolation,
    aucune perte, et il se recalcule tout seul si la mise en page change.
    """
    morceaux = []
    for annotation in annotations:
        if annotation.genre != "cadre" or not annotation.cadre:
            continue
        x, y, largeur, hauteur = annotation.cadre
        fenetre = f"between(t,{annotation.debut:.2f},{annotation.fin:.2f})"
        morceaux.append(
            f"drawbox=x={x}:y={y}:w={largeur}:h={hauteur}"
            f":color=0x22D3EE@0.95:t=3:enable='{fenetre}'"
        )
        morceaux.append(
            f"drawbox=x={x}:y={y}:w={largeur}:h={hauteur}"
            f":color=0x22D3EE@0.18:t=fill:enable='{fenetre}'"
        )
    return ",".join(morceaux)


def planifier(dossier: Path) -> list[ChapitrePlanifie]:
    """Le plan complet, un chapitre par role, rushes presents ou non."""
    plan: list[ChapitrePlanifie] = []

    for rang, role, titre, mission in CHAPITRES:
        chapitre = ChapitrePlanifie(rang=rang, role=role, titre=titre, mission=mission)
        rush = dossier / f"brut_{rang}.mkv"
        journal = dossier / f"journal_{rang}.jsonl"

        if not rush.exists() or rush.stat().st_size == 0:
            chapitre.manquant = True
            chapitre.motif = "aucune image capturée"
            plan.append(chapitre)
            continue

        chapitre.rush = rush
        evenements = lire_le_journal(
            journal.read_text(encoding="utf-8") if journal.exists() else ""
        )
        if not prise_complete(evenements):
            chapitre.motif = "prise interrompue"

        decalage = lire_le_decalage(
            (dossier / f"geometrie_{rang}.txt").read_text(encoding="utf-8")
            if (dossier / f"geometrie_{rang}.txt").exists()
            else ""
        )
        t0 = _lire_t0(dossier / f"t0_{rang}.txt")
        chapitre.duree = _lire_la_duree(dossier / f"duree_{rang}.txt")
        chapitre.annotations = convertir_en_annotations(
            evenements, t0, decalage, chapitre.duree
        )
        plan.append(chapitre)

    return plan


def _lire_t0(chemin: Path) -> int:
    if not chemin.exists():
        return 0
    try:
        return int(chemin.read_text(encoding="utf-8").strip())
    except ValueError:
        return 0


def _lire_la_duree(chemin: Path) -> float:
    """La duree du rush, mesuree par ffprobe a l'enregistrement.

    Zero quand on ne la connait pas: les annotations ne sont alors pas bornees,
    ce qui est moins grave que de les ecarter toutes.
    """
    if not chemin.exists():
        return 0.0
    try:
        return float(chemin.read_text(encoding="utf-8").strip())
    except ValueError:
        return 0.0


def metadonnees_de_chapitres(bornes: list[tuple[str, float, float]]) -> str:
    """Les chapitres au format que ffmpeg incruste dans le conteneur.

    VLC, QuickTime et YouTube les lisent: on peut sauter directement au role
    qu'on veut voir, ce qui change tout sur une video de neuf minutes.
    """
    lignes = [";FFMETADATA1"]
    for titre, debut, fin in bornes:
        lignes.append("[CHAPTER]")
        lignes.append("TIMEBASE=1/1000")
        lignes.append(f"START={int(debut * 1000)}")
        lignes.append(f"END={int(fin * 1000)}")
        lignes.append(f"title={titre}")
    return "\n".join(lignes) + "\n"


def corps_de_release(bornes: list[tuple[str, float, float]], poids_mo: float) -> str:
    """Le texte de la Release, avec les minutages en clair.

    Les chapitres du conteneur ne se voient pas quand on telecharge le fichier:
    on les repete donc en texte.
    """
    lignes = [
        "Démonstration de **Gestion School**, les neuf rôles de l'école.",
        "",
        "Chaque chapitre montre ce qu'un rôle fait et que les autres ne font pas :",
        "le directeur génère l'emploi du temps, le censeur et le comptable visent",
        "la paie l'un après l'autre, l'enseignant corrige sans pouvoir publier,",
        "la famille ne voit que son enfant.",
        "",
        "## Chapitres",
        "",
    ]
    for titre, debut, _ in bornes:
        minutes = int(debut // 60)
        secondes = int(debut % 60)
        lignes.append(f"- `{minutes:02d}:{secondes:02d}` {titre}")

    lignes += [
        "",
        "## À savoir",
        "",
        "- Toutes les données sont **fictives** : noms, matricules, notes et",
        "  montants sortent des commandes de peuplement du dépôt. Aucune donnée",
        "  d'élève réel n'est filmée, et un garde-fou refuse le tournage si la",
        "  base n'est pas un décor.",
        "- Aucune voix, aucune musique : les explications sont en sous-titres,",
        "  désactivables.",
        f"- Poids du fichier : environ {poids_mo:.0f} Mo.",
        "",
    ]
    return "\n".join(lignes)
