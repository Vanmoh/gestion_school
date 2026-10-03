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


def stats_cache_key(etablissement_id, month_start, annee_id=None) -> str:
    """Cle des compteurs d'un etablissement, pour une annee et un mois donnes.

    Volontairement sans identifiant d'utilisateur: les chiffres ne dependent
    que de la portee, et une cle par compte rendrait le cache inutile des le
    deuxieme utilisateur connecte. La portee est resolue avant toute lecture,
    donc un compte ne peut pas atteindre les totaux d'un etablissement qui
    n'est pas le sien.

    L'annee, elle, est indispensable depuis que les compteurs la respectent:
    sans elle, basculer sur l'annee suivante rendait les chiffres de l'annee
    precedente pendant une minute -- et rien a l'ecran ne l'aurait dit.
    """
    scope = etablissement_id if etablissement_id is not None else "global"
    annee = annee_id if annee_id is not None else "sans-annee"
    return f"dashboard:stats:{scope}:{annee}:{month_start.isoformat()}"


def invalidate_stats(etablissement_id) -> None:
    """Vide les compteurs du mois en cours pour cette portee.

    La cle "global" part avec: elle sert les comptes sans etablissement
    rattache, dont les totaux couvrent justement l'etablissement modifie.

    Seul le mois courant est vise. Une ecriture antidatee laisse donc son mois
    en cache jusqu'a expiration -- un cas rare, sans consequence sur les
    chiffres du mois affiche par defaut.
    """
    month_start = current_month_start()

    # Toutes les annees de l'etablissement, et non la seule active: un
    # caissier qui travaille sur l'annee suivante doit voir son encaissement
    # aussitot, comme les autres. L'ensemble est borne -- une ecole en compte
    # une ou deux -- donc l'enumerer coute moins qu'un cache qui ment.
    from apps.school.models import AcademicYear

    annees = [None]
    if etablissement_id is not None:
        annees += list(
            AcademicYear.objects.filter(
                etablissement_id=etablissement_id
            ).values_list("id", flat=True)
        )
    else:
        annees += list(AcademicYear.objects.values_list("id", flat=True))

    keys = []
    for annee_id in annees:
        keys.append(stats_cache_key(None, month_start, annee_id))
        if etablissement_id is not None:
            keys.append(stats_cache_key(etablissement_id, month_start, annee_id))
    cache.delete_many(keys)
