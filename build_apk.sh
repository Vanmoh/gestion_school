#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"
ANDROID_DIR="$APP_DIR/android"
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

cleanup_stale_gradle_locks() {
  # Stop Gradle daemons and remove lock files that are not currently held.
  if [[ -x "$ANDROID_DIR/gradlew" ]]; then
    (cd "$ANDROID_DIR" && ./gradlew --stop >/dev/null 2>&1 || true)
  fi

  if ! command -v lsof >/dev/null 2>&1; then
    return 0
  fi

  if [[ -d "$ANDROID_DIR/.gradle" ]]; then
    while IFS= read -r lock_file; do
      if lsof "$lock_file" >/dev/null 2>&1; then
        continue
      fi
      rm -f "$lock_file" >/dev/null 2>&1 || true
    done < <(find "$ANDROID_DIR/.gradle" -type f -name '*.lock' 2>/dev/null || true)
  fi
}

run_flutter_build_with_lock_retry() {
  local selected_mode="$1"
  local build_cmd=()

  if [[ "$selected_mode" == "debug" ]]; then
    build_cmd=(flutter build apk --debug "${BUILD_ARGS[@]}")
  else
    build_cmd=(flutter build apk "${BUILD_ARGS[@]}")
  fi

  local build_log
  build_log="$(mktemp)"
  local status=0

  set +e
  "${build_cmd[@]}" 2>&1 | tee "$build_log"
  status=${PIPESTATUS[0]}
  set -e

  if [[ "$status" -ne 0 ]] && grep -q 'Timeout waiting to lock file hash cache' "$build_log"; then
    echo "⚠️ Conflit de lock Gradle detecte. Nettoyage puis nouvelle tentative..."
    cleanup_stale_gradle_locks
    set +e
    "${build_cmd[@]}" 2>&1 | tee "$build_log"
    status=${PIPESTATUS[0]}
    set -e
  fi

  rm -f "$build_log"
  return "$status"
}

echo "[1/3] Résolution des dépendances Flutter..."
flutter pub get

if [[ "$DO_CLEAN" == "1" ]]; then
  echo "[2/3] Nettoyage du projet..."
  flutter clean
  flutter pub get
fi

if [[ "$MODE" == "debug" ]]; then
  echo "[3/3] Build APK debug..."
  cleanup_stale_gradle_locks
  run_flutter_build_with_lock_retry "$MODE"
  APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
  NAMED_APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/Gestion School-debug.apk"
else
  echo "[3/3] Build APK release..."
  cleanup_stale_gradle_locks
  run_flutter_build_with_lock_retry "$MODE"
  APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
  NAMED_APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/Gestion School.apk"
fi

echo
if [[ -f "$APK_PATH" ]]; then
  cp "$APK_PATH" "$NAMED_APK_PATH"
  SIZE="$(du -h "$APK_PATH" | awk '{print $1}')"
  echo "✅ APK généré: $NAMED_APK_PATH"
  echo "ℹ️ APK original Flutter: $APK_PATH"
  echo "📦 Taille: $SIZE"
else
  echo "⚠️ Build terminé, mais APK non trouvé au chemin attendu: $APK_PATH"
  exit 1
fi
