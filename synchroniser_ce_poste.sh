#!/usr/bin/env bash
#
# Mettre ce poste au niveau de GitHub, sans rien perdre de ce qu'il contient.
#
# Le cas prevu: une copie du dossier faite il y a quelques jours, sur laquelle
# on a peut-etre travaille entre-temps. Le script ne detruit jamais rien --
# il met de cote ce qui traine (`git stash`) et marque la position actuelle
# (branche de sauvegarde) avant de bouger quoi que ce soit.
#
# Il verifie aussi ce que git ne transporte pas: le fichier .env, le venv
# Python, la base PostgreSQL, Flutter, et les migrations en attente. C'est la
# que se logent les pannes qui ressemblent a des donnees perdues.
#
# Usage:
#   ./synchroniser_ce_poste.sh                 # diagnostic + avance si c'est sans risque
#   ./synchroniser_ce_poste.sh --appliquer     # aligne meme s'il faut ecarter du local
#   ./synchroniser_ce_poste.sh --branche=main  # viser une autre branche
#
set -uo pipefail

BRANCHE_PAR_DEFAUT="feat/palette-eleve-droits-edition"
DEPOT_ATTENDU="Vanmoh/gestion_school"

BRANCHE="$BRANCHE_PAR_DEFAUT"
APPLIQUER=0

for arg in "$@"; do
  case "$arg" in
    --branche=*) BRANCHE="${arg#*=}" ;;
    --appliquer|-y) APPLIQUER=1 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argument inconnu: $arg"; exit 1 ;;
  esac
done

ROUGE=$'\033[31m'; VERT=$'\033[32m'; JAUNE=$'\033[33m'; GRAS=$'\033[1m'; NEUTRE=$'\033[0m'
AVERTISSEMENTS=0
BLOCAGES=0

titre()   { printf '\n%s== %s ==%s\n' "$GRAS" "$1" "$NEUTRE"; }
ok()      { printf '  %s✓%s %s\n' "$VERT" "$NEUTRE" "$1"; }
attention() { printf '  %s!%s %s\n' "$JAUNE" "$NEUTRE" "$1"; AVERTISSEMENTS=$((AVERTISSEMENTS+1)); }
bloque()  { printf '  %s✗%s %s\n' "$ROUGE" "$NEUTRE" "$1"; BLOCAGES=$((BLOCAGES+1)); }
info()    { printf '    %s\n' "$1"; }

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$RACINE" || exit 1

# ---------------------------------------------------------------------------
titre "Le depot"
# ---------------------------------------------------------------------------

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bloque "Ce dossier n'est pas un depot git."
  info "La copie a peut-etre ete faite sans le dossier .git."
  info "Dans ce cas: git clone https://github.com/$DEPOT_ATTENDU.git"
  exit 1
fi

URL_ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$URL_ORIGIN" ]]; then
  bloque "Aucun remote 'origin'."
  info "git remote add origin https://github.com/$DEPOT_ATTENDU.git"
  exit 1
elif [[ "$URL_ORIGIN" != *"$DEPOT_ATTENDU"* ]]; then
  attention "origin pointe ailleurs: $URL_ORIGIN"
else
  ok "origin: $URL_ORIGIN"
fi

BRANCHE_LOCALE="$(git branch --show-current 2>/dev/null || echo '(detachee)')"
ok "branche actuelle: $BRANCHE_LOCALE"
ok "position actuelle: $(git log --oneline -1 2>/dev/null || echo 'aucun commit')"

# ---------------------------------------------------------------------------
titre "Ce que ce poste contient et que GitHub n'a pas"
# ---------------------------------------------------------------------------

A_SAUVER=0

MODIFS="$(git status --porcelain)"
if [[ -n "$MODIFS" ]]; then
  attention "Modifications non validees ($(echo "$MODIFS" | wc -l) fichier(s)):"
  echo "$MODIFS" | head -20 | sed 's/^/      /'
  [[ "$(echo "$MODIFS" | wc -l)" -gt 20 ]] && info "... et d'autres"
  A_SAUVER=1
else
  ok "Arbre de travail propre."
fi

git fetch --all --prune --quiet 2>/dev/null || attention "fetch impossible (reseau?)"

NON_POUSSES=""
if git rev-parse --verify "origin/$BRANCHE_LOCALE" >/dev/null 2>&1; then
  NON_POUSSES="$(git log --oneline "origin/$BRANCHE_LOCALE..HEAD" 2>/dev/null)"
fi
if [[ -n "$NON_POUSSES" ]]; then
  attention "Commits locaux jamais pousses:"
  echo "$NON_POUSSES" | sed 's/^/      /'
  A_SAUVER=1
else
  ok "Aucun commit local non pousse."
fi

# ---------------------------------------------------------------------------
titre "Alignement sur GitHub"
# ---------------------------------------------------------------------------

if ! git rev-parse --verify "origin/$BRANCHE" >/dev/null 2>&1; then
  bloque "La branche origin/$BRANCHE n'existe pas."
  info "Branches disponibles:"
  git branch -r | sed 's/^/      /' | head -10
  exit 1
fi

CIBLE="$(git rev-parse --short "origin/$BRANCHE")"
ok "cible: origin/$BRANCHE ($CIBLE) -- $(git log --format='%s' -1 "origin/$BRANCHE")"

# Peut-on avancer sans rien ecarter? Oui si l'arbre est propre, qu'on est sur
# la bonne branche, et que la cible descend de la position actuelle.
AVANCE_SIMPLE=0
if [[ -z "$MODIFS" && "$BRANCHE_LOCALE" == "$BRANCHE" ]] \
   && git merge-base --is-ancestor HEAD "origin/$BRANCHE" 2>/dev/null; then
  AVANCE_SIMPLE=1
fi

if [[ "$(git rev-parse HEAD)" == "$(git rev-parse "origin/$BRANCHE")" && -z "$MODIFS" ]]; then
  ok "Ce poste est deja au niveau de GitHub."
elif [[ "$AVANCE_SIMPLE" -eq 1 ]]; then
  info "Avance directe, rien a ecarter."
  git checkout "$BRANCHE" --quiet 2>/dev/null
  if git merge --ff-only "origin/$BRANCHE" --quiet; then
    ok "Avance jusqu'a $CIBLE."
  else
    bloque "L'avance a echoue."
  fi
elif [[ "$APPLIQUER" -eq 0 ]]; then
  attention "Alignement NON fait: il faudrait ecarter du travail local."
  info "Relancez avec --appliquer. Rien ne sera perdu:"
  info "  - les modifications partent dans un 'git stash' nomme"
  info "  - la position actuelle est marquee par une branche de sauvegarde"
  echo
  info "Ou, pour regarder d'abord ce qui differe:"
  info "  git diff origin/$BRANCHE"
else
  HORODATE="$(date +%Y%m%d-%H%M%S)"

  if [[ "$A_SAUVER" -eq 1 && -n "$NON_POUSSES" ]]; then
    SAUVEGARDE="sauvegarde/${BRANCHE_LOCALE}-$HORODATE"
    if git branch "$SAUVEGARDE" HEAD; then
      ok "Position actuelle marquee: $SAUVEGARDE"
      info "git log $SAUVEGARDE  pour la revoir"
    fi
  fi

  if [[ -n "$MODIFS" ]]; then
    # -u prend les fichiers non suivis mais PAS les ignores: backend/.env
    # et capture_a_corriger/ restent en place.
    #
    # Et le script s'exclut lui-meme: a sa premiere execution sur un poste, il
    # n'est pas encore suivi par git, donc `-u` le rangeait dans le stash --
    # il disparaissait du dossier au milieu de sa propre execution.
    MOI="$(basename "${BASH_SOURCE[0]}")"
    if git stash push -u -m "avant-synchro-$HORODATE" --quiet -- . ":!$MOI"; then
      ok "Modifications mises de cote."
      info "git stash list     pour les voir"
      info "git stash pop      pour les reprendre"
    fi
  fi

  git checkout "$BRANCHE" --quiet 2>/dev/null || git checkout -b "$BRANCHE" "origin/$BRANCHE" --quiet
  if git reset --hard "origin/$BRANCHE" --quiet; then
    ok "Aligne sur origin/$BRANCHE ($CIBLE)."
  else
    bloque "L'alignement a echoue."
  fi
fi

# ---------------------------------------------------------------------------
titre "Ce que git ne transporte pas"
# ---------------------------------------------------------------------------

# --- Le fichier de configuration -------------------------------------------
if [[ -f backend/.env ]]; then
  ok "backend/.env present."
  if ! grep -q "^DATABASE_URL=" backend/.env; then
    attention "backend/.env n'a pas de DATABASE_URL."
  fi
else
  bloque "backend/.env ABSENT -- il est ignore par git, donc jamais transmis."
  info "Recopiez-le depuis l'autre poste. Sans lui, rien ne demarre."
fi

# --- Le venv Python ---------------------------------------------------------
#
# Un venv ne se copie pas d'un poste a l'autre: les lanceurs (pip, django-admin)
# portent en dur le chemin de leur python. Sur le poste d'origine de ce
# depot, `.venv/bin/pip` pointe encore vers /home/van/... et ne demarre pas,
# alors que `.venv/bin/python` -- un vrai binaire -- fonctionne. D'ou les
# controles ci-dessous, qui testent ce qui casse vraiment.
if [[ ! -d .venv ]]; then
  attention ".venv absent."
  info "python3 -m venv .venv"
  info ".venv/bin/python -m pip install -r backend/requirements.txt"
elif ! .venv/bin/python -c "import django" >/dev/null 2>&1; then
  bloque "Le venv existe mais Django ne s'y importe pas."
  info "Le plus sur est de le refaire:"
  info "  rm -rf .venv && python3 -m venv .venv \\"
  info "  && .venv/bin/python -m pip install -r backend/requirements.txt"
else
  VERSION_DJANGO="$(.venv/bin/python -c 'import django; print(django.get_version())' 2>/dev/null)"
  ok "venv fonctionnel (Django ${VERSION_DJANGO:-?})."

  # Les lanceurs pointent-ils bien ici?
  SHEBANG="$(head -1 .venv/bin/pip 2>/dev/null | sed 's|^#!||')"
  if [[ -n "$SHEBANG" && "$SHEBANG" != "$RACINE"/* ]]; then
    attention "Les lanceurs du venv pointent vers un autre chemin:"
    info "  .venv/bin/pip appelle : $SHEBANG"
    info "  ce depot est dans     : $RACINE"
    info "Employez '.venv/bin/python -m pip' plutot que '.venv/bin/pip',"
    info "ou refaites le venv pour que les deux marchent."
  fi

  # Ce que requirements.txt demande, face a ce qui est installe. Sans reseau:
  # un diagnostic ne doit pas dependre de la connexion.
  ECARTS="$(.venv/bin/python - backend/requirements.txt <<'PYTHON' 2>/dev/null
import re, sys
from importlib.metadata import version, PackageNotFoundError

for ligne in open(sys.argv[1], encoding="utf-8"):
    ligne = ligne.split("#")[0].strip()
    if not ligne or ligne.startswith("-"):
        continue
    m = re.match(r"^([A-Za-z0-9._-]+)\s*(?:\[[^\]]*\])?\s*==\s*([^\s;]+)", ligne)
    if not m:
        continue
    nom, attendue = m.group(1), m.group(2)
    try:
        installee = version(nom)
    except PackageNotFoundError:
        print(f"ABSENT {nom} ({attendue} attendu)")
        continue
    if installee != attendue:
        print(f"ECART  {nom}: {installee} installe, {attendue} attendu")
PYTHON
)"
  if [[ -n "$ECARTS" ]]; then
    attention "L'environnement Python ne correspond pas a requirements.txt:"
    echo "$ECARTS" | sed 's/^/      /'
    info "C'est ce que la production installe; un ecart peut faire passer"
    info "un test ici et echouer la-bas."
    info ".venv/bin/python -m pip install -r backend/requirements.txt"
  else
    ok "Dependances Python conformes a requirements.txt."
  fi
fi

# --- La base de donnees -----------------------------------------------------
PORT_BASE="$(grep -m1 '^DATABASE_URL=' backend/.env 2>/dev/null \
             | sed -n 's#.*:\([0-9]\{4,5\}\)/.*#\1#p')"
PORT_BASE="${PORT_BASE:-5432}"
if command -v pg_isready >/dev/null 2>&1; then
  if pg_isready -h 127.0.0.1 -p "$PORT_BASE" >/dev/null 2>&1; then
    ok "PostgreSQL repond sur le port $PORT_BASE."
  else
    bloque "PostgreSQL NE REPOND PAS sur le port $PORT_BASE."
    info "Une base eteinte ressemble a des donnees perdues: l'application"
    info "affiche des listes vides, pas une erreur de connexion."
    info "Demarrez-la avant de conclure quoi que ce soit."
  fi
else
  attention "pg_isready absent: impossible de tester la base."
fi

# --- Les migrations ---------------------------------------------------------
if [[ -d .venv && -f backend/.env ]]; then
  EN_ATTENTE="$(cd backend && ../.venv/bin/python manage.py showmigrations --plan 2>/dev/null \
                | grep -c '^\[ \]' || true)"
  if [[ "${EN_ATTENTE:-0}" -gt 0 ]]; then
    attention "$EN_ATTENTE migration(s) en attente."
    info "cd backend && ../.venv/bin/python manage.py migrate"
  elif [[ -n "${EN_ATTENTE:-}" ]]; then
    ok "Migrations a jour."
  fi
fi

# --- Flutter ----------------------------------------------------------------
if command -v flutter >/dev/null 2>&1; then
  ok "flutter sur le PATH."
elif [[ -x "$HOME/development/flutter/bin/flutter" ]]; then
  attention "flutter hors PATH, mais present."
  info "export PATH=\"\$HOME/development/flutter/bin:\$PATH\""
else
  attention "flutter introuvable: les tests et l'analyse Dart ne tourneront pas."
fi

# --- Ce qui ne se synchronise jamais ---------------------------------------
if [[ -d capture_a_corriger ]]; then
  ok "capture_a_corriger/ present ($(find capture_a_corriger -type f | wc -l) fichier(s))."
else
  attention "capture_a_corriger/ absent -- ce dossier est ignore par git."
  info "Recopiez-le a la main si vous en avez besoin."
fi

# ---------------------------------------------------------------------------
titre "Resume"
# ---------------------------------------------------------------------------

printf '  position : %s\n' "$(git log --oneline -1)"
printf '  branche  : %s\n' "$(git branch --show-current)"
if [[ "$BLOCAGES" -gt 0 ]]; then
  printf '\n  %s%d point(s) bloquant(s)%s et %d avertissement(s).\n' "$ROUGE" "$BLOCAGES" "$NEUTRE" "$AVERTISSEMENTS"
  printf '  Traitez les lignes rouges avant de reprendre le travail.\n'
  exit 2
elif [[ "$AVERTISSEMENTS" -gt 0 ]]; then
  printf '\n  %d avertissement(s), rien de bloquant.\n' "$AVERTISSEMENTS"
else
  printf '\n  %sCe poste est au niveau de GitHub, et son environnement tient.%s\n' "$VERT" "$NEUTRE"
fi
