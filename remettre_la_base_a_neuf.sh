#!/usr/bin/env bash
# Remettre la base locale a neuf: vide, migree, rien d'autre.
#
# « A neuf » veut dire ceci, et rien de plus: le volume PostgreSQL est detruit,
# recree, migre. Il ne reste que ce que les migrations posent -- les quatre
# etablissements reels, sans une seule classe, sans un seul eleve, sans un seul
# compte. Aucune donnee de demonstration: `reset.sh` en seme, celui-ci non.
#
# C'est destructif et irreversible. Trois garde-fous, dont deux structurels:
#
#   1. la base visee doit etre locale. Le script lit `DATABASE_URL` et refuse
#      tout hote qui n'est pas 127.0.0.1, localhost ou le service `postgres`.
#      C'est la garantie la plus forte: elle ne depend d'aucune vigilance;
#   2. la confirmation se tape en clair -- le nom de la base, pas « oui »;
#   3. l'inventaire de ce qui va disparaitre s'affiche avant la question. On ne
#      confirme pas une suppression sans savoir ce qu'elle emporte.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_PYTHON="$ROOT_DIR/.venv/bin/python"

AUTO_YES=0
AVEC_ADMIN=1
MOT_DE_PASSE=""
PUIS_PEUPLER=0

usage() {
  cat <<'EOF'
Usage:
  ./remettre_la_base_a_neuf.sh [options]

Detruit le volume PostgreSQL local, le recree et applique les migrations. Il ne
reste que les quatre etablissements reels, vides: ni classe, ni eleve, ni note,
ni frais, ni compte -- sauf le superadmin, sans lequel on ne pourrait pas
ouvrir le site.

Options:
  --sans-admin            Ne pas creer de superadmin (le site sera inaccessible)
  --mot-de-passe=<mdp>    Mot de passe du superadmin (defaut: tire au hasard)
  --puis-peupler          Enchainer ./peupler_les_quatre_ecoles.sh
  -y, --yes               Ne pas demander confirmation (pour un script)
  -h, --help              Afficher cette aide

Exemples:
  ./remettre_la_base_a_neuf.sh
  ./remettre_la_base_a_neuf.sh --puis-peupler
  ./remettre_la_base_a_neuf.sh --mot-de-passe='...' -y --puis-peupler
EOF
}

for argument in "$@"; do
  case "$argument" in
    --sans-admin) AVEC_ADMIN=0 ;;
    --mot-de-passe=*) MOT_DE_PASSE="${argument#*=}" ;;
    --puis-peupler) PUIS_PEUPLER=1 ;;
    -y|--yes) AUTO_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $argument"; echo; usage; exit 1 ;;
  esac
done

etape() { echo; echo "==> $*"; }

# --- Garde-fou 1: la base doit etre locale -----------------------------------
URL="$(grep -E '^DATABASE_URL=' "$BACKEND_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
if [[ -z "$URL" ]]; then
  echo "Erreur: DATABASE_URL absent de backend/.env -- impossible de verifier"
  echo "que la base visee est bien locale. Refus."
  exit 1
fi

# L'hote se lit entre le dernier « @ » et le « / » ou le « : » qui suit.
HOTE="$(printf '%s' "$URL" | sed -E 's#^.*@([^/:]+).*$#\1#')"
BASE="$(printf '%s' "$URL" | sed -E 's#^.*/([^/?]+)(\?.*)?$#\1#')"
case "$HOTE" in
  127.0.0.1|localhost|::1|postgres|gestion_school_pg) ;;
  *)
    echo "Refus: DATABASE_URL pointe « $HOTE », qui n'est pas une base locale."
    echo "Ce script ne detruit que le PostgreSQL du poste de developpement."
    exit 1
    ;;
esac

# --- Docker ------------------------------------------------------------------
DOCKER_CMD=(docker)
if ! command -v docker >/dev/null 2>&1; then
  echo "Erreur: Docker n'est pas installe."
  exit 1
fi
if ! "${DOCKER_CMD[@]}" info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo -n docker)
  else
    echo "Erreur: le demon Docker est injoignable."
    exit 1
  fi
fi
docker_compose() { (cd "$INFRA_DIR" && "${DOCKER_CMD[@]}" compose "$@"); }

manage_hote() { (cd "$BACKEND_DIR" && "$VENV_PYTHON" -u manage.py "$@"); }

# --- Garde-fou 3: l'inventaire avant la question -----------------------------
etape "Ce qui va disparaitre"
if [[ -x "$VENV_PYTHON" ]] && docker_compose ps --status running postgres 2>/dev/null | grep -q postgres; then
  manage_hote shell -c "
from apps.accounts.models import User
from apps.school.models import Etablissement, ClassRoom, Student, Grade, Payment
print(f'    etablissements {Etablissement.objects.count()}')
print(f'    classes        {ClassRoom.objects.count()}')
print(f'    eleves         {Student.objects.count()}')
print(f'    notes          {Grade.objects.count()}')
print(f'    paiements      {Payment.objects.count()}')
print(f'    comptes        {User.objects.count()}')
" 2>/dev/null || echo "    (base illisible: elle sera recreee de toute facon)"
else
  echo "    (PostgreSQL arrete: inventaire impossible)"
fi

# --- Garde-fou 2: la confirmation en clair -----------------------------------
if [[ "$AUTO_YES" -ne 1 ]]; then
  echo
  echo "ATTENTION: le volume PostgreSQL « pg_data » va etre detruit."
  echo "Cette action est irreversible et n'a pas de sauvegarde automatique."
  read -r -p "Tapez le nom de la base ($BASE) pour confirmer: " reponse
  if [[ "$reponse" != "$BASE" ]]; then
    echo "Annule."
    exit 0
  fi
fi

etape "Arret de la stack et suppression du volume"
docker_compose down --remove-orphans
# Le volume seul, et non `down -v`: celui-ci emporterait aussi `mysql_data`,
# que le compose conserve exprès pour ne pas detruire l'ancienne base.
VOLUME="$("${DOCKER_CMD[@]}" volume ls --format '{{.Name}}' | grep -E '_pg_data$' | head -1 || true)"
if [[ -n "$VOLUME" ]]; then
  "${DOCKER_CMD[@]}" volume rm "$VOLUME"
  echo "    volume $VOLUME supprime"
else
  echo "    aucun volume pg_data a supprimer"
fi

etape "Recreation du PostgreSQL"
docker_compose up -d postgres
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

if [[ ! -x "$VENV_PYTHON" ]]; then
  echo "Erreur: $VENV_PYTHON est absent -- impossible de migrer depuis l'hote."
  exit 1
fi

etape "Application des migrations"
manage_hote migrate --noinput

if [[ "$AVEC_ADMIN" -eq 1 ]]; then
  etape "Creation du superadmin"
  if [[ -z "$MOT_DE_PASSE" ]]; then
    # Tire au hasard, affiche une seule fois: un mot de passe ecrit dans un
    # script finit dans l'historique du depot.
    MOT_DE_PASSE="$("$VENV_PYTHON" -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(16)))")"
    GENERE=1
  else
    GENERE=0
  fi
  MOT_DE_PASSE="$MOT_DE_PASSE" manage_hote shell -c "
import os
from apps.accounts.models import User, UserRole
compte, cree = User.objects.get_or_create(
    username='superadmin',
    defaults={'role': UserRole.SUPER_ADMIN, 'first_name': 'Super', 'last_name': 'Admin'},
)
compte.role = UserRole.SUPER_ADMIN
compte.is_staff = True
compte.is_superuser = True
compte.is_active = True
compte.set_password(os.environ['MOT_DE_PASSE'])
compte.save()
print('    superadmin ' + ('cree' if cree else 'mis a jour'))
"
fi

etape "Etat de la base neuve"
manage_hote shell -c "
from apps.accounts.models import User
from apps.school.models import Etablissement, ClassRoom, Student, Grade
print('    etablissements :', list(Etablissement.objects.order_by('id').values_list('name', flat=True)))
print(f'    classes {ClassRoom.objects.count()} | eleves {Student.objects.count()} | notes {Grade.objects.count()} | comptes {User.objects.count()}')
"

if [[ "$AVEC_ADMIN" -eq 1 && "${GENERE:-0}" -eq 1 ]]; then
  cat <<EOF

===========================================================================
Superadmin: superadmin
Mot de passe: $MOT_DE_PASSE

Ce mot de passe est affiche une seule fois et n'est ecrit nulle part.
Notez-le maintenant, ou relancez avec --mot-de-passe=...
===========================================================================
EOF
fi

if [[ "$PUIS_PEUPLER" -eq 1 ]]; then
  etape "Enchainement du peuplement"
  exec "$ROOT_DIR/peupler_les_quatre_ecoles.sh"
fi

echo
echo "Base a neuf. Pour la peupler: ./peupler_les_quatre_ecoles.sh"
