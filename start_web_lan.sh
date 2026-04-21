#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"

WEB_PORT="8080"
API_PORT="8000"
HOST_IP=""

usage() {
  cat <<'EOF'
Usage: ./start_web_lan.sh [--ip=<LAN_IP>] [--web-port=<port>] [--api-port=<port>] [--dev|--watch] [--pwa]

Exemples:
  ./start_web_lan.sh
  ./start_web_lan.sh --ip=192.168.1.25
  ./start_web_lan.sh --web-port=8081 --api-port=8001
  ./start_web_lan.sh --dev
  ./start_web_lan.sh --watch
  ./start_web_lan.sh --pwa
EOF
}

MODE="stable"
PWA_STRATEGY="none"

free_web_port() {
  local pids_on_port
  pids_on_port="$(lsof -tiTCP:"$WEB_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -z "$pids_on_port" ]]; then
    return
  fi

  echo "Port ${WEB_PORT} occupé: arrêt des PID ${pids_on_port}"
  # shellcheck disable=SC2086
  kill $pids_on_port 2>/dev/null || true
  sleep 1

  pids_on_port="$(lsof -tiTCP:"$WEB_PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids_on_port" ]]; then
    echo "Port ${WEB_PORT} toujours occupé: arrêt forcé des PID ${pids_on_port}"
    # shellcheck disable=SC2086
    kill -9 $pids_on_port
  fi
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
    --dev|--watch)
      MODE="dev"
      ;;
    --pwa)
      PWA_STRATEGY="offline-first"
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

if [[ "$MODE" == "stable" ]] && ! command -v python3 >/dev/null 2>&1; then
  echo "Erreur: python3 est requis pour servir build/web en mode stable."
  exit 1
fi

if ! python3 - <<'PY' >/dev/null 2>&1
import pymysql  # noqa: F401
PY
then
  echo "Erreur: le package Python 'pymysql' est requis (pip install pymysql)."
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

echo "[1.1/3] Vérification cohérence données runtime (MySQL) ..."
if ! python3 "$ROOT_DIR/tools/runtime_data_guard.py" --etab-id=11; then
  echo "Guard KO: tentative de réparation idempotente..."
  python3 "$ROOT_DIR/tools/repair_runtime_etab11.py"
  python3 "$ROOT_DIR/tools/runtime_data_guard.py" --etab-id=11
fi

echo "[2/3] Préparation Flutter web..."
cd "$APP_DIR"
flutter pub get

echo "[3/3] Lancement web (accessible sur le réseau local)..."
echo "URL locale : http://127.0.0.1:${WEB_PORT}"
echo "URL réseau : http://${HOST_IP}:${WEB_PORT}"
echo "API utilisée: ${API_URL}"

free_web_port

if [[ "$MODE" == "dev" ]]; then
  echo "Mode dev: flutter run web-server"
  exec flutter run \
    -d web-server \
    --web-hostname=0.0.0.0 \
    --web-port="$WEB_PORT" \
    --dart-define="API_BASE_URL=${API_URL}"
fi

echo "Mode stable: build web puis serveur statique"
flutter build web --release --no-wasm-dry-run \
  --pwa-strategy="$PWA_STRATEGY" \
  --dart-define="API_BASE_URL=${API_URL}"

if [[ "$PWA_STRATEGY" == "none" ]]; then
  echo "Serveur anti-cache actif (headers no-store)"
  exec python3 "$ROOT_DIR/tools/no_cache_static_server.py" \
    --host 0.0.0.0 \
    --port "$WEB_PORT" \
    --directory build/web
fi

exec python3 -m http.server "$WEB_PORT" --bind 0.0.0.0 --directory build/web