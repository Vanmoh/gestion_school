#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"

ETAB_ID="11"
TERM="T1"
TERMS=""
SEED="20260423"
API_BASE_URL="http://127.0.0.1:8000/api"
API_USERNAME="superadmin"
API_PASSWORD="Admin@12345"
CLASSROOM_ID="35"
ACADEMIC_YEAR_ID="1"
DRY_RUN="false"
CLOSE_TERM="false"
CLOSE_NOTES="Cloture automatique apres injection des notes."

usage() {
  cat <<'EOF'
Usage: ./seed_runtime_term_scores.sh [options]

Options:
  --etab-id=<id>            Etablissement cible (defaut: 11)
  --term=<T1|T2|T3>         Trimestre cible (defaut: T1)
  --terms=<csv>             Liste de trimestres, ex: T1,T2,T3 (prioritaire sur --term)
  --seed=<int>              Seed pseudo-aleatoire deterministic (defaut: 20260423)
  --api-base-url=<url>      Base URL API pour validation (defaut: http://127.0.0.1:8000/api)
  --api-username=<user>     Identifiant API pour validation (defaut: superadmin)
  --api-password=<pass>     Mot de passe API pour validation (defaut: Admin@12345)
  --classroom-id=<id>       Classe a sonder via l'API apres injection (defaut: 35)
  --academic-year-id=<id>   Annee scolaire a sonder via l'API (defaut: 1)
  --close-term              Cloture automatiquement la periode apres seed
  --close-notes=<text>      Notes de cloture appliquees si --close-term
  --dry-run                 N'ecrit rien, verifie seulement la chaine complete
  -h, --help                Affiche cette aide
EOF
}

for arg in "$@"; do
  case "$arg" in
    --etab-id=*)
      ETAB_ID="${arg#*=}"
      ;;
    --term=*)
      TERM="${arg#*=}"
      ;;
    --terms=*)
      TERMS="${arg#*=}"
      ;;
    --seed=*)
      SEED="${arg#*=}"
      ;;
    --api-base-url=*)
      API_BASE_URL="${arg#*=}"
      ;;
    --api-username=*)
      API_USERNAME="${arg#*=}"
      ;;
    --api-password=*)
      API_PASSWORD="${arg#*=}"
      ;;
    --classroom-id=*)
      CLASSROOM_ID="${arg#*=}"
      ;;
    --academic-year-id=*)
      ACADEMIC_YEAR_ID="${arg#*=}"
      ;;
    --dry-run)
      DRY_RUN="true"
      ;;
    --close-term)
      CLOSE_TERM="true"
      ;;
    --close-notes=*)
      CLOSE_NOTES="${arg#*=}"
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

if ! command -v docker >/dev/null 2>&1; then
  echo "Erreur: docker est requis."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Erreur: curl est requis."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Erreur: python3 est requis."
  exit 1
fi

echo "[preflight] Cible runtime: backend Docker + MySQL du service db"
echo "[preflight] Parametres: etab_id=${ETAB_ID} term=${TERM} terms=${TERMS:-<none>} seed=${SEED} dry_run=${DRY_RUN} close_term=${CLOSE_TERM}"

cd "$INFRA_DIR"
docker compose up -d db backend >/dev/null

echo "[preflight] Compteurs SQL avant injection"
docker compose exec -T db mysql -ugestion_user -pgestion_password -D gestion_school -e "
SELECT COUNT(*) AS grades_before
FROM school_grade g
JOIN school_classroom c ON c.id=g.classroom_id
WHERE c.etablissement_id=${ETAB_ID} AND g.term='${TERM}';
SELECT COUNT(*) AS exam_results_before
FROM school_examresult er
JOIN school_student s ON s.id=er.student_id
JOIN school_examsession es ON es.id=er.session_id
WHERE s.etablissement_id=${ETAB_ID} AND es.term='${TERM}';
"

echo "[apply] Execution de la commande Django dans le conteneur backend"
if [[ -n "$TERMS" ]]; then
  IFS=',' read -r -a TERM_LIST <<< "$TERMS"
else
  TERM_LIST=("$TERM")
fi

for CURRENT_TERM in "${TERM_LIST[@]}"; do
  CURRENT_TERM="$(echo "$CURRENT_TERM" | xargs)"
  if [[ -z "$CURRENT_TERM" ]]; then
    continue
  fi

  RUNTIME_CMD="cd /app && python manage.py seed_term_scores --etab-id ${ETAB_ID} --term ${CURRENT_TERM} --seed ${SEED}"
  if [[ "$DRY_RUN" == "true" ]]; then
    RUNTIME_CMD+=" --dry-run"
  fi
  if [[ "$CLOSE_TERM" == "true" ]]; then
    RUNTIME_CMD+=" --close-term --close-notes \"${CLOSE_NOTES}\""
  fi

  echo "[apply] term=${CURRENT_TERM}"
  docker compose exec -T backend sh -lc "$RUNTIME_CMD"
done

echo "[postflight] Compteurs SQL après execution"
docker compose exec -T db mysql -ugestion_user -pgestion_password -D gestion_school -e "
SELECT COUNT(*) AS grades_after
FROM school_grade g
JOIN school_classroom c ON c.id=g.classroom_id
WHERE c.etablissement_id=${ETAB_ID} AND g.term IN ('T1','T2','T3');
SELECT COUNT(*) AS exam_results_after
FROM school_examresult er
JOIN school_student s ON s.id=er.student_id
JOIN school_examsession es ON es.id=er.session_id
WHERE s.etablissement_id=${ETAB_ID} AND es.term IN ('T1','T2','T3');
"

echo "[postflight] Verification API /grades/"
TOKEN="$({
  curl -sS -X POST "${API_BASE_URL}/auth/login/" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"${API_USERNAME}\",\"password\":\"${API_PASSWORD}\"}"
} | python3 -c "import sys, json; print(json.load(sys.stdin).get('access',''))")"

if [[ -z "$TOKEN" ]]; then
  echo "Erreur: impossible d'obtenir un token API pour la verification."
  exit 1
fi

CHECK_TERM="$TERM"
if [[ -n "$TERMS" ]]; then
  CHECK_TERM="$(echo "$TERMS" | cut -d',' -f1 | xargs)"
fi

curl -sS "${API_BASE_URL}/grades/?classroom=${CLASSROOM_ID}&academic_year=${ACADEMIC_YEAR_ID}&term=${CHECK_TERM}&ordering=-id&page=1&page_size=5" \
  -H "Authorization: Bearer ${TOKEN}" |
  python3 -c "import sys, json; data=json.load(sys.stdin); rows=data.get('results', []); print({'term_checked': '${CHECK_TERM}', 'count': data.get('count'), 'sample_ids': [row.get('id') for row in rows], 'sample_values': [row.get('value') for row in rows]})"

echo "[done] Verification terminee"