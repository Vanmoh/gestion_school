#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"

log() {
  printf "\n[%s] %s\n" "$(date +"%H:%M:%S")" "$1"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Erreur: la commande '$1' est introuvable."
    exit 1
  fi
}

require_cmd docker

DOCKER_CMD=(docker)

if ! "${DOCKER_CMD[@]}" info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo -n docker)
  else
    docker_info_err="$(docker info 2>&1 || true)"
    if systemctl is-active docker >/dev/null 2>&1; then
      echo "Erreur: Docker est actif, mais l'utilisateur courant n'a pas accès au socket Docker."
      echo "Solution: exécutez 'sudo ./bootstrap.sh' ou ajoutez l'utilisateur au groupe docker."
      echo "Détail: ${docker_info_err}"
    else
      echo "Erreur: Docker daemon n'est pas démarré. Lancez Docker puis réessayez."
    fi
    exit 1
  fi
fi

docker_compose() {
  "${DOCKER_CMD[@]}" compose "$@"
}

all_columns_exist() {
  local checks_python="$1"
  docker_compose exec -T backend python manage.py shell -c "$checks_python"
}

if ! docker_compose version >/dev/null 2>&1; then
  echo "Erreur: 'docker compose' n'est pas disponible."
  exit 1
fi

log "Démarrage de la stack backend (MySQL, Redis, Django, Celery)..."
cd "$INFRA_DIR"
docker_compose up -d --build

log "Attente de disponibilité du service backend..."
ready=0
for _ in $(seq 1 40); do
  if docker_compose exec -T backend python manage.py check >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 3
done

if [[ "$ready" -ne 1 ]]; then
  echo "Erreur: le backend n'est pas prêt après le délai d'attente."
  docker_compose logs --tail=200 backend
  exit 1
fi

log "Application des migrations..."
migrate_log_file="$(mktemp)"
set +e
docker_compose exec -T backend python manage.py migrate --noinput 2>&1 | tee "$migrate_log_file"
migrate_rc=${PIPESTATUS[0]}
set -e

if [[ "$migrate_rc" -ne 0 ]]; then
  if grep -q "Duplicate column name 'etablissement_id'" "$migrate_log_file"; then
    log "Schéma existant détecté (colonnes etablissement_id déjà présentes), tentative de rattrapage des migrations..."

    if [[ "$(all_columns_exist "from django.db import connection; cols={c.name for c in connection.introspection.get_table_description(connection.cursor(), 'common_activitylog')}; print('1' if 'etablissement_id' in cols else '0')")" == "1" ]]; then
      docker_compose exec -T backend python manage.py migrate common 0003 --fake
    fi

    if [[ "$(all_columns_exist "from django.db import connection; cursor=connection.cursor(); needed=[('school_announcement','etablissement_id'),('school_notification','etablissement_id'),('school_smsproviderconfig','etablissement_id'),('school_supplier','etablissement_id'),('school_stockitem','etablissement_id')]; ok=True\nfor table,col in needed:\n    cols={c.name for c in connection.introspection.get_table_description(cursor, table)}\n    ok = ok and (col in cols)\nprint('1' if ok else '0')")" == "1" ]]; then
      docker_compose exec -T backend python manage.py migrate school 0016 --fake
    fi

    docker_compose exec -T backend python manage.py migrate --noinput
  elif grep -q "Table 'school_promotionrun' already exists" "$migrate_log_file" || grep -q "Table 'school_promotiondecision' already exists" "$migrate_log_file"; then
    log "Schéma passation déjà présent détecté, tentative de rattrapage de la migration school.0018..."

    if [[ "$(all_columns_exist "from django.db import connection; tables=set(connection.introspection.table_names()); print('1' if {'school_promotionrun','school_promotiondecision'}.issubset(tables) else '0')")" == "1" ]]; then
      docker_compose exec -T backend python manage.py migrate school 0018 --fake
      docker_compose exec -T backend python manage.py migrate --noinput
    else
      echo "Erreur: les tables de passation sont incohérentes (présence partielle)."
      cat "$migrate_log_file"
      rm -f "$migrate_log_file"
      exit 1
    fi
  elif grep -q "Table 'school_attendancesheetvalidation' already exists" "$migrate_log_file"; then
    log "Schéma de validation des fiches de présence déjà présent détecté, tentative de rattrapage de la migration school.0025..."

    if [[ "$(all_columns_exist "from django.db import connection; tables=set(connection.introspection.table_names()); print('1' if 'school_attendancesheetvalidation' in tables else '0')")" == "1" ]]; then
      docker_compose exec -T backend python manage.py migrate school 0025 --fake
      docker_compose exec -T backend python manage.py migrate --noinput
    else
      echo "Erreur: la table school_attendancesheetvalidation est incohérente ou absente."
      cat "$migrate_log_file"
      rm -f "$migrate_log_file"
      exit 1
    fi
  elif grep -q "Table 'chat_conversation' already exists" "$migrate_log_file" || grep -q "Table 'chat_chatmessage' already exists" "$migrate_log_file" || grep -q "Table 'chat_conversationparticipant' already exists" "$migrate_log_file" || grep -q "Table 'chat_chatpresence' already exists" "$migrate_log_file"; then
    log "Schéma chat déjà présent détecté, tentative de rattrapage des migrations chat..."

    if [[ "$(all_columns_exist "from django.db import connection; tables=set(connection.introspection.table_names()); needed={'chat_conversation','chat_chatmessage','chat_conversationparticipant','chat_chatpresence'}; print('1' if needed.issubset(tables) else '0')")" == "1" ]]; then
      docker_compose exec -T backend python manage.py migrate chat 0001 --fake

      if [[ "$(all_columns_exist "from django.db import connection; cursor=connection.cursor(); cols={c.name for c in connection.introspection.get_table_description(cursor, 'chat_conversationparticipant')}; print('1' if 'is_admin' in cols else '0')")" == "1" ]]; then
        docker_compose exec -T backend python manage.py migrate chat 0002 --fake
      fi

      docker_compose exec -T backend python manage.py migrate --noinput
    else
      echo "Erreur: les tables chat sont incohérentes (présence partielle)."
      cat "$migrate_log_file"
      rm -f "$migrate_log_file"
      exit 1
    fi
  elif grep -q "Duplicate column name 'is_admin'" "$migrate_log_file"; then
    log "Colonne chat_conversationparticipant.is_admin déjà présente, tentative de rattrapage de la migration chat.0002..."

    if [[ "$(all_columns_exist "from django.db import connection; cursor=connection.cursor(); cols={c.name for c in connection.introspection.get_table_description(cursor, 'chat_conversationparticipant')}; print('1' if 'is_admin' in cols else '0')")" == "1" ]]; then
      docker_compose exec -T backend python manage.py migrate chat 0002 --fake
      docker_compose exec -T backend python manage.py migrate --noinput
    else
      echo "Erreur: la colonne is_admin est absente malgré l'erreur duplicate."
      cat "$migrate_log_file"
      rm -f "$migrate_log_file"
      exit 1
    fi
  else
    echo "Erreur: échec des migrations."
    cat "$migrate_log_file"
    rm -f "$migrate_log_file"
    exit 1
  fi
fi

rm -f "$migrate_log_file"

log "Injection des données de démonstration..."
docker_compose exec -T backend python manage.py seed_demo_data

if command -v curl >/dev/null 2>&1; then
  log "Vérification HTTP de l'API..."
  for _ in $(seq 1 20); do
    if curl -fsS --max-time 10 "http://localhost:8000/api/docs/" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
fi

log "Bootstrap terminé ✅"
printf "\nAccès API docs: http://localhost:8000/api/docs/\n"
printf "Comptes de test:\n"
printf '%s\n' "- superadmin / Admin@12345"
printf '%s\n' "- directeur / Password@123"
printf '%s\n' "- comptable / Password@123"
printf '%s\n' "- enseignant1 / Password@123"
printf '%s\n' "- parent1 / Password@123"
printf '%s\n' "- eleve1 / Password@123"
