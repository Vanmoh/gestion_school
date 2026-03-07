#!/bin/sh
set -e

if [ "$1" = "gunicorn" ]; then
	python manage.py migrate --noinput
	python manage.py collectstatic --noinput
fi

exec "$@"
