#!/usr/bin/env bash
#
# Recopie la base de production dans le PostgreSQL local de developpement.
#
# Pourquoi ce script existe: le projet a longtemps eu trois bases distinctes
# — Supabase en production, un MySQL dans docker-compose, un SQLite pour le
# `manage.py` de l'hote — et rien ne le signalait. Lancer l'application en
# local affichait une ecole vide sans qu'aucune erreur n'apparaisse.
#
# ATTENTION: le contenu de la base locale est ECRASE. La production n'est
# jamais ouverte qu'en lecture.
#
# Usage:
#   tools/sync_local_db.sh                    # lit backend/.env.supabase.local
#   PROD_DATABASE_URL=postgres://... tools/sync_local_db.sh

set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTENEUR="gestion_school_pg"
BASE_LOCALE="gestion_school"
UTILISATEUR_LOCAL="gestion_user"

# --- Source de production (lecture seule) -----------------------------------
URL_PROD="${PROD_DATABASE_URL:-}"
if [ -z "$URL_PROD" ]; then
  FICHIER="$RACINE/backend/.env.supabase.local"
  [ -f "$FICHIER" ] || {
    echo "Aucune source: definissez PROD_DATABASE_URL, ou creez $FICHIER." >&2
    exit 1
  }
  URL_PROD="$(grep -E '^DATABASE_URL=' "$FICHIER" | head -1 | cut -d= -f2- \
    | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")"
fi
[ -n "$URL_PROD" ] || { echo "URL de production vide." >&2; exit 1; }

# Le pooler transactionnel (6543) ne sait pas servir pg_dump: il ne garde pas
# la session entre les requetes et le dump s'interrompt en cours de route.
case "$URL_PROD" in
  *:6543*) echo "Utilisez le port 5432 (pooler de session), pas 6543." >&2
           exit 1 ;;
esac

# --- Garde-fou: la cible doit etre le conteneur local ------------------------
# Le script contient des DROP. Il ne s'adresse qu'a un conteneur local, jamais
# a une URL fournie par l'appelant: une inversion des deux effacerait l'ecole.
docker inspect "$CONTENEUR" > /dev/null 2>&1 || {
  echo "Conteneur $CONTENEUR absent. Lancez d'abord:" >&2
  echo "  docker compose -f infra/docker-compose.yml up -d postgres" >&2
  exit 1
}

echo "==> Attente de la base locale"
for _ in $(seq 1 40); do
  docker exec "$CONTENEUR" psql -U "$UTILISATEUR_LOCAL" -d "$BASE_LOCALE" \
    -c 'select 1' > /dev/null 2>&1 && break
  sleep 2
done

DUMP="$(mktemp -t gestion_school_prod_XXXXXX.sql)"
trap 'rm -f "$DUMP"' EXIT

echo "==> Extraction de la production (lecture seule)"
# --schema=public uniquement: les schemas auth/storage/realtime appartiennent
# a Supabase et n'ont aucun equivalent dans un PostgreSQL nu.
pg_dump "$URL_PROD" \
  --schema=public --no-owner --no-privileges --no-comments \
  --clean --if-exists -f "$DUMP"
echo "    $(du -h "$DUMP" | cut -f1), $(grep -c '^CREATE TABLE' "$DUMP") tables"

echo "==> Restauration dans $CONTENEUR (le contenu local est ecrase)"
docker exec -i "$CONTENEUR" psql -U "$UTILISATEUR_LOCAL" -d "$BASE_LOCALE" \
  -v ON_ERROR_STOP=0 < "$DUMP" > /tmp/gestion_school_restore.log 2>&1

# Les DROP ... IF EXISTS sur une base vide ne sont pas des echecs.
ERREURS="$(grep -E '^(ERREUR|ERROR)' /tmp/gestion_school_restore.log \
  | grep -viE "n'existe pas|does not exist" | head -5 || true)"
if [ -n "$ERREURS" ]; then
  echo "Erreurs pendant la restauration:" >&2
  echo "$ERREURS" >&2
  echo "Journal complet: /tmp/gestion_school_restore.log" >&2
  exit 1
fi

echo "==> Verification"
docker exec "$CONTENEUR" psql -U "$UTILISATEUR_LOCAL" -d "$BASE_LOCALE" \
  -At -F' = ' -c "
select 'etablissements', count(*) from school_etablissement
union all select 'classes', count(*) from school_classroom
union all select 'eleves',  count(*) from school_student
union all select 'utilisateurs', count(*) from users order by 1;" \
  | sed 's/^/    /'

echo
echo "Termine. Les mots de passe sont ceux de production: connectez-vous"
echo "avec un compte reel, ou creez-en un via 'manage.py createsuperuser'."
