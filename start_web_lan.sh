#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"

WEB_PORT="8080"
API_PORT="8000"
HOST_IP=""

usage() {
  cat <<'EOF'
Usage: ./start_web_lan.sh [--ip=<LAN_IP>] [--web-port=<port>] [--api-port=<port>]

Exemples:
  ./start_web_lan.sh
  ./start_web_lan.sh --ip=192.168.1.25
  ./start_web_lan.sh --web-port=8081 --api-port=8001
EOF
}

for arg in "$@"; do
  case "$arg" in
    --ip=*)
      HOST_IP="${arg#*=}"
      ;;
    --web-port=*)
      WEB_PORT="${arg#*=}"
      ;;
    --api-port=*)
      API_PORT="${arg#*=}"
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

if ! command -v flutter >/dev/null 2>&1; then
  echo "Erreur: flutter n'est pas installé ou absent du PATH."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Erreur: curl est requis pour vérifier l'API backend."
  exit 1
fi

if [[ -z "$HOST_IP" ]]; then
  HOST_IP="$(hostname -I | awk '{print $1}')"
fi

if [[ -z "$HOST_IP" ]]; then
  echo "Erreur: impossible de détecter l'IP locale. Utilise --ip=<LAN_IP>."
  exit 1
fi

if [[ ! -d "$APP_DIR" ]]; then
  echo "Erreur: dossier Flutter introuvable: $APP_DIR"
  exit 1
fi

API_URL="http://${HOST_IP}:${API_PORT}/api"
API_DOCS_URL="http://${HOST_IP}:${API_PORT}/api/docs/"

echo "[1/3] Vérification API backend sur ${API_DOCS_URL} ..."
if ! curl -fsS --max-time 8 "$API_DOCS_URL" >/dev/null 2>&1; then
  echo "Backend non joignable via IP LAN: $HOST_IP:$API_PORT"
  echo "Astuce: vérifie que ./bootstrap.sh est lancé et que le pare-feu autorise le port $API_PORT."
  exit 1
fi

echo "[2/3] Préparation Flutter web..."
cd "$APP_DIR"
flutter pub get

echo "[3/3] Lancement web (accessible sur le réseau local)..."
echo "URL locale : http://127.0.0.1:${WEB_PORT}"
echo "URL réseau : http://${HOST_IP}:${WEB_PORT}"
echo "API utilisée: ${API_URL}"

exec flutter run \
  -d web-server \
  --web-hostname=0.0.0.0 \
  --web-port="$WEB_PORT" \
  --dart-define="API_BASE_URL=${API_URL}"
