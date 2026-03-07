#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
MODE="text"

if [[ "${1:-}" == "--json" ]]; then
  MODE="json"
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  echo "Usage: ./status.sh [--json]"
  exit 0
fi

bool() {
  if [[ "$1" == "1" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

ok_or_ko() {
  if [[ "$1" == "1" ]]; then
    echo "OK"
  else
    echo "KO"
  fi
}

docker_installed=1
docker_daemon=1
DOCKER_CMD=(docker)

if ! command -v docker >/dev/null 2>&1; then
  docker_installed=0
fi

if [[ "$docker_installed" == "1" ]] && ! "${DOCKER_CMD[@]}" info >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo -n docker)
  else
    docker_daemon=0
  fi
fi

docker_compose() {
  "${DOCKER_CMD[@]}" compose "$@"
}

if [[ "$MODE" == "json" ]]; then
  if [[ "$docker_installed" == "0" || "$docker_daemon" == "0" ]]; then
    echo "{\"docker_installed\":$(bool "$docker_installed"),\"docker_daemon\":$(bool "$docker_daemon"),\"error\":\"docker_unavailable\"}"
    exit 1
  fi
else
  if [[ "$docker_installed" == "0" ]]; then
    echo "Erreur: Docker n'est pas installé."
    exit 1
  fi

  if [[ "$docker_daemon" == "0" ]]; then
    echo "Docker daemon: indisponible"
    echo "Astuce: exécutez ./status.sh avec sudo ou activez l'accès Docker pour votre utilisateur."
    exit 1
  fi
fi

cd "$INFRA_DIR"

api_docs=0
api_schema=0
mysql_ok=0
redis_ok=0
django_ok=0
curl_installed=0
service_total=$(docker_compose ps --services 2>/dev/null | wc -l | tr -d ' ')
service_running=$(docker_compose ps --status running --services 2>/dev/null | wc -l | tr -d ' ')

if command -v curl >/dev/null 2>&1; then
  curl_installed=1
  if curl -fsS --max-time 15 "http://localhost:8000/api/docs/" >/dev/null 2>&1; then
    api_docs=1
  fi
  if curl -fsS --max-time 20 "http://localhost:8000/api/schema/" >/dev/null 2>&1; then
    api_schema=1
  fi
fi

if timeout 12 docker_compose exec -T db sh -lc 'mysqladmin ping -h localhost -uroot --password="$MYSQL_ROOT_PASSWORD"' >/dev/null 2>&1; then
  mysql_ok=1
fi

if docker_compose exec -T redis redis-cli ping >/dev/null 2>&1; then
  redis_ok=1
fi

if docker_compose exec -T backend python manage.py check >/dev/null 2>&1; then
  django_ok=1
fi

if [[ "$MODE" == "json" ]]; then
  echo "{\"docker_installed\":$(bool "$docker_installed"),\"docker_daemon\":$(bool "$docker_daemon"),\"services\":{\"total\":$service_total,\"running\":$service_running},\"http\":{\"curl_installed\":$(bool "$curl_installed"),\"api_docs\":$(bool "$api_docs"),\"api_schema\":$(bool "$api_schema")},\"internals\":{\"mysql\":$(bool "$mysql_ok"),\"redis\":$(bool "$redis_ok"),\"django_check\":$(bool "$django_ok")}}"
  exit 0
fi

echo "=== Docker Compose Services ==="
docker_compose ps

echo
echo "=== API Checks ==="
if [[ "$curl_installed" == "1" ]]; then
  echo "API docs: $(ok_or_ko "$api_docs") (http://localhost:8000/api/docs/)"
  echo "API schema: $(ok_or_ko "$api_schema")"
else
  echo "curl non installé: checks HTTP ignorés"
fi

echo
echo "=== Service Internals ==="
echo "MySQL: $(ok_or_ko "$mysql_ok")"
echo "Redis: $(ok_or_ko "$redis_ok")"
echo "Django check: $(ok_or_ko "$django_ok")"
