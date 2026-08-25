"""Invalidation du cache du tableau de bord.

Les compteurs sont gardes une minute (dashboard_cache). Une minute de retard
passe inapercue sur des effectifs ou des absences, mais pas sur l'argent: un
caissier qui enregistre un paiement puis ouvre le tableau de bord doit y voir
son encaissement, sinon il conclut a une panne et ressaisit.

D'ou ces deux modeles et pas les autres: seuls les paiements et les depenses
sont saisis puis verifies dans la foulee sur le meme ecran.
"""

from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from .dashboard_cache import invalidate_stats
from .models import Expense, Payment


@receiver(post_save, sender=Payment)
@receiver(post_delete, sender=Payment)
@receiver(post_save, sender=Expense)
@receiver(post_delete, sender=Expense)
def _clear_dashboard_stats(sender, instance, **kwargs):
    # etablissement_id et non instance.etablissement: lire la cle etrangere
    # declencherait une requete de plus a chaque ecriture, pour un objet dont
    # on n'utilise que l'identifiant.
    invalidate_stats(getattr(instance, "etablissement_id", None))
