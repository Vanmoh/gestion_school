#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

REMOTE="origin"
SOURCE_BRANCH="staging"
TARGET_BRANCH="main"
AUTO_YES=0

usage() {
  cat <<'EOF'
Usage:
  ./promote_staging_to_main.sh [options]

Options:
  --remote=<name>      Remote Git (default: origin)
  --source=<branch>    Branche source (default: staging)
  --target=<branch>    Branche cible (default: main)
  -y, --yes            Ne pas demander de confirmation
  -h, --help           Afficher cette aide

Exemple:
  ./promote_staging_to_main.sh
EOF
}

for arg in "$@"; do
  case "$arg" in
    --remote=*)
      REMOTE="${arg#*=}"
      ;;
    --source=*)
      SOURCE_BRANCH="${arg#*=}"
      ;;
    --target=*)
      TARGET_BRANCH="${arg#*=}"
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

if ! command -v git >/dev/null 2>&1; then
  echo "Erreur: git est requis."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Erreur: ce script doit être exécuté dans un dépôt git."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Erreur: le working tree n'est pas propre."
  echo "Commit/stash tes changements avant de promouvoir staging -> main."
  git status --short
  exit 1
fi

echo "[1/6] Récupération des branches distantes..."
git fetch "$REMOTE" "$SOURCE_BRANCH" "$TARGET_BRANCH"

if ! git show-ref --verify --quiet "refs/remotes/$REMOTE/$SOURCE_BRANCH"; then
  echo "Erreur: branche distante introuvable: $REMOTE/$SOURCE_BRANCH"
  exit 1
fi

if ! git show-ref --verify --quiet "refs/remotes/$REMOTE/$TARGET_BRANCH"; then
  echo "Erreur: branche distante introuvable: $REMOTE/$TARGET_BRANCH"
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
MERGE_FROM="$REMOTE/$SOURCE_BRANCH"

if [[ "$AUTO_YES" -ne 1 ]]; then
  echo
  echo "Cette action va exécuter:"
  echo "  1) checkout $TARGET_BRANCH"
  echo "  2) pull --rebase $REMOTE/$TARGET_BRANCH"
  echo "  3) merge --no-ff $MERGE_FROM"
  echo "  4) push $REMOTE $TARGET_BRANCH"
  echo
  read -r -p "Confirmer la promotion $SOURCE_BRANCH -> $TARGET_BRANCH ? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "Annulé."
    exit 0
  fi
fi

echo "[2/6] Checkout $TARGET_BRANCH..."
git checkout "$TARGET_BRANCH"

echo "[3/6] Mise à jour locale de $TARGET_BRANCH..."
git pull --rebase "$REMOTE" "$TARGET_BRANCH"

echo "[4/6] Merge de $MERGE_FROM vers $TARGET_BRANCH..."
git merge --no-ff "$MERGE_FROM" -m "Promote $SOURCE_BRANCH to $TARGET_BRANCH"

echo "[5/6] Push vers $REMOTE/$TARGET_BRANCH..."
git push "$REMOTE" "$TARGET_BRANCH"

echo "[6/6] Promotion terminée ✅"
echo "Dernier commit sur $TARGET_BRANCH: $(git rev-parse --short HEAD)"

if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
  echo "Retour sur la branche initiale: $CURRENT_BRANCH"
  git checkout "$CURRENT_BRANCH"
fi
