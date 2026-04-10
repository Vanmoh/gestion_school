#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"
START_SCRIPT="$ROOT_DIR/start_web_lan.sh"

WEB_PORT="8080"
EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: ./clean_web_lan.sh [--web-port=<port>] [other start_web_lan.sh args]

Exemples:
  ./clean_web_lan.sh
  ./clean_web_lan.sh --web-port=8081
  ./clean_web_lan.sh --ip=192.168.1.25
  ./clean_web_lan.sh --dev
  ./clean_web_lan.sh --pwa
EOF
}

for arg in "$@"; do
  case "$arg" in
    --web-port=*)
      WEB_PORT="${arg#*=}"
      EXTRA_ARGS+=("$arg")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$arg")
      ;;
  esac
done

if [[ ! -x "$START_SCRIPT" ]]; then
  echo "Erreur: script introuvable ou non exécutable: $START_SCRIPT"
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

echo "[1/3] Arrêt du serveur web local sur le port ${WEB_PORT} (si actif)..."
pids_on_port="$(lsof -tiTCP:"$WEB_PORT" -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$pids_on_port" ]]; then
  echo "PID détectés: $pids_on_port"
  # shellcheck disable=SC2086
  kill -9 $pids_on_port
else
  echo "Aucun serveur actif sur ${WEB_PORT}."
fi

echo "[2/3] Nettoyage Flutter web..."
cd "$APP_DIR"
flutter clean
flutter pub get

echo "[3/3] Rebuild + relance web anti-cache..."
cd "$ROOT_DIR"
exec "$START_SCRIPT" "${EXTRA_ARGS[@]}"
