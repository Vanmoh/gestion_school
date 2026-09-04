#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"

WEB_PORT="8080"
API_PORT="8000"
HOST_IP=""
# Vide par defaut: l'application deduit l'API de la page servie. Ne la figer
# que pour pointer une API qui vit ailleurs que sur la machine du serveur web.
API_URL_FORCEE=""
GUARD_ETAB_ID="11"

usage() {
  cat <<'EOF'
Usage: ./start_web_lan.sh [--ip=<LAN_IP>] [--web-port=<port>] [--api-port=<port>]
                         [--api-url=<url>] [--dev|--watch] [--pwa]

Exemples:
  ./start_web_lan.sh
  ./start_web_lan.sh --ip=192.168.1.25
  ./start_web_lan.sh --web-port=8081 --api-port=8001
  ./start_web_lan.sh --api-url=https://api.exemple.org/api
  ./start_web_lan.sh --dev
  ./start_web_lan.sh --watch
  ./start_web_lan.sh --pwa
EOF
}

MODE="stable"
PWA_STRATEGY="none"

run_flutter_pub_get() {
  local max_attempts=3
  local attempt=1
  local primary_hosted="${PUB_HOSTED_URL:-https://pub.dev}"
  local primary_storage="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"
  local mirror_hosted="https://pub.flutter-io.cn"
  local mirror_storage="https://storage.flutter-io.cn"
  local pub_log

  while [[ "$attempt" -le "$max_attempts" ]]; do
    pub_log="$(mktemp)"
    set +e
    PUB_HOSTED_URL="$primary_hosted" FLUTTER_STORAGE_BASE_URL="$primary_storage" flutter pub get 2>&1 | tee "$pub_log"
    local rc=${PIPESTATUS[0]}
    set -e

    if [[ "$rc" -eq 0 ]]; then
      rm -f "$pub_log"
      return 0
    fi

    if grep -qiE "connection reset by peer|failed to update packages|socketexception|timed out|temporary failure" "$pub_log"; then
      rm -f "$pub_log"
      if [[ "$attempt" -lt "$max_attempts" ]]; then
        echo "[2/3] Echec reseau pub.dev detecte (tentative ${attempt}/${max_attempts}). Nouvelle tentative dans 4s..."
        sleep 4
        ((attempt++))
        continue
      fi
      break
    fi

    cat "$pub_log"
    rm -f "$pub_log"
    return 1
  done

  # Cache pub local d'abord: instantane et hors-ligne, contrairement au mirror distant.
  echo "[2/3] Reseau pub.dev instable: tentative sur le cache pub local (--offline)..."
  set +e
  flutter pub get --offline
  local offline_rc=$?
  set -e
  if [[ "$offline_rc" -eq 0 ]]; then
    echo "[2/3] Dependances resolues depuis le cache local."
    return 0
  fi

  if [[ "$primary_hosted" != "$mirror_hosted" ]]; then
    echo "[2/3] Cache local insuffisant: bascule vers mirror Flutter CN..."
    set +e
    PUB_HOSTED_URL="$mirror_hosted" FLUTTER_STORAGE_BASE_URL="$mirror_storage" flutter pub get
    local mirror_rc=$?
    set -e
    if [[ "$mirror_rc" -eq 0 ]]; then
      return 0
    fi
  fi

  echo "Erreur: impossible de recuperer les dependances Flutter (pub.dev, cache local et mirror indisponibles)."
  echo "Action conseillee: relancer ./start_web_lan.sh quand le reseau se stabilise."
  return 1
}

guard_etab_exists() {
  python3 - "$GUARD_ETAB_ID" <<'PY' >/dev/null 2>&1
import sys

import pymysql

etab_id = int(sys.argv[1])
conn = pymysql.connect(
    host="127.0.0.1",
    port=3306,
    user="gestion_user",
    password="gestion_password",
    database="gestion_school",
    charset="utf8mb4",
)
try:
    with conn.cursor() as cur:
        cur.execute("SELECT 1 FROM school_etablissement WHERE id=%s", (etab_id,))
        found = cur.fetchone() is not None
finally:
    conn.close()

raise SystemExit(0 if found else 1)
PY
}

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
    --api-url=*)
      API_URL_FORCEE="${arg#*=}"
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

# L'adresse de l'API n'entre pas dans le build.
#
# Elle y entrait, sous la forme --dart-define=API_BASE_URL=http://<IP LAN>:8000,
# et cette IP survivait au reseau qui l'avait vue naitre: le lendemain, sur un
# autre Wi-Fi ou apres un bail DHCP different, l'application ouverte sur
# 127.0.0.1 appelait toujours l'ancienne adresse et n'obtenait plus rien --
# l'ecran de selection restait vide, sans un mot pour dire pourquoi.
#
# Sans cette definition, ApiConstants deduit l'API de la page servie
# (meme hote, port ${API_PORT}): l'adresse est juste depuis le poste comme
# depuis un telephone du reseau, sans reconstruire quoi que ce soit.
# --api-url reste la pour les API qui vivent vraiment ailleurs.
#
# Seul le port entre dans le build: l'hote se lit sur la page, le port non.
# Sans lui, --api-port=8001 etait honore par le controle du backend et par
# les URL affichees, mais pas par l'application, qui continuait d'appeler
# 8000 -- le drapeau semblait pris en compte alors qu'il ne l'etait qu'a
# moitie.
DART_DEFINES=()
if [[ -n "$API_URL_FORCEE" ]]; then
  DART_DEFINES+=(--dart-define="API_BASE_URL=${API_URL_FORCEE}")
else
  DART_DEFINES+=(--dart-define="API_PORT=${API_PORT}")
fi

echo "[1/3] Vérification API backend sur ${API_DOCS_URL} ..."
if ! curl -fsS --max-time 8 "$API_DOCS_URL" >/dev/null 2>&1; then
  echo "Backend non joignable via IP LAN: $HOST_IP:$API_PORT"
  echo "Astuce: vérifie que ./bootstrap.sh est lancé et que le pare-feu autorise le port $API_PORT."
  exit 1
fi

echo "[1.1/3] Vérification cohérence données runtime (MySQL) ..."
if ! guard_etab_exists; then
  echo "Etablissement ${GUARD_ETAB_ID} absent de la base: guard ignoré (base fraîche ou jeu de données démo)."
elif ! python3 "$ROOT_DIR/tools/runtime_data_guard.py" --etab-id="$GUARD_ETAB_ID"; then
  echo "Guard KO: tentative de réparation idempotente..."
  python3 "$ROOT_DIR/tools/repair_runtime_etab11.py"
  python3 "$ROOT_DIR/tools/runtime_data_guard.py" --etab-id="$GUARD_ETAB_ID"
fi

echo "[2/3] Préparation Flutter web..."
cd "$APP_DIR"
run_flutter_pub_get

echo "[3/3] Lancement web (accessible sur le réseau local)..."
echo "URL locale : http://127.0.0.1:${WEB_PORT}"
echo "URL réseau : http://${HOST_IP}:${WEB_PORT}"
if [[ -n "$API_URL_FORCEE" ]]; then
  echo "API utilisée: ${API_URL_FORCEE} (figée dans le build)"
else
  echo "API utilisée: déduite de la page servie, port ${API_PORT}"
  echo "               (http://127.0.0.1:${API_PORT}/api ou http://${HOST_IP}:${API_PORT}/api)"
fi

free_web_port

if [[ "$MODE" == "dev" ]]; then
  echo "Mode dev: flutter run web-server"
  exec flutter run \
    -d web-server \
    --web-hostname=0.0.0.0 \
    --web-port="$WEB_PORT" \
    "${DART_DEFINES[@]}"
fi

echo "Mode stable: build web puis serveur statique"
# --no-web-resources-cdn: CanvasKit sort du build et non de gstatic.com. Servi
# depuis le CDN, l'application ne demarrait pas du tout sans Internet -- or un
# serveur de classe sur reseau local est precisement le cas ou il n'y en a pas.
flutter build web --release --no-wasm-dry-run --no-web-resources-cdn \
  --pwa-strategy="$PWA_STRATEGY" \
  "${DART_DEFINES[@]}"

# Bloquant, et c'est voulu: servir un build qui ira chercher pdf.js ou une
# police sur Internet, c'est servir une application dont les apercus PDF
# tournent sans fin. Mieux vaut ne pas demarrer que le decouvrir en classe.
"$ROOT_DIR/tools/verifier_autonomie_hors_ligne.sh" "$APP_DIR/build/web"

if [[ "$PWA_STRATEGY" == "none" ]]; then
  echo "Serveur anti-cache actif (headers no-store)"
  exec python3 "$ROOT_DIR/tools/no_cache_static_server.py" \
    --host 0.0.0.0 \
    --port "$WEB_PORT" \
    --directory build/web
fi

exec python3 -m http.server "$WEB_PORT" --bind 0.0.0.0 --directory build/web