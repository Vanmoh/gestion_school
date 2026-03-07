#!/usr/bin/env sh
set -e

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is missing."
  echo "Set DATABASE_URL in Render Environment using your Supabase pooler URL."
  exit 1
fi

mkdir -p logs || true
touch logs/app.log || true

python manage.py migrate --noinput
python manage.py collectstatic --noinput

exec gunicorn config.wsgi:application \
  --bind 0.0.0.0:${PORT:-8000} \
  --workers ${WEB_CONCURRENCY:-3} \
  --timeout 120
