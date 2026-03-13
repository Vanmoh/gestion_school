#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

REMOTE="origin"
TARGET="prod"
AUTO_YES=0
PUBLISH_DOWNLOADS=0
COMMIT_MESSAGE=""

usage() {
  cat <<'EOF'
Usage:
  ./deploy_one_click.sh [options]

Options:
  --target=<prod|staging>     Cible de deploiement (defaut: prod)
  --message="..."            Message de commit auto (defaut: genere avec date)
  --publish-downloads         Regenerer/publier les artifacts dans downloads_site avant commit
  --remote=<name>             Remote Git (defaut: origin)
  -y, --yes                   Aucun prompt de confirmation
  -h, --help                  Afficher cette aide

Exemples:
  ./deploy_one_click.sh --target=prod -y
  ./deploy_one_click.sh --target=staging --message="Hotfix UI" -y
  ./deploy_one_click.sh --publish-downloads -y
EOF
}

for arg in "$@"; do
  case "$arg" in
    --target=*)
      TARGET="${arg#*=}"
      ;;
    --message=*)
      COMMIT_MESSAGE="${arg#*=}"
      ;;
    --publish-downloads)
      PUBLISH_DOWNLOADS=1
      ;;
    --remote=*)
      REMOTE="${arg#*=}"
      ;;
    -y|--yes)
      AUTO_YES=1
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

if [[ "$TARGET" != "prod" && "$TARGET" != "staging" ]]; then
  echo "Erreur: --target doit valoir 'prod' ou 'staging'."
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Erreur: git est requis."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Erreur: ce script doit etre execute dans un depot git."
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Erreur: impossible de detecter la branche courante."
  exit 1
fi

confirm() {
  local prompt="$1"
  if [[ "$AUTO_YES" -eq 1 ]]; then
    return 0
  fi

  echo
  read -r -p "$prompt (yes/no): " answer
  [[ "$answer" == "yes" ]]
}

push_current_branch() {
  local branch
  branch="$(git branch --show-current)"
  if [[ -z "$branch" ]]; then
    echo "Erreur: branche courante introuvable pour push."
    exit 1
  fi

  if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    git push
  else
    git push -u "$REMOTE" "$branch"
  fi
}

echo "[One-Click] Branche courante: $CURRENT_BRANCH"
echo "[One-Click] Cible: $TARGET"

if [[ "$PUBLISH_DOWNLOADS" -eq 1 ]]; then
  if [[ ! -x "$ROOT_DIR/publish_downloads_artifacts.sh" ]]; then
    echo "Erreur: script introuvable ou non executable: $ROOT_DIR/publish_downloads_artifacts.sh"
    exit 1
  fi
  echo "[1/5] Publication artifacts downloads..."
  "$ROOT_DIR/publish_downloads_artifacts.sh"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  if [[ -z "$COMMIT_MESSAGE" ]]; then
    COMMIT_MESSAGE="One-click deploy $(date -u +'%Y-%m-%d %H:%M:%SZ')"
  fi

  echo "[2/5] Modifications detectees: creation du commit..."
  git add -A
  git commit -m "$COMMIT_MESSAGE"
else
  echo "[2/5] Aucune modification locale a commit."
fi

if [[ "$TARGET" == "staging" ]]; then
  if ! confirm "Confirmer le deploiement one-click vers staging depuis '$CURRENT_BRANCH'"; then
    echo "Annule."
    exit 0
  fi

  echo "[3/5] Push de la branche courante..."
  push_current_branch

  if [[ "$CURRENT_BRANCH" == "staging" ]]; then
    echo "[4/5] Branche staging deja active: rien a merger."
  else
    echo "[4/5] Synchronisation vers staging via push_to_staging.sh..."
    "$ROOT_DIR/push_to_staging.sh" --remote="$REMOTE" --source="$CURRENT_BRANCH" --target=staging -y
  fi

  echo "[5/5] Termine ✅"
  echo "Staging web: https://gestion-school-staging-web.onrender.com"
  exit 0
fi

# target = prod
if ! confirm "Confirmer le deploiement one-click vers production depuis '$CURRENT_BRANCH'"; then
  echo "Annule."
  exit 0
fi

echo "[3/5] Push de la branche courante..."
push_current_branch

if [[ "$CURRENT_BRANCH" == "main" ]]; then
  echo "[4/5] Main deja a jour: deploiement prod declenche par push main."
elif [[ "$CURRENT_BRANCH" == "staging" ]]; then
  echo "[4/5] Promotion staging -> main..."
  "$ROOT_DIR/promote_staging_to_main.sh" --remote="$REMOTE" --source=staging --target=main -y
else
  echo "[4/5] Etape 1: merge vers staging..."
  "$ROOT_DIR/push_to_staging.sh" --remote="$REMOTE" --source="$CURRENT_BRANCH" --target=staging -y
  echo "[4/5] Etape 2: promotion staging -> main..."
  "$ROOT_DIR/promote_staging_to_main.sh" --remote="$REMOTE" --source=staging --target=main -y
fi

echo "[5/5] Termine ✅"
echo "Production web: https://gestion-school-web.onrender.com"
