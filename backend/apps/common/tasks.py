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

    Les trois canaux sont traites: push, courriel et SMS. Un canal non
    configure n'echoue pas l'ensemble -- ses notifications restent en attente
    et repartiront au prochain passage, une fois l'ecole equipee. Elles ne
    sont jamais marquees envoyees a vide: ce serait mentir sur ce qui est
    parti, et l'ecole croirait ses familles prevenues.

    `limite` borne le lot: une file qui a grossi pendant une panne ne doit
    pas immobiliser le worker sur un seul passage.
    """
    from apps.common.messagerie import (
        courriel_configure,
        envoyer_un_courriel,
        envoyer_un_sms,
        passerelle_sms,
    )
    from apps.common.models import DeviceToken
    from apps.common.push import envoyer_a_des_appareils, push_configure
    from apps.school.models import Notification, NotificationChannel
    from django.utils import timezone

    push_pret = push_configure()
    courriel_pret = courriel_configure()

    canaux_ouverts = [NotificationChannel.SMS]
    if push_pret:
        canaux_ouverts.append(NotificationChannel.PUSH)
    if courriel_pret:
        canaux_ouverts.append(NotificationChannel.EMAIL)

    en_attente = list(
        Notification.objects.filter(is_sent=False, channel__in=canaux_ouverts)
        .select_related("recipient", "etablissement")
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
    # Une requete par etablissement, pas une par notification: une classe
    # entiere prevenue le meme soir vise la meme passerelle.
    passerelles: dict[int, object] = {}

    def _passerelle(etablissement):
        if etablissement is None:
            return None
        if etablissement.id not in passerelles:
            passerelles[etablissement.id] = passerelle_sms(etablissement)
        return passerelles[etablissement.id]

    for notification in en_attente:
        destinataire = notification.recipient
        parti = False
        motif = ""

        if notification.channel == NotificationChannel.PUSH:
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
            parti, motif = resultat.a_reussi, resultat.erreur

        elif notification.channel == NotificationChannel.EMAIL:
            adresse = str(getattr(destinataire, "email", "") or "").strip()
            if not adresse:
                # Pas d'adresse: rien a envoyer et rien a marquer, comme pour
                # un destinataire sans appareil.
                continue
            resultat = envoyer_un_courriel(
                destinataire=adresse,
                sujet=notification.title,
                message=notification.message,
            )
            parti, motif = resultat.envoye, resultat.erreur

        elif notification.channel == NotificationChannel.SMS:
            numero = str(getattr(destinataire, "phone", "") or "").strip()
            if not numero:
                continue
            resultat = envoyer_un_sms(
                passerelle=_passerelle(notification.etablissement),
                numero=numero,
                message=f"{notification.title}: {notification.message}",
            )
            parti, motif = resultat.envoye, resultat.erreur

        if parti:
            notification.is_sent = True
            notification.sent_at = timezone.now()
            notification.save(update_fields=["is_sent", "sent_at", "updated_at"])
            envoyees += 1
        else:
            echecs += 1
            if motif:
                logger.warning(
                    "Notification #%s (%s) non envoyee: %s",
                    notification.id,
                    notification.channel,
                    motif,
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
