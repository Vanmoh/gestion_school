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

compose_up_with_retries() {
  local max_attempts=3
  local attempt=1
  local up_log

  while [[ "$attempt" -le "$max_attempts" ]]; do
    up_log="$(mktemp)"
    set +e
    docker_compose up -d --build 2>&1 | tee "$up_log"
    local up_rc=${PIPESTATUS[0]}
    set -e

    if [[ "$up_rc" -eq 0 ]]; then
      rm -f "$up_log"
      return 0
    fi

    if grep -qiE "failed to resolve source metadata|lookup registry-1\.docker\.io|i/o timeout|temporary failure in name resolution" "$up_log"; then
      rm -f "$up_log"
      if [[ "$attempt" -lt "$max_attempts" ]]; then
        log "Echec reseau Docker Hub detecte (tentative ${attempt}/${max_attempts}). Nouvelle tentative dans 8s..."
        sleep 8
        ((attempt++))
        continue
      fi

      echo "Erreur: impossible de joindre Docker Hub apres ${max_attempts} tentatives."
      echo "Cause probable: DNS/reseau intermittent (ex: registry-1.docker.io)."
      echo "Action conseillee: relancez ./bootstrap.sh, ou configurez des DNS stables pour Docker (1.1.1.1 / 8.8.8.8)."
      return 1
    fi

    cat "$up_log"
    rm -f "$up_log"
    return 1
  done

  return 1
}

all_columns_exist() {
  local checks_python="$1"
  docker_compose exec -T backend python manage.py shell -c "$checks_python"
}

mysql_query() {
  local sql="$1"
  docker_compose exec -T db sh -lc 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -N -e "$1"' -- "$sql"
}

school_0026_schema_complete() {
  local payroll_cols timeentry_cols checkout_nullable

  payroll_cols="$(mysql_query "USE gestion_school; SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='gestion_school' AND TABLE_NAME='school_teacherpayroll' AND COLUMN_NAME IN ('level_one_validated_at','level_one_validated_by_id','level_two_validated_at','level_two_validated_by_id');")"
  timeentry_cols="$(mysql_query "USE gestion_school; SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='gestion_school' AND TABLE_NAME='school_teachertimeentry' AND COLUMN_NAME IN ('auto_closed_reason','is_auto_closed','late_minutes','tolerated_late_minutes');")"
  checkout_nullable="$(mysql_query "USE gestion_school; SELECT COALESCE(MAX(CASE WHEN IS_NULLABLE='YES' THEN 1 ELSE 0 END), 0) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='gestion_school' AND TABLE_NAME='school_teachertimeentry' AND COLUMN_NAME='check_out_time';")"

  [[ "$payroll_cols" == "4" && "$timeentry_cols" == "4" && "$checkout_nullable" == "1" ]]
}

if ! docker_compose version >/dev/null 2>&1; then
  echo "Erreur: 'docker compose' n'est pas disponible."
  exit 1
fi

log "Démarrage de la stack backend (MySQL, Redis, Django, Celery)..."
cd "$INFRA_DIR"
compose_up_with_retries

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
  if grep -q "disk is full" "$migrate_log_file"; then
    echo "Erreur: espace disque insuffisant pendant les migrations MySQL."
    echo "Liberez de l'espace sur la partition racine puis relancez ./bootstrap.sh."
    cat "$migrate_log_file"
    rm -f "$migrate_log_file"
    exit 1
  elif grep -q "Duplicate column name 'etablissement_id'" "$migrate_log_file"; then
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
  elif grep -q "Duplicate column name 'level_one_validated_at'" "$migrate_log_file" || grep -q "Duplicate column name 'level_one_validated_by_id'" "$migrate_log_file" || grep -q "Duplicate column name 'level_two_validated_at'" "$migrate_log_file" || grep -q "Duplicate column name 'level_two_validated_by_id'" "$migrate_log_file" || grep -q "Duplicate column name 'auto_closed_reason'" "$migrate_log_file" || grep -q "Duplicate column name 'is_auto_closed'" "$migrate_log_file" || grep -q "Duplicate column name 'late_minutes'" "$migrate_log_file" || grep -q "Duplicate column name 'tolerated_late_minutes'" "$migrate_log_file"; then
    log "Schéma pointage/paie enseignants déjà présent détecté, tentative de rattrapage de la migration school.0026..."

    if school_0026_schema_complete; then
      docker_compose exec -T backend python manage.py migrate school 0026 --fake
      docker_compose exec -T backend python manage.py migrate --noinput
    else
      echo "Erreur: la migration school.0026 semble partiellement appliquée mais le schéma n'est pas complet."
      echo "Complétez ou réparez le schéma school_teacherpayroll/school_teachertimeentry puis relancez ./bootstrap.sh."
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
