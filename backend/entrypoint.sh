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

	# Les statiques sont figes dans l'image (voir Dockerfile): les recalculer
	# ici coutait une minute a chaque reveil du service pour reproduire a
	# l'identique ce que le build avait deja produit.
	#
	# Le repli couvre le developpement, ou /app est monte depuis l'hote et
	# masque le repertoire construit dans l'image.
	if [ ! -f staticfiles/staticfiles.json ]; then
		python manage.py collectstatic --noinput
	fi

	# Le catalogue du fonds documentaire, confie au worker.
	#
	# Le service web ne lit plus les neuf pages de bkalan.ml lui-meme: il
	# depose un message dans la file et rend la main. La source peut etre
	# lente ou muette, cela ne coute plus le temps de personne -- le worker
	# Celery ne sert aucune requete, contrairement a ce processus.
	#
	# Le message part quand meme en tache de fond: joindre le courtier reste
	# un acces reseau, et le demarrage de l'API n'a pas a l'attendre.
	#
	# La commande ne rend jamais d'erreur bloquante: un courtier injoignable
	# laisse le catalogue vide, l'API relaie alors la source, et la tache
	# planifiee rattrape au passage suivant.
	if [ "${LIBRARY_AUTO_IMPORT:-True}" = "True" ]; then
		(
			timeout 60 python manage.py queue_library_catalogue \
				|| echo "Bibliotheque: catalogue non demande (file de travaux injoignable)."
		) &
	fi
fi

exec "$@"
