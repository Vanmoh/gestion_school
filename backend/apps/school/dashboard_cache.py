"""Cache des compteurs du tableau de bord.

La vue additionne sept agregats -- paiements, depenses, eleves, absences,
classes, enseignants -- a chaque affichage, et l'application les redemande a
chaque retour sur l'ecran comme a chaque tirage vers le bas. Vers une base
distante, ces allers-retours sont le poste dominant du temps d'affichage.

La cle et son invalidation vivent ici plutot que dans la vue: les signaux qui
la vident doivent en construire exactement le meme format, et deux ecritures
du meme motif finissent toujours par diverger.
"""

from django.core.cache import cache
from django.utils import timezone

# Assez court pour qu'un chiffre oublie se rattrape tout seul, assez long pour
# absorber les rafraichissements en rafale d'un meme ecran. Les ecritures qui
# se voient immediatement -- paiements, depenses -- ne dependent pas de ce
# delai: elles vident la cle (voir signals.py).
STATS_CACHE_SECONDS = 60


def current_month_start():
    return timezone.now().date().replace(day=1)


def stats_cache_key(etablissement_id, month_start) -> str:
    """Cle des compteurs d'un etablissement pour un mois donne.

    Volontairement sans identifiant d'utilisateur: les chiffres ne dependent
    que de la portee, et une cle par compte rendrait le cache inutile des le
    deuxieme utilisateur connecte. La portee est resolue avant toute lecture,
    donc un compte ne peut pas atteindre les totaux d'un etablissement qui
    n'est pas le sien.
    """
    scope = etablissement_id if etablissement_id is not None else "global"
    return f"dashboard:stats:{scope}:{month_start.isoformat()}"


def invalidate_stats(etablissement_id) -> None:
    """Vide les compteurs du mois en cours pour cette portee.

    La cle "global" part avec: elle sert les comptes sans etablissement
    rattache, dont les totaux couvrent justement l'etablissement modifie.

    Seul le mois courant est vise. Une ecriture antidatee laisse donc son mois
    en cache jusqu'a expiration -- un cas rare, sans consequence sur les
    chiffres du mois affiche par defaut.
    """
    month_start = current_month_start()
    keys = [stats_cache_key(None, month_start)]
    if etablissement_id is not None:
        keys.append(stats_cache_key(etablissement_id, month_start))
    cache.delete_many(keys)
