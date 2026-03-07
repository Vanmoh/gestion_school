#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"
MODE="release"
DO_CLEAN=0
API_BASE_URL=""

usage() {
  cat <<'EOF'
Usage: ./build_apk.sh [release|debug] [--clean] [--api-url=<url>]

Options:
  release     Build APK release (default)
  debug       Build APK debug
  --clean     Run flutter clean before build
  --api-url   API base URL embedded in APK (example: http://192.168.1.10:8000/api)
  -h, --help  Show this help
EOF
}

for arg in "$@"; do
  case "$arg" in
    release|debug)
      MODE="$arg"
      ;;
    --clean)
      DO_CLEAN=1
      ;;
    --api-url=*)
      API_BASE_URL="${arg#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      usage
      exit 1
      ;;
  esac
done

if ! command -v flutter >/dev/null 2>&1; then
  echo "Erreur: flutter n'est pas installé ou n'est pas dans le PATH."
  exit 1
fi

BUILD_ARGS=()
if [[ -n "$API_BASE_URL" ]]; then
  BUILD_ARGS+=("--dart-define=API_BASE_URL=$API_BASE_URL")
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Erreur: dossier Flutter introuvable: $APP_DIR"
  exit 1
fi

cd "$APP_DIR"

echo "[1/3] Résolution des dépendances Flutter..."
flutter pub get

if [[ "$DO_CLEAN" == "1" ]]; then
  echo "[2/3] Nettoyage du projet..."
  flutter clean
  flutter pub get
fi

if [[ "$MODE" == "debug" ]]; then
  echo "[3/3] Build APK debug..."
  flutter build apk --debug "${BUILD_ARGS[@]}"
  APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
else
  echo "[3/3] Build APK release..."
  flutter build apk "${BUILD_ARGS[@]}"
  APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
fi

echo
if [[ -f "$APK_PATH" ]]; then
  SIZE="$(du -h "$APK_PATH" | awk '{print $1}')"
  echo "✅ APK généré: $APK_PATH"
  echo "📦 Taille: $SIZE"
else
  echo "⚠️ Build terminé, mais APK non trouvé au chemin attendu: $APK_PATH"
  exit 1
fi
