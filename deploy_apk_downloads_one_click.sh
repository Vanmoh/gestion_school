#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT_DIR/frontend/gestion_school_app"
DOWNLOADS_DIR="$ROOT_DIR/downloads_site"
INDEX_FILE="$DOWNLOADS_DIR/index.html"
APK_BUILD_FILE="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
APK_PUBLISHED_FILE="$DOWNLOADS_DIR/Gestion School.apk"
REMOTE="origin"
AUTO_YES=0
DO_CLEAN=0
API_URL=""
COMMIT_MESSAGE=""
RELEASE_VERSION=""

usage() {
  cat <<'EOF'
Usage:
  ./deploy_apk_downloads_one_click.sh [options]

Options:
  --api-url=<url>        API URL pour le build APK (transmis a build_apk.sh)
  --clean                Force flutter clean avant build APK
  --message="..."        Message de commit (defaut: genere automatiquement)
  --release=<version>    Version de release pour downloads_site/index.html
  --remote=<name>        Remote Git (defaut: origin)
  -y, --yes              Ne pas demander de confirmation
  -h, --help             Afficher l'aide

Exemples:
  ./deploy_apk_downloads_one_click.sh -y
  ./deploy_apk_downloads_one_click.sh --api-url=https://gestion-school-jkzf.onrender.com/api -y
  ./deploy_apk_downloads_one_click.sh --clean --release=2026-03-13-r2 -y
EOF
}

for arg in "$@"; do
  case "$arg" in
    --api-url=*)
      API_URL="${arg#*=}"
      ;;
    --clean)
      DO_CLEAN=1
      ;;
    --message=*)
      COMMIT_MESSAGE="${arg#*=}"
      ;;
    --release=*)
      RELEASE_VERSION="${arg#*=}"
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

if ! command -v git >/dev/null 2>&1; then
  echo "Erreur: git est requis."
  exit 1
fi

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Erreur: ce script doit etre execute dans le depot gestion_school."
  exit 1
fi

if [[ ! -x "$ROOT_DIR/build_apk.sh" ]]; then
  echo "Erreur: script introuvable ou non executable: $ROOT_DIR/build_apk.sh"
  exit 1
fi

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Erreur: fichier introuvable: $INDEX_FILE"
  exit 1
fi

CURRENT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Erreur: branche courante introuvable."
  exit 1
fi

# Keep deployments predictable and avoid committing unrelated local work.
# Ignore this script when it is the only untracked file during first-run setup.
WORKTREE_STATUS="$(git -C "$ROOT_DIR" status --porcelain)"
if [[ -n "$WORKTREE_STATUS" ]]; then
  # Allow a tiny set of known local/generated untracked paths.
  FILTERED_STATUS="$(printf '%s\n' "$WORKTREE_STATUS" | grep -vE '^\?\? (deploy_apk_downloads_one_click\.sh|frontend/gestion_school_app/android/\.kotlin(/.*)?|frontend/gestion_school_app/android/\.gradle(/.*)?)$' || true)"
  if [[ -n "$FILTERED_STATUS" ]]; then
    echo "Erreur: le working tree n'est pas propre."
    echo "Commit/stash tes changements avant de lancer ce script."
    git -C "$ROOT_DIR" status --short
    exit 1
  fi
fi

if [[ -z "$RELEASE_VERSION" ]]; then
  RELEASE_VERSION="$(date -u +'%Y-%m-%d-r%H%M%S')"
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

push_branch() {
  local branch="$1"
  if git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
    git -C "$ROOT_DIR" push
  else
    git -C "$ROOT_DIR" push -u "$REMOTE" "$branch"
  fi
}

echo "[1/8] Build APK release..."
BUILD_ARGS=("release")
if [[ "$DO_CLEAN" -eq 1 ]]; then
  BUILD_ARGS+=("--clean")
fi
if [[ -n "$API_URL" ]]; then
  BUILD_ARGS+=("--api-url=$API_URL")
fi
"$ROOT_DIR/build_apk.sh" "${BUILD_ARGS[@]}"

if [[ ! -f "$APK_BUILD_FILE" ]]; then
  echo "Erreur: APK build non trouve: $APK_BUILD_FILE"
  exit 1
fi

echo "[2/8] Publication APK vers downloads_site..."
mkdir -p "$DOWNLOADS_DIR"
cp "$APK_BUILD_FILE" "$APK_PUBLISHED_FILE"

echo "[3/8] Mise a jour version release dans index downloads..."
sed -i -E "s/(const releaseVersion = ')[^']+(')/\\1$RELEASE_VERSION\\2/" "$INDEX_FILE"
sed -i -E "s/(<code id=\"release-version\">)[^<]+(<\\/code>)/\\1$RELEASE_VERSION\\2/" "$INDEX_FILE"

if [[ -z "$COMMIT_MESSAGE" ]]; then
  COMMIT_MESSAGE="Deploy APK downloads $RELEASE_VERSION"
fi

echo "[4/8] Commit des artefacts APK + index..."
git -C "$ROOT_DIR" add "$APK_PUBLISHED_FILE" "$INDEX_FILE"
git -C "$ROOT_DIR" commit -m "$COMMIT_MESSAGE"

if ! confirm "Confirmer le deploiement de cette APK vers production"; then
  echo "Annule."
  exit 0
fi

echo "[5/8] Push de la branche courante ($CURRENT_BRANCH)..."
push_branch "$CURRENT_BRANCH"

if [[ "$CURRENT_BRANCH" == "main" ]]; then
  echo "[6/8] Branche main detectee: deploiement Render prod declenche par push."
elif [[ "$CURRENT_BRANCH" == "staging" ]]; then
  echo "[6/8] Promotion staging -> main..."
  "$ROOT_DIR/promote_staging_to_main.sh" --remote="$REMOTE" --source=staging --target=main -y
else
  echo "[6/8] Synchronisation vers staging..."
  "$ROOT_DIR/push_to_staging.sh" --remote="$REMOTE" --source="$CURRENT_BRANCH" --target=staging -y
  echo "[7/8] Promotion staging -> main..."
  "$ROOT_DIR/promote_staging_to_main.sh" --remote="$REMOTE" --source=staging --target=main -y
fi

if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "staging" ]]; then
  echo "[7/8] Verification references locales..."
else
  echo "[8/8] Verification references locales..."
fi
echo "HEAD main local: $(git -C "$ROOT_DIR" rev-parse --short main)"
echo "HEAD origin/main: $(git -C "$ROOT_DIR" rev-parse --short origin/main)"

echo

echo "✅ APK publiee en one-click."
echo "Lien downloads: https://gestion-school-downloads.onrender.com"
echo "Lien APK direct: https://gestion-school-downloads.onrender.com/Gestion%20School.apk?v=$RELEASE_VERSION"
