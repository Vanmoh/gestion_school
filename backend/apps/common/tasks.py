"""Les taches de fond: sauvegarde, et distribution des notifications."""

import logging

from celery import shared_task
from django.core.management import call_command

logger = logging.getLogger(__name__)


@shared_task
def scheduled_database_backup():
    call_command("backup_db")


@shared_task
def envoyer_les_notifications_en_attente(limite: int = 200):
    """Fait partir les notifications restees en base.

    Le module Communication ecrivait ses notifications avec `is_sent=False`
    et rien ne le repassait jamais a True: elles s'empilaient sans que
    personne ne les recoive, alors que prevenir les familles est la raison
    d'etre du module.

    La tache ne traite que le canal PUSH: le SMS attend une passerelle
    d'operateur, le courriel un serveur d'envoi. Les notifications de ces
    deux canaux restent en attente plutot que d'etre marquees envoyees --
    les marquer serait mentir sur ce qui est parti.

    `limite` borne le lot: une file qui a grossi pendant une panne ne doit
    pas immobiliser le worker sur un seul passage.
    """
    from apps.common.models import DeviceToken
    from apps.common.push import envoyer_a_des_appareils, push_configure
    from apps.school.models import Notification, NotificationChannel
    from django.utils import timezone

    if not push_configure():
        logger.info("Push non configure: aucune notification envoyee.")
        return {"envoyees": 0, "echecs": 0, "raison": "push non configure"}

    en_attente = list(
        Notification.objects.filter(
            is_sent=False, channel=NotificationChannel.PUSH
        )
        .select_related("recipient")
        .order_by("created_at", "id")[:limite]
    )
    if not en_attente:
        return {"envoyees": 0, "echecs": 0}

    # Les jetons sont charges en un coup pour tous les destinataires du lot:
    # une requete par notification ferait autant d'allers-retours que la file
    # compte de lignes.
    destinataires = {
        notification.recipient_id
        for notification in en_attente
        if notification.recipient_id
    }
    jetons_par_utilisateur: dict[int, list[str]] = {}
    for user_id, jeton in DeviceToken.objects.filter(
        user_id__in=destinataires, is_active=True
    ).values_list("user_id", "token"):
        jetons_par_utilisateur.setdefault(user_id, []).append(jeton)

    envoyees = 0
    echecs = 0
    jetons_morts: set[str] = set()

    for notification in en_attente:
        jetons = jetons_par_utilisateur.get(notification.recipient_id or 0, [])
        if not jetons:
            # Destinataire sans appareil connu: rien a envoyer, et rien a
            # marquer. La notification reste lisible dans l'application.
            continue

        resultat = envoyer_a_des_appareils(
            jetons,
            titre=notification.title,
            message=notification.message,
            donnees={"notification_id": notification.id},
        )
        jetons_morts.update(resultat.jetons_invalides)

        if resultat.a_reussi:
            notification.is_sent = True
            notification.sent_at = timezone.now()
            notification.save(update_fields=["is_sent", "sent_at", "updated_at"])
            envoyees += 1
        else:
            echecs += 1
            if resultat.erreur:
                logger.warning(
                    "Notification #%s non envoyee: %s",
                    notification.id,
                    resultat.erreur,
                )

    if jetons_morts:
        # Un telephone reinitialise ou une application desinstallee rendent
        # un jeton mort: le fermer evite de reessayer chaque nuit.
        DeviceToken.objects.filter(token__in=jetons_morts).update(is_active=False)

    return {
        "envoyees": envoyees,
        "echecs": echecs,
        "jetons_fermes": len(jetons_morts),
    }
