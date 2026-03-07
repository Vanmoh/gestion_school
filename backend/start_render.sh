#!/usr/bin/env sh
set -e

if [ -z "${DATABASE_URL:-}" ] && [ -n "${database_url:-}" ]; then
  export DATABASE_URL="${database_url}"
fi

if [ -z "${DATABASE_URL:-}" ] && [ -n "${DB_URL:-}" ]; then
  export DATABASE_URL="${DB_URL}"
fi

if [ -z "${DATABASE_URL:-}" ] && [ -n "${POSTGRES_URL:-}" ]; then
  export DATABASE_URL="${POSTGRES_URL}"
fi

if [ -z "${DATABASE_URL:-}" ] && [ -n "${SUPABASE_DATABASE_URL:-}" ]; then
  export DATABASE_URL="${SUPABASE_DATABASE_URL}"
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is missing."
  echo "Set DATABASE_URL (or DB_URL / POSTGRES_URL / SUPABASE_DATABASE_URL) in Render Environment."
  echo "Render: Service -> Environment -> Add Environment Variable"
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
