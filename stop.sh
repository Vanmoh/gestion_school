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
    echo "Astuce: exécutez ./stop.sh avec sudo ou activez l'accès Docker pour votre utilisateur."
    exit 1
  fi
fi

docker_compose() {
  "${DOCKER_CMD[@]}" compose "$@"
}

cd "$INFRA_DIR"
echo "Arrêt des services Docker Compose..."
docker_compose down

echo "Services arrêtés ✅"
