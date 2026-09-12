"""Ce qui doit suivre une ecriture, sans que l'appelant y pense.

Invalidation du cache du tableau de bord.

Les compteurs sont gardes une minute (dashboard_cache). Une minute de retard
passe inapercue sur des effectifs ou des absences, mais pas sur l'argent: un
caissier qui enregistre un paiement puis ouvre le tableau de bord doit y voir
son encaissement, sinon il conclut a une panne et ressaisit.

D'ou ces deux modeles et pas les autres: seuls les paiements et les depenses
sont saisis puis verifies dans la foulee sur le meme ecran.
"""

from django.conf import settings
from django.db.models.signals import post_delete, post_save, pre_save
from django.dispatch import receiver

from .dashboard_cache import invalidate_stats
from .models import Expense, ParentProfile, Payment, Student, StudentFee


@receiver(post_save, sender=Payment)
@receiver(post_delete, sender=Payment)
@receiver(post_save, sender=Expense)
@receiver(post_delete, sender=Expense)
def _clear_dashboard_stats(sender, instance, **kwargs):
    # etablissement_id et non instance.etablissement: lire la cle etrangere
    # declencherait une requete de plus a chaque ecriture, pour un objet dont
    # on n'utilise que l'identifiant.
    invalidate_stats(getattr(instance, "etablissement_id", None))


@receiver(pre_save, sender=settings.AUTH_USER_MODEL)
def _memoriser_l_ancien_telephone(sender, instance, **kwargs):
    """Retient le numero d'avant, pour savoir si le WhatsApp le suivait.

    Lu avant l'ecriture: apres, il est perdu, et l'on ne saurait plus
    distinguer un numero WhatsApp laisse tel quel d'un numero saisi
    volontairement different.
    """
    if not instance.pk:
        instance._ancien_telephone = ""
        return
    ancien = (
        type(instance)
        .objects.filter(pk=instance.pk)
        .values_list("phone", flat=True)
        .first()
    )
    instance._ancien_telephone = ancien or ""


@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def _propager_le_telephone_au_numero_whatsapp(sender, instance, created, **kwargs):
    """Fait suivre le numero WhatsApp quand le telephone change.

    Il existe deux numeros: `User.phone`, champ de repertoire, et
    `ParentProfile.whatsapp_phone`, seul utilise pour l'envoi des bulletins.
    On corrigeait le premier en croyant avoir tout fait, et l'envoi partait
    sur l'ancien numero -- ou sur rien.

    La regle: le numero WhatsApp suit le telephone tant que personne ne les a
    dissocies. Il est donc mis a jour quand il est vide, ou quand il valait
    exactement l'ancien telephone normalise. Un numero WhatsApp saisi
    volontairement different -- le portable du tuteur quand la fiche porte le
    fixe du domicile -- n'est jamais ecrase.

    Le format reste garanti: un telephone illisible (« 76 12 34 56 / bureau
    66 74 22 32 ») ne produit rien plutot qu'un numero devine, et l'ecole
    tranche a la main.
    """
    from apps.school.phone_utils import normaliser_numero

    profil = getattr(instance, "parent_profile", None)
    if profil is None:
        return

    nouveau = normaliser_numero(getattr(instance, "phone", ""))
    if not nouveau:
        return

    actuel = (profil.whatsapp_phone or "").strip()
    if actuel == nouveau:
        return

    ancien_normalise = normaliser_numero(getattr(instance, "_ancien_telephone", ""))
    dissocie = bool(actuel) and actuel != (ancien_normalise or "")
    if dissocie:
        return

    profil.whatsapp_phone = nouveau
    profil.save(update_fields=["whatsapp_phone", "updated_at"])


@receiver(post_save, sender=ParentProfile)
def _reprendre_le_telephone_a_la_creation_du_profil(sender, instance, created, **kwargs):
    """Reprend le telephone du compte quand la fiche parent vient de naitre.

    Le signal precedent ne suffit pas: a l'inscription, le compte est
    enregistre avant que sa fiche parent existe, et la propagation n'a alors
    rien a viser. Un parent cree avec son telephone se retrouvait sans numero
    WhatsApp, donc injoignable, sans que rien ne le signale.
    """
    if not created or (instance.whatsapp_phone or "").strip():
        return

    from apps.school.phone_utils import normaliser_numero

    numero = normaliser_numero(getattr(instance.user, "phone", "") if instance.user else "")
    if not numero:
        return

    # `update` et non `save`: on est deja dans le post_save de cet objet, et
    # le reenregistrer relancerait le signal.
    ParentProfile.objects.filter(pk=instance.pk).update(whatsapp_phone=numero)
    instance.whatsapp_phone = numero


# --- Inscription conditionnee au paiement ----------------------------------
#
# Le statut suit la caisse sans que personne ait a le mettre a jour. Le faire
# a la main aurait garanti l'oubli: le jour ou un parent solde son
# inscription, c'est au guichet, et la secretaire n'ira pas rouvrir la fiche
# pour cocher une case.


def _recalculer_pour(student):
    from .inscription import recalculer

    if student is None:
        return
    try:
        recalculer(student)
    except Exception:
        # Le recalcul ne doit jamais faire echouer l'ecriture qui l'a
        # declenche: un versement enregistre reste enregistre, meme si le
        # statut se remet d'accord au passage suivant.
        pass


@receiver(post_save, sender=Payment)
@receiver(post_delete, sender=Payment)
def _suivre_le_reglement_de_l_inscription(sender, instance, **kwargs):
    """Un versement -- ou son annulation -- peut liberer les documents."""
    fee = getattr(instance, "fee", None)
    _recalculer_pour(getattr(fee, "student", None))


@receiver(post_save, sender=StudentFee)
@receiver(post_delete, sender=StudentFee)
def _suivre_les_frais_d_inscription(sender, instance, **kwargs):
    """Poser le frais d'inscription est ce qui met l'eleve en attente.

    Sans frais, il n'y a rien a payer: un eleve cree avant que le bareme
    soit pose reste en regle jusqu'a ce qu'on lui en reclame un.
    """
    _recalculer_pour(getattr(instance, "student", None))


@receiver(post_save, sender=Student)
def _statuer_a_la_creation_de_la_fiche(sender, instance, created, **kwargs):
    if created:
        _recalculer_pour(instance)
