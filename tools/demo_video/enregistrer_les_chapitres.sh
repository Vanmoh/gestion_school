#!/usr/bin/env bash
#
# Filme l'application pendant qu'un pilote la conduit, un chapitre par role.
#
# Ce script ne tourne pas sur une machine de developpement ordinaire: il lui
# faut un serveur X (fut-il virtuel), la chaine de compilation Linux de Flutter,
# et ffmpeg. C'est la raison pour laquelle la video se fabrique sur un runner.
#
# Le point de rupture est connu et se verifie d'abord: l'embedder GTK de Flutter
# cree un contexte OpenGL, que Xvfb n'offre que par un rendu logiciel. L'etape
# de diagnostic echoue donc en quelques secondes si le GL manque, plutot que de
# laisser une prise expirer au bout de dix minutes sans dire pourquoi.
#
# Ce que le script depose pour chaque prise, dans --sortie:
#   brut_<rang>.mkv        la capture, telle que x11grab l'a ecrite
#   geometrie_<rang>.txt   la geometrie reelle de la fenetre, lue et non supposee
#   journal_<rang>.jsonl   ce que le pilote a dit au montage
#   t0_<rang>.txt          l'instant ou la capture a commence a ecrire des images
#
# Sans `t0`, le montage ne saurait pas ramener les horodatages absolus du
# journal au temps de la video.

set -uo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPLICATION="$RACINE/frontend/gestion_school_app"
SORTIE="$RACINE/tools/demo_video/sortie"
SEULEMENT=""
IMAGES_PAR_SECONDE=25
LARGEUR=1280
HAUTEUR=720

usage() {
  cat <<'FIN'
Usage: enregistrer_les_chapitres.sh [options]

  --sortie <dossier>   Ou deposer les rushes (defaut tools/demo_video/sortie)
  --seulement <rangs>  Ne tourner que ces prises, separees par des virgules
                       (« 3 » pour le seul chapitre du directeur)
  --fps <n>            Images par seconde de la capture (defaut 25)
  --aide               Ce message

Le debit de 25 images par seconde n'est pas un choix esthetique: en debug sous
rendu logiciel, l'application ne peint pas beaucoup plus, et capturer a 60
ecrirait surtout des doublons.
FIN
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sortie) SORTIE="$2"; shift 2 ;;
    --seulement) SEULEMENT="$2"; shift 2 ;;
    --fps) IMAGES_PAR_SECONDE="$2"; shift 2 ;;
    --aide|-h) usage; exit 0 ;;
    *) echo "Option inconnue: $1" >&2; usage; exit 2 ;;
  esac
done

# Les neuf prises, dans l'ordre de la video. Le rang sert de numero de chapitre
# et de suffixe de fichier; le nom du fichier de test est celui du pilote.
PRISES=(
  "1:r1_super_admin_test.dart:super_admin"
  "2:r2_promoteur_test.dart:promoter"
  "3:r3_directeur_test.dart:director"
  "4:r4_censeur_test.dart:censor"
  "5:r5_comptable_test.dart:accountant"
  "6:r6_surveillant_test.dart:supervisor"
  "7:r7_enseignant_test.dart:teacher"
  "8:r8_parent_test.dart:parent"
  "9:r9_eleve_test.dart:student"
)

mkdir -p "$SORTIE"

dire() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# --------------------------------------------------------------- diagnostics

verifier_les_outils() {
  local manquants=()
  for outil in ffmpeg xvfb-run xdotool xwininfo flutter; do
    command -v "$outil" >/dev/null 2>&1 || manquants+=("$outil")
  done
  if [[ ${#manquants[@]} -gt 0 ]]; then
    echo "Outils absents: ${manquants[*]}" >&2
    echo "Ce script a besoin d'un serveur X, de ffmpeg et de la chaine Flutter." >&2
    return 1
  fi
}

verifier_le_contexte_gl() {
  # L'etape qui decide de toute la voie. Elle coute cinq secondes et evite dix
  # minutes d'attente sur une prise qui n'aurait jamais affiche une fenetre.
  dire "Contexte OpenGL sous serveur X virtuel"
  if ! command -v glxinfo >/dev/null 2>&1; then
    echo "glxinfo absent: diagnostic impossible, on tente la suite." >&2
    return 0
  fi
  if LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a \
      -s "-screen 0 ${LARGEUR}x${HAUTEUR}x24 +extension GLX +extension RENDER -nolisten tcp" \
      glxinfo -B 2>&1 | tee "$SORTIE/glxinfo.txt" | grep -qi "renderer"; then
    grep -i "renderer\|OpenGL version" "$SORTIE/glxinfo.txt" | head -3
    return 0
  fi
  echo "Aucun contexte OpenGL: l'embedder GTK de Flutter ne pourra pas ouvrir" >&2
  echo "de fenetre. Voir tools/demo_video/sortie/glxinfo.txt." >&2
  return 1
}

# ------------------------------------------------------------- une prise

tourner_une_prise() {
  local rang="$1" fichier="$2" role="$3"
  local brut="$SORTIE/brut_${rang}.mkv"
  local journal="$SORTIE/journal_${rang}.jsonl"
  local geometrie="$SORTIE/geometrie_${rang}.txt"
  local horodate="$SORTIE/t0_${rang}.txt"

  if [[ ! -f "$APPLICATION/integration_test/demonstration/$fichier" ]]; then
    echo "Pilote absent pour le chapitre $rang ($role): $fichier" >&2
    return 1
  fi

  dire "Chapitre $rang — $role"
  rm -f "$brut" "$journal" "$geometrie" "$horodate"

  # Un serveur X par prise, et un HOME par prise: le choix d'etablissement se
  # retient dans le trousseau du systeme, et une prise ne doit pas heriter de
  # l'ecran ou la precedente s'est arretee.
  local affichage=":$((90 + rang))"
  local maison
  maison="$(mktemp -d)"

  Xvfb "$affichage" -screen 0 "${LARGEUR}x${HAUTEUR}x24" \
    +extension GLX +extension RENDER -nolisten tcp >"$SORTIE/xvfb_${rang}.log" 2>&1 &
  local pid_xvfb=$!
  sleep 2

  # Un gestionnaire de fenetres minimal si l'on en trouve un: sans lui, GTK
  # place parfois la fenetre hors champ, et la capture filme du noir.
  local pid_wm=""
  if command -v openbox >/dev/null 2>&1; then
    DISPLAY="$affichage" openbox >/dev/null 2>&1 &
    pid_wm=$!
    sleep 1
  fi

  (
    cd "$APPLICATION" || exit 1
    DISPLAY="$affichage" \
    HOME="$maison" \
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    JOURNAL_DEMO="$journal" \
    DUREE_DE_POSE_MS="${DUREE_DE_POSE_MS:-2500}" \
    flutter test -d linux "integration_test/demonstration/$fichier" \
      >"$SORTIE/pilote_${rang}.log" 2>&1
  ) &
  local pid_pilote=$!

  # On attend la fenetre plutot qu'un delai fixe: le premier build CMake est
  # long, les suivants ne le sont pas, et un delai devine serait faux dans les
  # deux cas.
  local identifiant=""
  for _ in $(seq 1 180); do
    identifiant="$(DISPLAY="$affichage" xdotool search --name 'gestion_school_app' 2>/dev/null | head -1 || true)"
    [[ -n "$identifiant" ]] && break
    if ! kill -0 "$pid_pilote" 2>/dev/null; then
      echo "Le pilote s'est arrete avant d'ouvrir sa fenetre." >&2
      tail -25 "$SORTIE/pilote_${rang}.log" >&2 || true
      kill "$pid_xvfb" 2>/dev/null
      return 1
    fi
    sleep 1
  done

  if [[ -z "$identifiant" ]]; then
    echo "Aucune fenetre apres trois minutes: prise abandonnee." >&2
    kill "$pid_pilote" "$pid_xvfb" 2>/dev/null
    return 1
  fi

  # La geometrie se lit, elle ne se suppose pas: la barre de titre GTK decale la
  # vue Flutter, et c'est ce decalage que le montage applique aux encadres.
  DISPLAY="$affichage" xwininfo -id "$identifiant" > "$geometrie" 2>/dev/null || true
  local hauteur_vue
  hauteur_vue="$(awk '/Height:/ {print $2; exit}' "$geometrie" 2>/dev/null || echo "$HAUTEUR")"
  local decalage=$(( HAUTEUR - hauteur_vue ))
  [[ "$decalage" -lt 0 ]] && decalage=0
  echo "decalage_vertical=$decalage" >> "$geometrie"

  ffmpeg -nostdin -loglevel warning -y \
    -f x11grab -framerate "$IMAGES_PAR_SECONDE" \
    -video_size "${LARGEUR}x${HAUTEUR}" -i "$affichage" \
    -c:v libx264 -preset ultrafast -qp 0 -pix_fmt yuv420p \
    "$brut" >"$SORTIE/ffmpeg_${rang}.log" 2>&1 &
  local pid_ffmpeg=$!

  # `t0` une fois que le fichier grossit vraiment: le demarrage de x11grab prend
  # un instant, et dater la capture depuis l'appel a ffmpeg decalerait tout
  # l'habillage de cette latence.
  for _ in $(seq 1 100); do
    if [[ -s "$brut" ]]; then break; fi
    sleep 0.1
  done
  date +%s%3N > "$horodate"

  wait "$pid_pilote"
  local issue=$?

  # SIGINT et non SIGKILL: ffmpeg doit finir d'ecrire son index, sinon le
  # fichier n'est pas lisible.
  kill -INT "$pid_ffmpeg" 2>/dev/null
  wait "$pid_ffmpeg" 2>/dev/null
  [[ -n "$pid_wm" ]] && kill "$pid_wm" 2>/dev/null
  kill "$pid_xvfb" 2>/dev/null
  rm -rf "$maison"

  if [[ ! -s "$brut" ]]; then
    echo "Chapitre $rang: aucune image capturee." >&2
    return 1
  fi

  local taille
  taille="$(du -h "$brut" | cut -f1)"
  echo "Chapitre $rang: $taille, decalage vertical ${decalage}px, pilote code $issue"

  # Le code du pilote ne fait pas echouer la prise: un geste manque peut-etre,
  # mais les images sont la et le journal dira ce qui n'a pas eu lieu. Perdre
  # une prise entiere pour un bouton absent couterait plus cher que le montrer
  # incomplete.
  return 0
}

# ----------------------------------------------------------------- le tour

verifier_les_outils || exit 1
verifier_le_contexte_gl || exit 1

dire "Compilation de l'application (une fois pour les neuf prises)"
(
  cd "$APPLICATION" || exit 1
  flutter config --enable-linux-desktop >/dev/null
  flutter pub get >/dev/null
) || exit 1

echec=0
for prise in "${PRISES[@]}"; do
  IFS=':' read -r rang fichier role <<< "$prise"
  if [[ -n "$SEULEMENT" ]] && [[ ",$SEULEMENT," != *",$rang,"* ]]; then
    continue
  fi
  if ! tourner_une_prise "$rang" "$fichier" "$role"; then
    echo "Chapitre $rang manquant." >&2
    echec=$((echec + 1))
  fi
done

dire "Rushes deposes dans $SORTIE"
ls -1 "$SORTIE" | sed 's/^/  /'

if [[ "$echec" -gt 0 ]]; then
  echo "$echec chapitre(s) n'ont pas pu etre tournes." >&2
  # On ne fait pas echouer le tour entier: le montage remplacera les chapitres
  # manquants par un carton qui le dit, plutot que de perdre les autres.
fi
exit 0
