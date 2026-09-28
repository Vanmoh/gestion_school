#!/usr/bin/env bash
# Peupler les quatre etablissements reels de A a Z, en un seul appel.
#
# Ce script ne cree rien lui-meme: il enchaine ce que le depot sait deja faire,
# dans le seul ordre ou cela fonctionne, et il **verifie** le resultat. C'est la
# difference qui compte: un peuplement qui se termine sans erreur n'est pas un
# peuplement utilisable. Une base peut porter mille eleves et rester inerte --
# des enseignants sans heures, des familles injoignables, une caisse ou tout est
# paye. `controler_la_dotation` tranche, et ce script echoue si elle echoue.
#
# La base visee est celle du site local: le PostgreSQL du conteneur
# `gestion_school_pg`, que `bootstrap.sh` utilise aussi (le service `backend`
# pointe `postgres:5432`, soit le meme volume `pg_data` que le `127.0.0.1:5433`
# vu depuis l'hote).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_PYTHON="$ROOT_DIR/.venv/bin/python"

ELEVES_PAR_CLASSE=30
PART_NON_SOLDEE=25
GRAINE=2026
ECOLE=""
SANS_NOTES=0
SANS_CONTROLE=0

usage() {
  cat <<'EOF'
Usage:
  ./peupler_les_quatre_ecoles.sh [options]

Monte les quatre etablissements reels de bout en bout: classes, matieres,
eleves, enseignants, emploi du temps, notes des trois trimestres, frais,
encadrement, familles, appel, discipline, bulletins, examens, surveillance,
disponibilites, paie, depenses, bibliotheque, cantine, stock, messagerie,
bilans, emargement, remise des bulletins et conseil de fin d'annee.

Options:
  --ecole=<nom>              N'en monter qu'une, par son nom exact
  --eleves-par-classe=<n>    Effectif vise par classe (defaut 30)
  --part-non-soldee=<n>      % d'eleves n'ayant pas solde (defaut 25)
  --graine=<n>               Graine d'alea: meme graine, meme ecole (defaut 2026)
  --sans-notes               Monter sans saisir les notes (rapide)
  --sans-controle            Ne pas verifier le resultat (deconseille)
  -h, --help                 Afficher cette aide

Exemples:
  ./peupler_les_quatre_ecoles.sh
  ./peupler_les_quatre_ecoles.sh --ecole="IFP-OBK" --eleves-par-classe=10
  ./peupler_les_quatre_ecoles.sh --sans-notes

Relancer ce script est sans danger: la dotation est idempotente, elle ne double
rien. Pour repartir d'une base vide, voir ./remettre_la_base_a_neuf.sh
EOF
}

for argument in "$@"; do
  case "$argument" in
    --ecole=*) ECOLE="${argument#*=}" ;;
    --eleves-par-classe=*) ELEVES_PAR_CLASSE="${argument#*=}" ;;
    --part-non-soldee=*) PART_NON_SOLDEE="${argument#*=}" ;;
    --graine=*) GRAINE="${argument#*=}" ;;
    --sans-notes) SANS_NOTES=1 ;;
    --sans-controle) SANS_CONTROLE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $argument"; echo; usage; exit 1 ;;
  esac
done

etape() { echo; echo "==> $*"; }

# --- Docker ------------------------------------------------------------------
DOCKER_CMD=(docker)
if ! command -v docker >/dev/null 2>&1; then
  echo "Erreur: Docker n'est pas installe -- le PostgreSQL local en depend."
  exit 1
fi
if ! "${DOCKER_CMD[@]}" info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo -n docker)
  else
    echo "Erreur: le demon Docker est injoignable."
    echo "Astuce: relancez avec sudo, ou ajoutez votre utilisateur au groupe docker."
    exit 1
  fi
fi
docker_compose() { (cd "$INFRA_DIR" && "${DOCKER_CMD[@]}" compose "$@"); }

etape "Demarrage du PostgreSQL local"
docker_compose up -d postgres

# `pg_isready` repond des que le serveur ecoute, meme s'il refuse encore la
# base: on attend le healthcheck du compose, qui execute une vraie requete.
printf "    attente du healthcheck"
for _ in $(seq 1 60); do
  etat="$("${DOCKER_CMD[@]}" inspect -f '{{.State.Health.Status}}' gestion_school_pg 2>/dev/null || echo inconnu)"
  [[ "$etat" == "healthy" ]] && break
  printf "."
  sleep 2
done
echo
if [[ "${etat:-}" != "healthy" ]]; then
  echo "Erreur: PostgreSQL n'est pas pret (etat: ${etat:-inconnu})."
  docker_compose logs --tail=40 postgres
  exit 1
fi

# --- Comment lancer manage.py ------------------------------------------------
# Le conteneur `backend` d'abord, quand il tourne: c'est exactement
# l'environnement du site. Sinon le venv de l'hote, qui parle au meme
# PostgreSQL par le port 5433 publie.
if "${DOCKER_CMD[@]}" ps --format '{{.Names}}' | grep -qx gestion_school_backend; then
  echo "    manage.py: conteneur gestion_school_backend"
  manage() { docker_compose exec -T backend python manage.py "$@"; }
elif [[ -x "$VENV_PYTHON" ]]; then
  echo "    manage.py: venv de l'hote ($VENV_PYTHON)"
  manage() { (cd "$BACKEND_DIR" && "$VENV_PYTHON" -u manage.py "$@"); }
else
  echo "Erreur: ni le conteneur backend ni $VENV_PYTHON ne sont disponibles."
  echo "Astuce: lancez ./bootstrap.sh, ou creez le venv du depot."
  exit 1
fi

etape "Application des migrations"
manage migrate --noinput

etape "Montage des etablissements"
dotation=(doter_les_etablissements_reels --forcer
          --eleves-par-classe "$ELEVES_PAR_CLASSE"
          --part-non-soldee "$PART_NON_SOLDEE"
          --graine "$GRAINE")
[[ -n "$ECOLE" ]] && dotation+=(--etablissement "$ECOLE")
[[ "$SANS_NOTES" -eq 1 ]] && dotation+=(--sans-notes)
manage "${dotation[@]}"

if [[ "$SANS_CONTROLE" -eq 1 ]]; then
  etape "Controle passe (--sans-controle)"
else
  etape "Controle: cette base est-elle utilisable ?"
  controle=(controler_la_dotation --part-non-soldee "$PART_NON_SOLDEE")
  [[ -n "$ECOLE" ]] && controle+=(--etablissement "$ECOLE")
  manage "${controle[@]}"
fi

cat <<'EOF'

===========================================================================
Peuplement termine.

Comptes crees, par etablissement -- <code> est le code de l'ecole en
minuscules (lt, lo, io, cs):

  directeur     <code>.dir        Ecole@2026
  censeur       <code>.cen        Ecole@2026
  comptable     <code>.cpt        Ecole@2026
  surveillant   <code>.sur        Ecole@2026
  promoteur     <code>.pro        Ecole@2026
  enseignants   <code>.profNN     Prof@2026
  familles      <code>.parNNN     Parent@2026
  eleves        <code>.<id>.NNN   Eleve@2026

Ces mots de passe sont connus et n'ont de sens qu'en local. Ne montez jamais
cette base pour des utilisateurs reels sans les changer.

Pour ouvrir le site:   ./start_web_lan.sh
Pour repartir de zero: ./remettre_la_base_a_neuf.sh
===========================================================================
EOF
