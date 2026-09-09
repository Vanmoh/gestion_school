"""Les notifications finissent par partir.

Le module Communication écrivait ses notifications en base avec
`is_sent=False`, et rien ne le repassait jamais à True: aucune passerelle
n'existait. Les familles ne recevaient rien — ni push, ni SMS, ni courriel —
alors que prévenir les familles est la raison d'être du module.

Ce qui suit couvre le canal push: l'enregistrement de l'appareil, la
distribution, et ce qui doit se passer quand rien n'est configuré — car une
école doit pouvoir tourner sans Firebase.

Aucun test n'appelle Firebase: le service d'envoi est doublé.
"""

from unittest.mock import patch

from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.common.models import DeviceToken
from apps.common.push import ResultatEnvoi, push_configure
from apps.common.tasks import envoyer_les_notifications_en_attente
from apps.school.models import Notification, NotificationChannel

CONFIGURE = {
    "FCM_PROJECT_ID": "ecole-demo",
    "FCM_CREDENTIALS_JSON": '{"type": "service_account"}',
}


class ConfigurationDuPushTests(TestCase):
    @override_settings(FCM_PROJECT_ID="", FCM_CREDENTIALS_JSON="", FCM_CREDENTIALS_FILE="")
    def test_sans_reglage_le_push_se_declare_absent(self):
        """Une école doit pouvoir tourner sans Firebase."""
        self.assertFalse(push_configure())

    @override_settings(**CONFIGURE, FCM_CREDENTIALS_FILE="")
    def test_avec_projet_et_identifiants_il_est_pret(self):
        self.assertTrue(push_configure())

    @override_settings(FCM_PROJECT_ID="ecole-demo", FCM_CREDENTIALS_JSON="", FCM_CREDENTIALS_FILE="")
    def test_un_projet_sans_identifiants_ne_suffit_pas(self):
        self.assertFalse(push_configure())


class EnregistrementDeLAppareilTests(APITestCase):
    def setUp(self):
        self.parent = User.objects.create_user(
            username="parent_push", password="Pass1234!", role=UserRole.PARENT
        )
        self.autre = User.objects.create_user(
            username="autre_push", password="Pass1234!", role=UserRole.PARENT
        )
        self.client.force_authenticate(self.parent)

    def test_l_appareil_s_enregistre(self):
        reponse = self.client.post(
            "/api/auth/device-token/",
            {"token": "jeton-abc", "platform": "android"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        appareil = DeviceToken.objects.get(token="jeton-abc")
        self.assertEqual(appareil.user, self.parent)
        self.assertTrue(appareil.is_active)

    def test_un_jeton_sans_valeur_est_refuse(self):
        reponse = self.client.post(
            "/api/auth/device-token/", {"token": "  "}, format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_telephone_partage_suit_le_dernier_connecte(self):
        """Sinon un parent recevrait les notifications adressées à l'autre."""
        self.client.post(
            "/api/auth/device-token/", {"token": "jeton-partage"}, format="json"
        )

        self.client.force_authenticate(self.autre)
        self.client.post(
            "/api/auth/device-token/", {"token": "jeton-partage"}, format="json"
        )

        self.assertEqual(DeviceToken.objects.filter(token="jeton-partage").count(), 1)
        self.assertEqual(DeviceToken.objects.get(token="jeton-partage").user, self.autre)

    def test_une_plateforme_inconnue_retombe_sur_android(self):
        self.client.post(
            "/api/auth/device-token/",
            {"token": "jeton-x", "platform": "blackberry"},
            format="json",
        )

        self.assertEqual(
            DeviceToken.objects.get(token="jeton-x").platform,
            DeviceToken.Platform.ANDROID,
        )

    def test_le_retrait_ferme_le_jeton_sans_l_effacer(self):
        """Effacé, il reviendrait au premier envoi: rien ne dirait qu'il est mort."""
        self.client.post(
            "/api/auth/device-token/", {"token": "jeton-abc"}, format="json"
        )

        reponse = self.client.delete(
            "/api/auth/device-token/", {"token": "jeton-abc"}, format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(DeviceToken.objects.get(token="jeton-abc").is_active)

    def test_on_ne_ferme_pas_le_jeton_d_un_autre_compte(self):
        DeviceToken.objects.create(token="jeton-autre", user=self.autre)

        self.client.delete(
            "/api/auth/device-token/", {"token": "jeton-autre"}, format="json"
        )

        self.assertTrue(DeviceToken.objects.get(token="jeton-autre").is_active)

    def test_la_deconnexion_ferme_l_appareil(self):
        DeviceToken.objects.create(token="jeton-abc", user=self.parent)

        self.client.post(
            "/api/auth/logout/",
            {"refresh": "jeton-invalide", "device_token": "jeton-abc"},
            format="json",
        )

        self.assertFalse(DeviceToken.objects.get(token="jeton-abc").is_active)

    def test_un_anonyme_ne_peut_pas_enregistrer(self):
        self.client.force_authenticate(None)

        reponse = self.client.post(
            "/api/auth/device-token/", {"token": "jeton-anon"}, format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_401_UNAUTHORIZED)


@override_settings(**CONFIGURE, FCM_CREDENTIALS_FILE="")
class DistributionDesNotificationsTests(TestCase):
    def setUp(self):
        self.parent = User.objects.create_user(
            username="parent_distrib", password="Pass1234!", role=UserRole.PARENT
        )
        self.appareil = DeviceToken.objects.create(
            token="jeton-actif", user=self.parent
        )

    def _notification(self, canal=NotificationChannel.PUSH, destinataire=None):
        return Notification.objects.create(
            recipient=destinataire or self.parent,
            channel=canal,
            title="Incident disciplinaire",
            message="Un incident vous est signalé.",
        )

    def test_une_notification_partie_est_marquee_envoyee(self):
        notification = self._notification()

        with patch(
            "apps.common.push.envoyer_a_des_appareils",
            return_value=ResultatEnvoi(envoyes=1),
        ) as envoi:
            resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 1)
        notification.refresh_from_db()
        self.assertTrue(notification.is_sent)
        self.assertIsNotNone(notification.sent_at)
        self.assertEqual(envoi.call_args.args[0], ["jeton-actif"])

    def test_un_echec_laisse_la_notification_en_attente(self):
        """La marquer envoyée serait mentir sur ce qui est parti."""
        notification = self._notification()

        with patch(
            "apps.common.push.envoyer_a_des_appareils",
            return_value=ResultatEnvoi(echecs=1, erreur="FCM 503"),
        ):
            resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["echecs"], 1)
        notification.refresh_from_db()
        self.assertFalse(notification.is_sent)

    def test_un_jeton_mort_est_ferme(self):
        """Sinon on réessaie chaque nuit vers un téléphone réinitialisé."""
        self._notification()

        with patch(
            "apps.common.push.envoyer_a_des_appareils",
            return_value=ResultatEnvoi(echecs=1, jetons_invalides=["jeton-actif"]),
        ):
            resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["jetons_fermes"], 1)
        self.assertFalse(DeviceToken.objects.get(token="jeton-actif").is_active)

    def test_un_destinataire_sans_appareil_n_est_pas_marque_envoye(self):
        sans_appareil = User.objects.create_user(
            username="sans_appareil", password="Pass1234!", role=UserRole.PARENT
        )
        notification = self._notification(destinataire=sans_appareil)

        resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 0)
        notification.refresh_from_db()
        self.assertFalse(notification.is_sent)

    def test_le_sms_reste_en_attente(self):
        """Aucune passerelle d'opérateur n'existe encore: ne rien prétendre."""
        notification = self._notification(canal=NotificationChannel.SMS)

        with patch(
            "apps.common.push.envoyer_a_des_appareils",
            return_value=ResultatEnvoi(envoyes=1),
        ):
            envoyer_les_notifications_en_attente()

        notification.refresh_from_db()
        self.assertFalse(notification.is_sent)

    def test_une_notification_deja_envoyee_n_est_pas_reprise(self):
        notification = self._notification()
        notification.is_sent = True
        notification.sent_at = timezone.now()
        notification.save()

        resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 0)

    def test_un_jeton_ferme_n_est_plus_vise(self):
        self.appareil.desactiver()
        self._notification()

        resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 0)

    def test_le_lot_est_borne(self):
        """Une file gonflée par une panne ne doit pas bloquer le worker."""
        for _ in range(5):
            self._notification()

        with patch(
            "apps.common.push.envoyer_a_des_appareils",
            return_value=ResultatEnvoi(envoyes=1),
        ):
            resultat = envoyer_les_notifications_en_attente(limite=2)

        self.assertEqual(resultat["envoyees"], 2)
        self.assertEqual(Notification.objects.filter(is_sent=False).count(), 3)


class DistributionSansConfigurationTests(TestCase):
    """Un canal fermé laisse ses notifications en attente, sans bloquer le reste.

    La tâche s'arrêtait autrefois net quand Firebase manquait; depuis qu'elle
    dessert aussi le courriel et le SMS, elle ne peut plus: fermer le push
    priverait les familles joignables par les deux autres canaux.
    """

    @override_settings(FCM_PROJECT_ID="", FCM_CREDENTIALS_JSON="", FCM_CREDENTIALS_FILE="")
    def test_sans_firebase_la_notification_push_reste_en_attente(self):
        parent = User.objects.create_user(
            username="parent_sans_fcm", password="Pass1234!", role=UserRole.PARENT
        )
        DeviceToken.objects.create(token="jeton", user=parent)
        notification = Notification.objects.create(
            recipient=parent,
            channel=NotificationChannel.PUSH,
            title="Titre",
            message="Message",
        )

        resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 0)
        notification.refresh_from_db()
        self.assertFalse(notification.is_sent)


class ControleDeDeploiementDuPushTests(TestCase):
    """Rien ne signalait qu'aucune notification ne partait."""

    @override_settings(DEBUG=False, FCM_PROJECT_ID="", FCM_CREDENTIALS_JSON="", FCM_CREDENTIALS_FILE="")
    def test_il_signale_un_push_non_configure(self):
        from apps.common import checks

        trouves = checks.push_notifications_are_configured(None)

        self.assertEqual(len(trouves), 1)
        self.assertEqual(trouves[0].id, checks.W006_PUSH_ABSENT)

    @override_settings(DEBUG=False, FCM_CREDENTIALS_FILE="", **CONFIGURE)
    def test_il_se_tait_une_fois_configure(self):
        from apps.common import checks

        self.assertEqual(checks.push_notifications_are_configured(None), [])

    @override_settings(DEBUG=True, FCM_PROJECT_ID="", FCM_CREDENTIALS_JSON="", FCM_CREDENTIALS_FILE="")
    def test_le_developpement_n_est_pas_concerne(self):
        from apps.common import checks

        self.assertEqual(checks.push_notifications_are_configured(None), [])


class FermetureDesJetonsMortsTests(TestCase):
    """Quand un refus de FCM vise l'appareil, et quand il vise le message.

    Fermer un jeton sur un simple 400 reviendrait, le jour où une
    notification serait mal construite (titre trop long, `data` non
    conforme), à couper les notifications de toute l'école en une passe: FCM
    rend 400 dans les deux cas.
    """

    class _Reponse:
        def __init__(self, status_code, corps=None):
            self.status_code = status_code
            self._corps = corps
            self.text = str(corps or "")

        def json(self):
            if self._corps is None:
                raise ValueError("pas de JSON")
            return self._corps

    def test_un_404_ferme_le_jeton(self):
        from apps.common.push import _jeton_est_mort

        self.assertTrue(_jeton_est_mort(self._Reponse(404)))

    def test_un_400_sur_le_message_ne_ferme_rien(self):
        from apps.common.push import _jeton_est_mort

        reponse = self._Reponse(
            400,
            {
                "error": {
                    "status": "INVALID_ARGUMENT",
                    "details": [
                        {
                            "fieldViolations": [
                                {"field": "message.notification.title"}
                            ]
                        }
                    ],
                }
            },
        )

        self.assertFalse(_jeton_est_mort(reponse))

    def test_un_400_qui_designe_le_jeton_le_ferme(self):
        from apps.common.push import _jeton_est_mort

        reponse = self._Reponse(
            400,
            {
                "error": {
                    "details": [
                        {"fieldViolations": [{"field": "message.token"}]}
                    ]
                }
            },
        )

        self.assertTrue(_jeton_est_mort(reponse))

    def test_un_code_unregistered_ferme_le_jeton(self):
        from apps.common.push import _jeton_est_mort

        reponse = self._Reponse(
            400, {"error": {"details": [{"errorCode": "UNREGISTERED"}]}}
        )

        self.assertTrue(_jeton_est_mort(reponse))

    def test_un_400_sans_corps_lisible_ne_ferme_rien(self):
        from apps.common.push import _jeton_est_mort

        self.assertFalse(_jeton_est_mort(self._Reponse(400)))

    def test_un_503_ne_ferme_rien(self):
        """Une panne passagère de FCM ne dit rien de l'appareil."""
        from apps.common.push import _jeton_est_mort

        self.assertFalse(_jeton_est_mort(self._Reponse(503)))
