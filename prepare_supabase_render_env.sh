#!/usr/bin/env bash
set -euo pipefail

PROJECT_REF="ztwrwmufrbzlrtgnwlyt"
PROJECT_URL="https://ztwrwmufrbzlrtgnwlyt.supabase.co"
POOLER_HOST="aws-1-eu-west-1.pooler.supabase.com"
POOLER_PORT="5432"
DB_MODE="session"

DB_PASSWORD=""
API_DOMAIN=""
WEB_DOMAIN=""
SECRET_KEY=""
OUTPUT_FILE=""

usage() {
  cat <<'EOF'
Usage:
  ./prepare_supabase_render_env.sh \
    --db-password='<SUPABASE_DB_PASSWORD>' \
    --api-domain='gestion-school-api.onrender.com' \
    [--web-domain='gestion-school-web.onrender.com'] \
    [--db-mode='session|direct'] \
    [--pooler-host='aws-1-eu-west-1.pooler.supabase.com'] \
    [--pooler-port='5432'] \
    [--secret-key='...'] \
    [--output-file='backend/.env.supabase']

Description:
  Génère les variables d'environnement prêtes pour déploiement Render + Supabase.
  Le project ref est préconfiguré pour le projet actuel.

Notes:
  - Les clés Supabase publishable/anon ne sont pas utilisées par Django pour la connexion DB.
  - La variable critique est DATABASE_URL avec mot de passe DB Supabase.
  - Par défaut, le script utilise le Session Pooler IPv4 (recommandé sur réseaux IPv4-only).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --db-password=*)
      DB_PASSWORD="${arg#*=}"
      ;;
    --api-domain=*)
      API_DOMAIN="${arg#*=}"
      ;;
    --web-domain=*)
      WEB_DOMAIN="${arg#*=}"
      ;;
    --db-mode=*)
      DB_MODE="${arg#*=}"
      ;;
    --pooler-host=*)
      POOLER_HOST="${arg#*=}"
      ;;
    --pooler-port=*)
      POOLER_PORT="${arg#*=}"
      ;;
    --secret-key=*)
      SECRET_KEY="${arg#*=}"
      ;;
    --output-file=*)
      OUTPUT_FILE="${arg#*=}"
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

if [[ -z "$DB_PASSWORD" || -z "$API_DOMAIN" ]]; then
  echo "Erreur: --db-password et --api-domain sont obligatoires."
  usage
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Erreur: python3 est requis pour encoder le mot de passe DB dans l'URL."
  exit 1
fi

ENCODED_DB_PASSWORD="$(python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DB_PASSWORD")"

normalize_domain() {
  local raw="$1"
  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%%/*}"
  printf "%s" "$raw"
}

API_DOMAIN="$(normalize_domain "$API_DOMAIN")"

if [[ -z "$WEB_DOMAIN" ]]; then
  WEB_DOMAIN="$API_DOMAIN"
else
  WEB_DOMAIN="$(normalize_domain "$WEB_DOMAIN")"
fi

case "$DB_MODE" in
  session)
    DATABASE_URL="postgresql://postgres.${PROJECT_REF}:${ENCODED_DB_PASSWORD}@${POOLER_HOST}:${POOLER_PORT}/postgres?sslmode=require"
    ;;
  direct)
    DATABASE_URL="postgresql://postgres:${ENCODED_DB_PASSWORD}@db.${PROJECT_REF}.supabase.co:5432/postgres?sslmode=require"
    ;;
  *)
    echo "Erreur: --db-mode doit être 'session' ou 'direct'."
    exit 1
    ;;
esac

if [[ -z "$SECRET_KEY" ]]; then
  SECRET_KEY="change_me_with_strong_random_secret"
fi

RENDER_ENV="DEBUG=False
SECRET_KEY=$SECRET_KEY
ALLOWED_HOSTS=$API_DOMAIN
CORS_ALLOW_ALL_ORIGINS=False
CORS_ALLOWED_ORIGINS=https://$WEB_DOMAIN
CSRF_TRUSTED_ORIGINS=https://$API_DOMAIN
DATABASE_URL=$DATABASE_URL
DB_SSL_REQUIRE=True
DB_CONN_MAX_AGE=600
USE_X_FORWARDED_HOST=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
"

echo "Projet Supabase : $PROJECT_URL"
echo "Project ref      : $PROJECT_REF"
echo "Mode DB          : $DB_MODE"
echo
echo "Variables Render à copier :"
echo "----------------------------------------"
printf "%s" "$RENDER_ENV"
echo "----------------------------------------"

if [[ -n "$OUTPUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUTPUT_FILE")"
  printf "%s" "$RENDER_ENV" > "$OUTPUT_FILE"
  echo "Fichier généré: $OUTPUT_FILE"
fi
