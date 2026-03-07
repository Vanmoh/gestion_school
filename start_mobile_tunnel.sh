#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/van/Documents/gestion_school"

cd "$ROOT_DIR"

echo "[1/3] Vérification backend local..."
if ! curl -sS --max-time 5 "http://127.0.0.1:8000/api/auth/login/" >/dev/null 2>&1; then
  echo "Backend non disponible sur 127.0.0.1:8000"
  echo "Lance d'abord: sudo ./bootstrap.sh"
  exit 1
fi

echo "[2/3] Démarrage tunnel public (Serveo SSH)..."
echo "Garde ce terminal ouvert pendant l'utilisation mobile."

echo "[3/3] URL publique API (copie l'URL affichée + /api dans l'app):"
ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -R 80:localhost:8000 serveo.net
