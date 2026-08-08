#!/usr/bin/env bash
#
# Installe gh si besoin, authentifie GitHub, puis pousse la branche courante.
#
# A lancer depuis un vrai terminal: l'authentification GitHub passe par le
# navigateur et reclame une saisie interactive.
#
# Idempotent: chaque etape verifie d'abord si elle a deja ete faite. Relancer
# le script apres un echec reprend a l'etape bloquante, sans rien refaire.
#
#   ./setup_github_push.sh              # pousse la branche courante
#   ./setup_github_push.sh --dry-run    # verifie tout, ne pousse pas

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Option inconnue: $1"; exit 1 ;;
  esac
done

etape() { printf "\n\033[1;34m[%s]\033[0m %s\n" "$1" "$2"; }
ok()    { printf "  \033[0;32mOK\033[0m    %s\n" "$1"; }
info()  { printf "  ...   %s\n" "$1"; }
avert() { printf "  \033[0;33mNOTE\033[0m  %s\n" "$1"; }
echec() { printf "\n\033[0;31mEchec:\033[0m %s\n" "$1"; exit 1; }

# --- 1. Prerequis ----------------------------------------------------------

etape "1/5" "Verification de l'environnement"

for outil in git curl tar; do
  command -v "$outil" >/dev/null 2>&1 || echec "'$outil' est introuvable."
done
ok "git, curl et tar sont presents"

cd "$ROOT_DIR"
git rev-parse --git-dir >/dev/null 2>&1 || echec "$ROOT_DIR n'est pas un depot git."

BRANCHE="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCHE" != "HEAD" ]] || echec "HEAD est detache: place-toi sur une branche."
ok "branche courante: $BRANCHE"

# Le nom d'hote non resolvable fait attendre sudo et parfois gh sur le reseau.
if ! getent hosts "$(hostname)" >/dev/null 2>&1; then
  avert "'$(hostname)' n'est pas resolvable. Si une commande semble bloquee,"
  avert "ajoute cette ligne a /etc/hosts (demande les droits root):"
  avert "    127.0.1.1  $(hostname)"
fi

# --- 2. Installation de gh -------------------------------------------------

etape "2/5" "CLI GitHub (gh)"

export PATH="$BIN_DIR:$PATH"

if command -v gh >/dev/null 2>&1; then
  ok "deja installe: $(gh --version | head -1)"
else
  info "absent des depots apt sans droits root: installation du binaire officiel"

  case "$(uname -m)" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)       echec "Architecture non geree: $(uname -m)" ;;
  esac

  VERSION="$(curl -fsSL -m 30 https://api.github.com/repos/cli/cli/releases/latest \
    | grep -oP '"tag_name":\s*"v\K[^"]+')" \
    || echec "Impossible de joindre l'API GitHub pour connaitre la derniere version."
  [[ -n "$VERSION" ]] || echec "Version de gh illisible."
  info "version $VERSION"

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  curl -fsSL -m 300 -o "$TMP/gh.tar.gz" \
    "https://github.com/cli/cli/releases/download/v${VERSION}/gh_${VERSION}_linux_${ARCH}.tar.gz" \
    || echec "Telechargement de gh impossible."

  tar xzf "$TMP/gh.tar.gz" -C "$TMP"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$TMP/gh_${VERSION}_linux_${ARCH}/bin/gh" "$BIN_DIR/gh"
  ok "installe dans $BIN_DIR/gh (aucun droit root requis)"
fi

# Le PATH n'est etendu que pour ce script: sans cette ligne dans le profil,
# gh redeviendrait introuvable au prochain terminal.
if ! printf '%s' "${PATH_ORIGINE:-$PATH}" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  for profil in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ -f "$profil" ]] || continue
    if ! grep -q '\.local/bin' "$profil"; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profil"
      ok "PATH complete dans $(basename "$profil")"
    fi
  done
fi

# --- 3. Authentification ---------------------------------------------------

etape "3/5" "Authentification GitHub"

if gh auth status >/dev/null 2>&1; then
  ok "deja authentifie: $(gh api user --jq .login 2>/dev/null || echo 'compte inconnu')"
else
  if [[ ! -t 0 ]]; then
    echec "Aucun terminal interactif. Relance ce script depuis ta console."
  fi

  cat <<'GUIDE'

  Une session de connexion va s'ouvrir. Reponds ceci:

    What account do you want to log into?     GitHub.com
    What is your preferred protocol?          HTTPS
    Authenticate Git with your credentials?   Yes   <-- indispensable pour push
    How would you like to authenticate?       Login with a web browser

  gh affiche un code du type XXXX-XXXX et ouvre github.com/login/device.
  Colle le code dans le navigateur, valide, puis reviens ici.

GUIDE
  gh auth login || echec "Authentification abandonnee ou echouee."
  ok "authentifie: $(gh api user --jq .login 2>/dev/null || echo 'compte inconnu')"
fi

# Branche git sur les identifiants de gh. Sans cela, git push redemande un mot
# de passe que GitHub n'accepte plus depuis 2021.
gh auth setup-git >/dev/null 2>&1 && ok "git utilise les identifiants de gh"

# --- 4. Etat du depot ------------------------------------------------------

etape "4/5" "Etat de la branche"

git remote get-url origin >/dev/null 2>&1 || echec "Aucun remote 'origin' configure."

info "recuperation des references distantes..."
git fetch origin --quiet || echec "fetch impossible: verifie ta connexion."

if git rev-parse --abbrev-ref "@{u}" >/dev/null 2>&1; then
  EN_AVANCE="$(git rev-list --count '@{u}..HEAD')"
  EN_RETARD="$(git rev-list --count 'HEAD..@{u}')"

  if [[ "$EN_RETARD" -gt 0 && "$EN_AVANCE" -gt 0 ]]; then
    echo
    echec "Les historiques ont diverge: $EN_AVANCE commit(s) local/aux, $EN_RETARD distant(s).
Le script ne force rien -- un push force effacerait le travail d'autrui.
Integre d'abord le distant:   git pull --rebase origin $BRANCHE"
  fi

  if [[ "$EN_AVANCE" -eq 0 ]]; then
    ok "rien a pousser, la branche est a jour"
    exit 0
  fi

  ok "$EN_AVANCE commit(s) a pousser"
  git --no-pager log --oneline '@{u}..HEAD' | sed 's/^/        /'
else
  avert "branche sans amont: elle sera creee sur origin"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  avert "des modifications non commitees restent dans l'arbre (elles ne partiront pas)"
fi

# --- 5. Push ---------------------------------------------------------------

etape "5/5" "Envoi vers origin"

if [[ "$DRY_RUN" -eq 1 ]]; then
  ok "--dry-run: tout est pret, rien n'a ete pousse"
  exit 0
fi

git push --set-upstream origin "$BRANCHE" || echec "Le push a echoue (voir le message ci-dessus)."

DEPOT="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
printf "\n\033[0;32mBranche poussee.\033[0m\n"
if [[ -n "$DEPOT" ]]; then
  printf "Ouvrir une pull request:\n  gh pr create --fill\n  https://github.com/%s/pull/new/%s\n" \
    "$DEPOT" "$BRANCHE"
fi
