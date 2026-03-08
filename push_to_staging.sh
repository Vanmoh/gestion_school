#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

REMOTE="origin"
TARGET_BRANCH="staging"
SOURCE_BRANCH=""
AUTO_YES=0

usage() {
  cat <<'EOF'
Usage:
  ./push_to_staging.sh [options]

Options:
  --remote=<name>      Remote Git (default: origin)
  --source=<branch>    Branche source à envoyer vers staging (default: branche courante)
  --target=<branch>    Branche cible (default: staging)
  -y, --yes            Ne pas demander de confirmation
  -h, --help           Afficher cette aide

Exemples:
  ./push_to_staging.sh
  ./push_to_staging.sh --source=feature/students -y
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

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$SOURCE_BRANCH" ]]; then
  SOURCE_BRANCH="$CURRENT_BRANCH"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Erreur: le working tree n'est pas propre."
  echo "Commit/stash tes changements avant d'envoyer vers $TARGET_BRANCH."
  git status --short
  exit 1
fi

if ! git show-ref --verify --quiet "refs/heads/$SOURCE_BRANCH"; then
  echo "Erreur: branche locale introuvable: $SOURCE_BRANCH"
  exit 1
fi

echo "[1/6] Récupération des branches distantes..."
git fetch "$REMOTE" "$TARGET_BRANCH"

if ! git show-ref --verify --quiet "refs/remotes/$REMOTE/$TARGET_BRANCH"; then
  echo "Erreur: branche distante introuvable: $REMOTE/$TARGET_BRANCH"
  echo "Astuce: crée d'abord la branche distante avec: git push -u $REMOTE $TARGET_BRANCH"
  exit 1
fi

if [[ "$AUTO_YES" -ne 1 ]]; then
  echo
  echo "Cette action va exécuter:"
  echo "  1) checkout $TARGET_BRANCH"
  echo "  2) pull --rebase $REMOTE/$TARGET_BRANCH"
  if [[ "$SOURCE_BRANCH" != "$TARGET_BRANCH" ]]; then
    echo "  3) merge --no-ff $SOURCE_BRANCH"
  else
    echo "  3) (pas de merge: source = cible)"
  fi
  echo "  4) push $REMOTE $TARGET_BRANCH"
  echo
  read -r -p "Confirmer l'envoi vers $TARGET_BRANCH ? (yes/no): " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "Annulé."
    exit 0
  fi
fi

echo "[2/6] Checkout $TARGET_BRANCH..."
git checkout "$TARGET_BRANCH"

echo "[3/6] Mise à jour locale de $TARGET_BRANCH..."
git pull --rebase "$REMOTE" "$TARGET_BRANCH"

if [[ "$SOURCE_BRANCH" != "$TARGET_BRANCH" ]]; then
  echo "[4/6] Merge de $SOURCE_BRANCH vers $TARGET_BRANCH..."
  git merge --no-ff "$SOURCE_BRANCH" -m "Push $SOURCE_BRANCH to $TARGET_BRANCH"
else
  echo "[4/6] Merge ignoré (source = cible)."
fi

echo "[5/6] Push vers $REMOTE/$TARGET_BRANCH..."
git push "$REMOTE" "$TARGET_BRANCH"

echo "[6/6] Envoi vers $TARGET_BRANCH terminé ✅"
echo "Dernier commit sur $TARGET_BRANCH: $(git rev-parse --short HEAD)"

if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
  echo "Retour sur la branche initiale: $CURRENT_BRANCH"
  git checkout "$CURRENT_BRANCH"
fi
