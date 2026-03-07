#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"

if ! command -v docker >/dev/null 2>&1; then
  echo "Erreur: Docker n'est pas installé."
  exit 1
fi

DOCKER_CMD=(docker)

if ! "${DOCKER_CMD[@]}" info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo -n docker)
  else
    echo "Erreur: Docker daemon indisponible ou accès refusé."
    echo "Astuce: exécutez ./reset.sh avec sudo ou activez l'accès Docker pour votre utilisateur."
    exit 1
  fi
fi

docker_compose() {
  "${DOCKER_CMD[@]}" compose "$@"
fi

echo "ATTENTION: cette action va supprimer les conteneurs ET les volumes (données MySQL incluses)."
read -r -p "Tapez RESET pour confirmer: " confirm

if [[ "$confirm" != "RESET" ]]; then
  echo "Annulé."
  exit 0
fi

cd "$INFRA_DIR"
echo "Arrêt et suppression complète de la stack..."
docker_compose down -v --remove-orphans

echo "Reconstruction + redémarrage..."
docker_compose up -d --build

echo "Attente de disponibilité du backend..."
ready=0
for _ in $(seq 1 40); do
  if docker_compose exec -T backend python manage.py check >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 3
done

if [[ "$ready" -ne 1 ]]; then
  echo "Erreur: backend non prêt dans le délai attendu."
  docker_compose logs --tail=200 backend
  exit 1
fi

echo "Application des migrations..."
docker_compose exec -T backend python manage.py migrate --noinput

echo "Injection des données de démonstration..."
docker_compose exec -T backend python manage.py seed_demo_data

echo "Reset terminé ✅"
