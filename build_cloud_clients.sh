#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"

API_URL=""
TARGETS="apk,web,linux"

usage() {
  cat <<'EOF'
Usage: ./build_cloud_clients.sh --api-url=<https://backend-domain/api> [--targets=apk,web,linux]

Options:
  --api-url   URL API publique utilisée par les builds (obligatoire)
  --targets   Liste séparée par virgules: apk,web,linux (défaut: apk,web,linux)
  -h, --help  Afficher l'aide

Exemples:
  ./build_cloud_clients.sh --api-url=https://api.mondomaine.com/api
  ./build_cloud_clients.sh --api-url=https://api.mondomaine.com/api --targets=apk,web
EOF
}

for arg in "$@"; do
  case "$arg" in
    --api-url=*)
      API_URL="${arg#*=}"
      ;;
    --targets=*)
      TARGETS="${arg#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Argument inconnu: $arg"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$API_URL" ]]; then
  echo "Erreur: --api-url est obligatoire."
  usage
  exit 1
fi

if [[ "$API_URL" != http://* && "$API_URL" != https://* ]]; then
  echo "Erreur: --api-url doit commencer par http:// ou https://"
  exit 1
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Erreur: dossier Flutter introuvable: $APP_DIR"
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Erreur: flutter n'est pas installé ou absent du PATH."
  exit 1
fi

cd "$APP_DIR"

echo "[1/4] Résolution des dépendances Flutter..."
flutter pub get

IFS=',' read -r -a target_list <<< "$TARGETS"

build_apk() {
  echo "[2/4] Build APK release..."
  flutter build apk --release --dart-define=API_BASE_URL="$API_URL"
  echo "APK: $APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
}

build_web() {
  echo "[3/4] Build web release..."
  flutter build web --release --dart-define=API_BASE_URL="$API_URL"
  echo "WEB: $APP_DIR/build/web"
}

build_linux() {
  echo "[4/4] Build Linux desktop release..."
  flutter build linux --release --dart-define=API_BASE_URL="$API_URL"
  echo "LINUX: $APP_DIR/build/linux/x64/release/bundle"
}

for target in "${target_list[@]}"; do
  clean_target="$(echo "$target" | xargs)"
  case "$clean_target" in
    apk)
      build_apk
      ;;
    web)
      build_web
      ;;
    linux)
      build_linux
      ;;
    *)
      echo "Cible ignorée (inconnue): $clean_target"
      ;;
  esac
done

echo
echo "✅ Builds terminés avec API publique: $API_URL"
