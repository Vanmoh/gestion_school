#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/frontend/gestion_school_app/build/linux/x64/release/bundle/gestion_school_app"

if [[ ! -x "$APP_PATH" ]]; then
  echo "Binaire introuvable: $APP_PATH"
  echo "Lance d'abord: cd frontend/gestion_school_app && flutter build linux"
  exit 1
fi

exec "$APP_PATH"
