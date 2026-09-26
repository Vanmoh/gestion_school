#!/usr/bin/env python3
"""Assemble les rushes en une video chapitree, sous-titree et annotee.

Ce script execute le plan que `plan_de_montage` calcule. La separation n'est pas
cosmetique: le calcul s'eprouve par des tests sur n'importe quelle machine, alors
que cette partie-ci demande ffmpeg et Pillow. Ce qui peut se tromper en silence
-- un horodatage, un rectangle, un chapitre manquant -- est du cote teste.

Ce qu'il fabrique, dans l'ordre:

1. un carton de titre par chapitre, compose par Pillow;
2. chaque rush recadre, badge, encadre et sous-titre;
3un carton de cloture;
4. le tout concatene en un seul MP4, avec ses chapitres et son fichier de
   sous-titres;
5. le corps de la Release, qui repete les minutages en clair.

Pillow plutot que le filtre `drawtext` pour les cartons: les apostrophes et les
accents francais demandent un triple echappement dans un filtergraph, et la
typographie precise -- interlettrage, retours a la ligne, logo -- n'est pas dans
ses cordes.

Un chapitre dont la prise manque devient un carton qui le dit. Perdre huit
chapitres parce que le neuvieme a echoue couterait plus cher que l'avouer.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import plan_de_montage as pm  # noqa: E402

RACINE = Path(__file__).resolve().parents[2]
POLICES = RACINE / "frontend/gestion_school_app/assets/fonts"
LOGO = RACINE / "frontend/gestion_school_app/assets/images/logo_ecole.png"

# Le theme sombre de l'application, pour que les cartons ne jurent pas avec les
# captures qu'ils annoncent.
FOND = (15, 23, 42)
FOND_BAS = (30, 41, 59)
ACCENT = (34, 211, 238)
TEXTE = (241, 245, 249)
TEXTE_DOUX = (148, 163, 184)

PROFILS = {
    "lisible": {"crf": "20", "echelle": None, "fps": pm.IMAGES_PAR_SECONDE},
    "equilibre": {"crf": "23", "echelle": None, "fps": pm.IMAGES_PAR_SECONDE},
    "leger": {"crf": "26", "echelle": "1024:576", "fps": 20},
}


def executer(commande: list[str], *, muet: bool = True) -> None:
    """Lance une commande et s'arrete net si elle echoue."""
    resultat = subprocess.run(
        commande,
        capture_output=muet,
        text=True,
    )
    if resultat.returncode != 0:
        if muet and resultat.stderr:
            print(resultat.stderr[-3000:], file=sys.stderr)
        raise SystemExit(f"Echec: {' '.join(commande[:6])}…")


def duree_du_media(chemin: Path) -> float:
    """La duree reelle d'un fichier, lue par ffprobe.

    Mesuree et non deduite du nombre d'images: la capture ne tient pas toujours
    la cadence demandee, et une duree supposee decalerait tout l'habillage.
    """
    sortie = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(chemin),
        ],
        capture_output=True,
        text=True,
    )
    if sortie.returncode != 0:
        return 0.0
    try:
        return float(json.loads(sortie.stdout)["format"]["duration"])
    except (KeyError, ValueError, json.JSONDecodeError):
        return 0.0


# ------------------------------------------------------------------- cartons


def _police(nom: str, taille: int):
    from PIL import ImageFont

    chemin = POLICES / nom
    if chemin.exists():
        return ImageFont.truetype(str(chemin), taille)
    # Sans les polices du depot, on ne renonce pas au carton: on le compose avec
    # la police par defaut, moins belle mais lisible.
    return ImageFont.load_default()


def composer_un_carton(
    destination: Path,
    *,
    surtitre: str,
    titre: str,
    mission: str,
    note: str = "",
) -> None:
    from PIL import Image, ImageDraw

    image = Image.new("RGB", (pm.LARGEUR, pm.HAUTEUR), FOND)
    dessin = ImageDraw.Draw(image)

    # Un degrade discret plutot qu'un aplat: un aplat parfait trahit une image
    # de synthese au milieu de captures reelles.
    for y in range(pm.HAUTEUR):
        part = y / pm.HAUTEUR
        couleur = tuple(
            int(FOND[i] + (FOND_BAS[i] - FOND[i]) * part) for i in range(3)
        )
        dessin.line([(0, y), (pm.LARGEUR, y)], fill=couleur)

    if LOGO.exists():
        try:
            logo = Image.open(LOGO).convert("RGB")
            logo.thumbnail((240, 240))
            # On fond le logo dans l'arriere-plan plutot que de le coller: le
            # fichier du depot n'a pas de transparence, si bien qu'un collage --
            # meme attenue par un masque -- dessinait un rectangle clair autour
            # de l'embleme.
            position = (
                pm.LARGEUR - logo.width - 60,
                pm.HAUTEUR - logo.height - 50,
            )
            region = image.crop(
                (
                    position[0],
                    position[1],
                    position[0] + logo.width,
                    position[1] + logo.height,
                )
            )
            image.paste(Image.blend(region, logo, 0.14), position)
        except OSError:
            pass

    dessin.line([(90, 250), (90 + 140, 250)], fill=ACCENT, width=5)
    dessin.text((90, 190), surtitre, font=_police("Inter-SemiBold.ttf", 26), fill=ACCENT)
    dessin.text((90, 285), titre, font=_police("Sora-Bold.ttf", 78), fill=TEXTE)
    dessin.text(
        (90, 400), mission, font=_police("Inter-Regular.ttf", 30), fill=TEXTE_DOUX
    )
    if note:
        dessin.text(
            (90, 460), note, font=_police("Inter-Regular.ttf", 24), fill=(248, 113, 113)
        )
    dessin.text(
        (90, pm.HAUTEUR - 70),
        pm.FILIGRANE,
        font=_police("Inter-Medium.ttf", 20),
        fill=TEXTE_DOUX,
    )

    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination)


def encoder_un_carton(
    png: Path, sortie: Path, duree: float, fps: int, crf: str
) -> None:
    executer(
        [
            "ffmpeg",
            "-nostdin",
            "-loglevel",
            "error",
            "-y",
            "-loop",
            "1",
            "-i",
            str(png),
            "-t",
            f"{duree}",
            "-r",
            str(fps),
            "-vf",
            f"fade=t=in:st=0:d=0.4,fade=t=out:st={max(0.1, duree - 0.4)}:d=0.4,"
            "format=yuv420p",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            crf,
            str(sortie),
        ]
    )


# -------------------------------------------------------------- les chapitres


def habiller_un_chapitre(
    chapitre: pm.ChapitrePlanifie,
    dossier: Path,
    profil: dict,
    decalage: float,
) -> Path:
    """Recadre le rush, y pose le badge, les encadres et les sous-titres."""
    sortie = dossier / f"chapitre_{chapitre.rang}.mkv"
    badge = dossier / f"badge_{chapitre.rang}.txt"
    filigrane = dossier / "filigrane.txt"
    srt = dossier / f"soustitres_{chapitre.rang}.srt"

    badge.write_text(f"{chapitre.rang}/9 · {chapitre.titre}", encoding="utf-8")
    filigrane.write_text(pm.FILIGRANE, encoding="utf-8")
    srt.write_text(pm.ecrire_le_srt(chapitre.annotations), encoding="utf-8")

    hauteur_vue = int(pm.HAUTEUR - decalage)
    filtres = [
        f"crop={pm.LARGEUR}:{hauteur_vue}:0:{int(decalage)}",
        f"pad={pm.LARGEUR}:{pm.HAUTEUR}:0:{int(decalage / 2)}:black",
    ]

    cadres = pm.filtre_des_cadres(chapitre.annotations)
    if cadres:
        filtres.append(cadres)

    # `textfile=` et jamais le texte en ligne de commande: c'est ce qui evite
    # d'echapper trois fois les apostrophes et les deux-points.
    filtres.append(
        f"drawtext=fontfile={_chemin_police('Inter-SemiBold.ttf')}"
        f":textfile={badge}:x=28:y=28:fontsize=22:fontcolor=white@0.92"
        ":box=1:boxcolor=0x0F172A@0.72:boxborderw=14"
    )
    filtres.append(
        f"drawtext=fontfile={_chemin_police('Inter-Medium.ttf')}"
        f":textfile={filigrane}:x=w-tw-24:y=h-th-20:fontsize=16"
        ":fontcolor=white@0.55"
    )

    if srt.read_text(encoding="utf-8").strip():
        filtres.append(
            f"subtitles={_echapper(srt)}:fontsdir={_echapper(POLICES)}"
            ":force_style='FontName=Inter,FontSize=20,PrimaryColour=&H00FFFFFF,"
            "BackColour=&HA0000000,BorderStyle=4,Outline=0,Shadow=0,MarginV=44,"
            "Alignment=2'"
        )

    if profil["echelle"]:
        filtres.append(f"scale={profil['echelle']}:flags=lanczos")

    executer(
        [
            "ffmpeg",
            "-nostdin",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(chapitre.rush),
            "-vf",
            ",".join(filtres),
            "-r",
            str(profil["fps"]),
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-crf",
            profil["crf"],
            "-pix_fmt",
            "yuv420p",
            str(sortie),
        ]
    )
    return sortie


def _chemin_police(nom: str) -> str:
    chemin = POLICES / nom
    return _echapper(chemin if chemin.exists() else POLICES / "Inter-Regular.ttf")


def _echapper(chemin: Path | str) -> str:
    """Un chemin tel qu'un filtergraph ffmpeg l'accepte."""
    return str(chemin).replace("\\", "/").replace(":", r"\:").replace(",", r"\,")


# ----------------------------------------------------------------- assemblage


def monter(dossier: Path, profil_nom: str) -> Path:
    profil = PROFILS[profil_nom]
    plan = pm.planifier(dossier)

    # La duree de chaque rush, mesuree avant tout calcul: le plan en a besoin
    # pour borner les annotations.
    for chapitre in plan:
        if chapitre.rush:
            duree = duree_du_media(chapitre.rush)
            (dossier / f"duree_{chapitre.rang}.txt").write_text(
                f"{duree}", encoding="utf-8"
            )
    plan = pm.planifier(dossier)

    presents = [c for c in plan if not c.manquant]
    if not presents:
        raise SystemExit(
            "Aucun rush exploitable: rien a monter. Voir les journaux de prise."
        )

    morceaux: list[Path] = []
    bornes: list[tuple[str, float, float]] = []
    instant = 0.0

    ouverture_png = dossier / "carton_ouverture.png"
    composer_un_carton(
        ouverture_png,
        surtitre="GESTION SCHOOL",
        titre="NEUF RÔLES",
        mission="Une école, neuf métiers, neuf écrans différents.",
    )
    ouverture = dossier / "carton_ouverture.mkv"
    encoder_un_carton(ouverture_png, ouverture, 4.0, profil["fps"], profil["crf"])
    morceaux.append(ouverture)
    instant += 4.0

    for chapitre in plan:
        png = dossier / f"carton_{chapitre.rang}.png"
        composer_un_carton(
            png,
            surtitre=f"CHAPITRE {chapitre.rang} SUR 9",
            titre=chapitre.titre,
            mission=chapitre.mission,
            note="Chapitre indisponible : " + chapitre.motif
            if chapitre.manquant
            else "",
        )
        carton = dossier / f"carton_{chapitre.rang}.mkv"
        encoder_un_carton(png, carton, 3.0, profil["fps"], profil["crf"])
        morceaux.append(carton)

        debut = instant
        instant += 3.0

        if not chapitre.manquant:
            decalage = pm.lire_le_decalage(
                (dossier / f"geometrie_{chapitre.rang}.txt").read_text(
                    encoding="utf-8"
                )
                if (dossier / f"geometrie_{chapitre.rang}.txt").exists()
                else ""
            )
            habille = habiller_un_chapitre(chapitre, dossier, profil, decalage)
            morceaux.append(habille)
            instant += duree_du_media(habille)

        bornes.append((f"{chapitre.rang}. {chapitre.titre}", debut, instant))

    cloture_png = dossier / "carton_cloture.png"
    composer_un_carton(
        cloture_png,
        surtitre="FIN",
        titre="MERCI",
        mission="github.com/Vanmoh/gestion_school",
    )
    cloture = dossier / "carton_cloture.mkv"
    encoder_un_carton(cloture_png, cloture, 4.0, profil["fps"], profil["crf"])
    morceaux.append(cloture)
    instant += 4.0

    liste = dossier / "liste.txt"
    liste.write_text(
        "\n".join(f"file '{m.resolve()}'" for m in morceaux) + "\n", encoding="utf-8"
    )

    metadonnees = dossier / "chapitres.txt"
    metadonnees.write_text(pm.metadonnees_de_chapitres(bornes), encoding="utf-8")

    final = dossier / "demo_gestion_school.mp4"

    # Un seul reencodage final, et pas de `-c copy`: les segments passes par
    # crop, drawbox et subtitles n'ont pas les memes en-tetes que les cartons.
    #
    # La piste audio silencieuse est du pragmatisme: plusieurs plateformes
    # refusent ou recompressent mal un MP4 sans piste audio, et trente-deux
    # kilobits de silence coutent deux megaoctets sur neuf minutes.
    executer(
        [
            "ffmpeg",
            "-nostdin",
            "-loglevel",
            "error",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(liste),
            "-f",
            "lavfi",
            "-i",
            "anullsrc=r=48000:cl=stereo",
            "-i",
            str(metadonnees),
            "-map",
            "0:v",
            "-map",
            "1:a",
            "-map_metadata",
            "2",
            "-c:v",
            "libx264",
            "-preset",
            "slow",
            "-crf",
            profil["crf"],
            "-pix_fmt",
            "yuv420p",
            "-profile:v",
            "high",
            "-level",
            "4.0",
            "-g",
            "50",
            "-movflags",
            "+faststart",
            "-c:a",
            "aac",
            "-b:a",
            "32k",
            "-shortest",
            str(final),
        ]
    )

    poids_mo = final.stat().st_size / (1024 * 1024)
    (dossier / "corps_de_release.md").write_text(
        pm.corps_de_release(bornes, poids_mo), encoding="utf-8"
    )

    duree_finale = duree_du_media(final)
    print(f"Video montee: {final}")
    print(f"  duree   : {int(duree_finale // 60)} min {int(duree_finale % 60)} s")
    print(f"  poids   : {poids_mo:.1f} Mo")
    print(f"  chapitres: {len(bornes)}")
    manquants = [c.rang for c in plan if c.manquant]
    if manquants:
        print(f"  chapitres remplaces par un carton: {manquants}")

    # Deux controles qui font echouer le montage plutot que de publier une
    # video dont personne ne regarderait la duree.
    if poids_mo > 150:
        raise SystemExit(f"Fichier trop lourd: {poids_mo:.0f} Mo. Essayez --profil leger.")
    if duree_finale < 60:
        raise SystemExit(
            f"Video de {int(duree_finale)} s: trop courte pour neuf roles. "
            "Les prises ont probablement echoue."
        )
    return final


def main() -> None:
    analyseur = argparse.ArgumentParser(description=__doc__)
    analyseur.add_argument(
        "--sortie",
        type=Path,
        default=Path(__file__).resolve().parent / "sortie",
        help="Dossier des rushes, qui recevra la video montee.",
    )
    analyseur.add_argument(
        "--profil",
        choices=sorted(PROFILS),
        default="equilibre",
        help="lisible (texte net), equilibre (defaut), leger (partage).",
    )
    analyseur.add_argument(
        "--cartons-seulement",
        action="store_true",
        help="Ne composer que les cartons PNG, sans ffmpeg. Utile hors CI.",
    )
    options = analyseur.parse_args()

    if options.cartons_seulement:
        options.sortie.mkdir(parents=True, exist_ok=True)
        composer_un_carton(
            options.sortie / "carton_ouverture.png",
            surtitre="GESTION SCHOOL",
            titre="NEUF RÔLES",
            mission="Une école, neuf métiers, neuf écrans différents.",
        )
        for rang, _role, titre, mission in pm.CHAPITRES:
            composer_un_carton(
                options.sortie / f"carton_{rang}.png",
                surtitre=f"CHAPITRE {rang} SUR 9",
                titre=titre,
                mission=mission,
            )
        print(f"Cartons composes dans {options.sortie}")
        return

    for outil in ("ffmpeg", "ffprobe"):
        if shutil.which(outil) is None:
            raise SystemExit(
                f"{outil} est absent. Le montage se fait sur un runner, "
                "pas sur cette machine — voir le workflow "
                "publier_video_demonstration.yml."
            )

    monter(options.sortie, options.profil)


if __name__ == "__main__":
    main()
