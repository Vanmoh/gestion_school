#!/bin/sh
set -e

# Aucune image memoire sur disque.
#
# Gunicorn envoie SIGABRT au worker qui depasse son --timeout. Avec une limite
# de core illimitee, chaque expiration ecrivait tout l'espace memoire du
# processus dans /app: SECRET_KEY, identifiants de base et jetons en transit,
# en clair, par tranches de 10 a 170 Mo. Ces fichiers n'ont jamais servi a
# personne -- ils ne sont meme pas lisibles sans debogueur -- et le repertoire
# est monte depuis l'hote en developpement.
ulimit -c 0 2>/dev/null || true

if [ "$1" = "gunicorn" ]; then
	python manage.py migrate --noinput
	python manage.py collectstatic --noinput
fi

exec "$@"
