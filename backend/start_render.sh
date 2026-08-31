#!/usr/bin/env sh
set -e

# Voir entrypoint.sh: un worker abandonne sur timeout ecrirait sinon toute sa
# memoire -- SECRET_KEY et identifiants compris -- dans un fichier core.
ulimit -c 0 2>/dev/null || true

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

# Les controles de deploiement ne tournaient qu'en CI, ou toutes les variables
# sont simulees: une variable reellement absente n'etait donc signalee nulle
# part. Ils sont rejoues ici, la ou la configuration est la vraie.
#
# Volontairement non bloquant: une couche temps reel mal configuree degrade le
# chat, la refuser au demarrage priverait l'ecole de tout le reste. Le detail
# part dans les logs Render, filtre pour ne pas noyer le demarrage sous la
# centaine d'avertissements de documentation de l'API.
echo "--- Controles de deploiement ---"
# Le resultat passe par un fichier plutot que par un tube: si la commande
# echoue (base injoignable, settings casses), un grep sans correspondance
# annoncerait « aucun avertissement » et masquerait la panne.
if python manage.py check --deploy > /tmp/deploy-check.log 2>&1; then
  grep -E '^\?: \((security|gestion_school)\.' /tmp/deploy-check.log \
    || echo "Aucun avertissement de securite ni de configuration projet."
else
  echo "ATTENTION: les controles de deploiement n'ont pas pu s'executer."
  tail -n 20 /tmp/deploy-check.log
fi
echo "--------------------------------"

# ASGI: la route websocket du chat (config/asgi.py) n'est servie que par un
# worker ASGI. En WSGI, l'API repond normalement mais le temps reel est mort.
#
# --timeout 0: le chien de garde de gunicorn compte le temps passe dans une
# requete, et une connexion de chat en est une, ouverte des heures. A 120 s il
# tuait ses propres workers (« WORKER TIMEOUT » puis SIGABRT) en coupant
# toutes les conversations en cours. Le worker uvicorn etant asynchrone, une
# requete lente n'y bloque personne: le garde-fou ne protegeait de rien.
exec gunicorn config.asgi:application \
  -k uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:${PORT:-8000} \
  --workers ${WEB_CONCURRENCY:-3} \
  --timeout 0
