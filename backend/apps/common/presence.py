"""Qui est en ligne, et depuis quand on ne l'a plus vu.

Trois endroits calculaient la meme chose de trois facons: le serializer du
chat, la vue de presence d'une conversation, et le consumer websocket qui,
lui, se contentait de relire la colonne `is_online` telle quelle. Les trois
partaient du compteur de connexions -- « au moins un socket ouvert, donc en
ligne ».

Ce compteur ment des qu'un socket meurt sans prevenir: navigateur ferme d'un
coup, wifi coupe, serveur redemarre. `disconnect()` n'est jamais appele, le
compteur reste a 1 pour toujours, et le compte s'affiche « en ligne » a vie.
C'est exactement ce qu'on observait: un utilisateur restait vert des jours
apres sa derniere visite.

La seule marque qui ne se coince pas est l'horodatage: le client bat toutes
les vingt secondes, chaque appel du chat le rafraichit aussi. Passe la
fenetre ci-dessous sans un signe de vie, la personne est hors ligne -- que le
compteur dise ce qu'il veut.
"""

from datetime import timedelta

from django.utils import timezone

# Trois battements manques avant de declarer quelqu'un parti: assez pour
# absorber un ping perdu ou une seconde de reseau, assez court pour que
# « hors ligne » arrive pendant qu'on regarde encore l'ecran.
FENETRE_PRESENCE = timedelta(seconds=75)


def presence_en_ligne(last_seen_at):
    """En ligne si un signe de vie est arrive dans la fenetre."""
    if last_seen_at is None:
        return False
    return (timezone.now() - last_seen_at) <= FENETRE_PRESENCE


def presence_depuis_ligne(presence):
    """Meme lecture, a partir de la ligne `ChatPresence` (ou de son absence)."""
    if presence is None:
        return False
    return presence_en_ligne(getattr(presence, "last_seen_at", None))


def presence_last_seen(presence):
    """L'horodatage de la derniere activite, ou None si on ne l'a jamais vue."""
    if presence is None:
        return None
    return getattr(presence, "last_seen_at", None)
