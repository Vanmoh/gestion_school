#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000/api}"
TOKEN="${2:-}"
ITERATIONS="${3:-8}"

if [[ -z "$TOKEN" ]]; then
  echo "Usage: ./profile_api.sh <base_url> <jwt_token> [iterations]"
  echo "Example: ./profile_api.sh http://127.0.0.1:8000/api eyJhbGci... 10"
  exit 1
fi

endpoints=(
  "/students/?page_size=80&ordering=-created_at"
  "/payments/?page_size=80"
  "/fees/?page_size=80"
  "/auth/users/?page_size=80"
  "/activity-logs/?page_size=80&ordering=-created_at"
)

echo "Base URL: $BASE_URL"
echo "Iterations: $ITERATIONS"
echo

for ep in "${endpoints[@]}"; do
  echo "=== $ep ==="
  total=0
  min=999999
  max=0

  for ((i=1; i<=ITERATIONS; i++)); do
    ms=$(curl -sS -o /dev/null \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -w "%{time_total}" \
      "$BASE_URL$ep")

    value=$(awk -v t="$ms" 'BEGIN { printf "%d", t * 1000 }')
    total=$((total + value))
    if (( value < min )); then min=$value; fi
    if (( value > max )); then max=$value; fi
    printf "run %02d: %d ms\n" "$i" "$value"
  done

  avg=$((total / ITERATIONS))
  echo "avg: $avg ms | min: $min ms | max: $max ms"
  echo
 done
