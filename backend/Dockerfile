ARG PYTHON_BASE_IMAGE=python:3.12-slim
FROM ${PYTHON_BASE_IMAGE}

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_DEFAULT_TIMEOUT=180
ENV PIP_RETRIES=15

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential default-libmysqlclient-dev libpq-dev pkg-config mariadb-client postgresql-client libcairo2-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip setuptools wheel \
    && pip install --prefer-binary --retries ${PIP_RETRIES} --timeout ${PIP_DEFAULT_TIMEOUT} -r requirements.txt

COPY . .

# Fichiers statiques figes dans l'image, et non recalculs au demarrage.
#
# CompressedManifestStaticFilesStorage empreinte et compresse 633 fichiers
# (admin Django, DRF, drf-spectacular). C'est du travail identique a chaque
# execution, pour un contenu qui ne change qu'avec l'image -- mais l'entrypoint
# est rejoue a chaque reveil du service, pas seulement a chaque deploiement.
# Sur les 0,1 CPU du plan gratuit Render, cela retardait la premiere reponse
# d'une bonne minute apres chaque mise en veille.
#
# Aucune variable n'est necessaire ici: sans DEBUG, les settings basculent sur
# leurs valeurs de developpement, et collectstatic ne touche pas la base.
RUN python manage.py collectstatic --noinput

RUN chmod +x /app/entrypoint.sh

# Le nombre de workers passe par WEB_CONCURRENCY, que gunicorn lit nativement:
# un CMD en forme exec n'interpole aucune variable, l'ecrire en dur ci-dessous
# imposerait de reconstruire l'image pour l'ajuster.
#
# 2 et non 3: chaque worker uvicorn charge Django en entier, soit ~180 Mo. Sur
# les 512 Mo du plan gratuit, un troisieme worker ne tenait qu'en repoussant
# les deux autres vers le swap -- toutes les requetes ralentissaient pour une
# concurrence qui n'a jamais servi.
ENV WEB_CONCURRENCY=2

ENTRYPOINT ["sh", "/app/entrypoint.sh"]
# ASGI et non WSGI: le chat temps reel passe par Channels (config/asgi.py).
# Servi en WSGI, la route websocket n'existe tout simplement pas et chaque
# tentative de connexion echoue cote client.
CMD ["gunicorn", "config.asgi:application", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000", "--timeout", "120"]
