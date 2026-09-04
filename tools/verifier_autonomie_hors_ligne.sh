#!/usr/bin/env bash
# Le build web servi sur le reseau d'une ecole ne doit rien attendre d'ailleurs.
#
# Les tests Dart verifient les sources; ce script verifie ce qui part
# reellement sur le serveur. La difference compte: un `flutter build` lance
# depuis un dossier `web/` incomplet produit un build incomplet sans le dire,
# et la panne ne se constate qu'une fois hors ligne, devant une classe.
#
# Usage: tools/verifier_autonomie_hors_ligne.sh <dossier build/web>
set -euo pipefail

BUILD_DIR="${1:?Usage: $0 <dossier build/web>}"
erreurs=0

signaler() {
  echo "  ✗ $1" >&2
  erreurs=$((erreurs + 1))
}

fichier_pesant() {
  # $1 chemin, $2 taille minimale attendue en octets.
  #
  # La presence ne suffit pas: un telechargement interrompu, un pointeur LFS
  # ou une page d'erreur de proxy laissent un fichier de quelques kilo-octets.
  # Un pdf.min.js tronque redonne le symptome d'origine -- l'apercu qui tourne
  # sans fin, parce que le script ne se charge jamais tout a fait.
  local chemin="$BUILD_DIR/$1"
  if [[ ! -f "$chemin" ]]; then
    signaler "$1 manquant"
    return
  fi
  local taille
  taille="$(wc -c <"$chemin")"
  if (( taille < $2 )); then
    signaler "$1 fait $taille octets, moins que les $2 attendus (fichier tronque?)"
  fi
}

echo "Verification de l'autonomie hors ligne: $BUILD_DIR"

# 1. pdf.js, sans quoi tout apercu PDF attend un CDN qui ne repondra pas.
fichier_pesant "pdfjs/pdf.min.js" 200000
fichier_pesant "pdfjs/pdf.worker.min.js" 900000

# 2. Les verrous qui detournent le paquet `printing` vers cette copie.
if [[ -f "$BUILD_DIR/index.html" ]]; then
  grep -q "dartPdfJsBaseUrl" "$BUILD_DIR/index.html" \
    || signaler "index.html ne deroute pas pdf.js (dartPdfJsBaseUrl absent)"
  grep -q 'src="pdfjs/pdf.min.js"' "$BUILD_DIR/index.html" \
    || signaler "index.html ne precharge pas pdf.js"
else
  signaler "index.html manquant"
fi

# 3. CanvasKit local: sans `--no-web-resources-cdn`, il vient de gstatic.com
#    et l'application ne demarre pas du tout hors ligne.
[[ -d "$BUILD_DIR/canvaskit" ]] \
  || signaler "canvaskit/ absent: build sans --no-web-resources-cdn"

# 4. La police de secours des glyphes qu'Inter ne porte pas.
if [[ -f "$BUILD_DIR/assets/FontManifest.json" ]]; then
  grep -q "NotoEmoji" "$BUILD_DIR/assets/FontManifest.json" \
    || signaler "NotoEmoji absente du build: les emoji iront sur fonts.gstatic.com"
fi

# 5. Aucune adresse de tiers dans les pages servies.
#
#    Hors commentaires: nommer un CDN pour expliquer pourquoi on ne s'y
#    adresse plus est le contraire d'une dependance, et `index.html` le fait.
#
#    `main.dart.js` est exclu, et il faut l'expliquer: le moteur Flutter et le
#    paquet `printing` y compilent leurs URL par defaut -- gstatic.com pour
#    les polices Noto, unpkg.com pour pdf.js -- que les verrous ci-dessus
#    rendent inertes sans les effacer du binaire. Les chercher la rendrait ce
#    controle rouge a vie. `pdfjs/` est exclu pour la meme raison: c'est du
#    code de Mozilla qui cite ses propres adresses.
tiers="$(python3 - "$BUILD_DIR" <<'PYTHON'
import pathlib
import re
import sys

racine = pathlib.Path(sys.argv[1])
hotes = ("unpkg.com", "cdn.jsdelivr.net", "fonts.gstatic.com", "fonts.googleapis.com")
commentaire = re.compile(r"<!--.*?-->", re.S)

for chemin in sorted(racine.rglob("*")):
    if not chemin.is_file() or chemin.suffix not in (".html", ".json", ".css"):
        continue
    if "pdfjs" in chemin.parts:
        continue
    texte = chemin.read_text(errors="ignore")
    if chemin.suffix == ".html":
        texte = commentaire.sub("", texte)
    for hote in hotes:
        if hote in texte:
            print(f"{chemin.relative_to(racine)} -> {hote}")
PYTHON
)"
if [[ -n "$tiers" ]]; then
  while IFS= read -r ligne; do
    signaler "adresse d'un tiers dans $ligne"
  done <<<"$tiers"
fi

if (( erreurs > 0 )); then
  echo >&2
  echo "Ce build ira chercher $erreurs ressource(s) hors du reseau local." >&2
  echo "Sur un serveur d'ecole sans Internet, l'application sera cassee." >&2
  echo "Voir frontend/gestion_school_app/web/pdfjs/PROVENANCE.md." >&2
  exit 1
fi

echo "  ✓ Aucune dependance Internet dans le build."
