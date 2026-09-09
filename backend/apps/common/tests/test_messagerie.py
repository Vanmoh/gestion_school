"""Le courriel et le SMS: les deux autres canaux vers les familles.

Le module Communication promettait trois canaux; seul le push était branché.
Les notifications de courriel et de SMS restaient en attente — ce qui était
honnête, les marquer envoyées aurait été mentir, mais laissait les familles
sans nouvelles.

Aucun test n'appelle un vrai serveur: le backend de courriel est celui que
Django garde en mémoire, et la passerelle SMS est doublée.
"""

from unittest.mock import patch

from django.core import mail
from django.test import TestCase, override_settings

from apps.accounts.models import User, UserRole
from apps.common.messagerie import (
    CHAMPS_PAR_FOURNISSEUR,
    ResultatMessage,
    courriel_configure,
    envoyer_un_courriel,
    envoyer_un_sms,
    passerelle_sms,
)
from apps.common.tasks import envoyer_les_notifications_en_attente
from apps.school.models import (
    Etablissement,
    Notification,
    NotificationChannel,
    SmsProviderConfig,
)

SMTP = {
    "EMAIL_BACKEND": "django.core.mail.backends.locmem.EmailBackend",
    "EMAIL_HOST": "smtp.exemple.ml",
}


class ConfigurationDuCourrielTests(TestCase):
    @override_settings(
        EMAIL_BACKEND="django.core.mail.backends.console.EmailBackend",
        EMAIL_HOST="",
    )
    def test_le_backend_console_ne_compte_pas_comme_configure(self):
        """Il affiche le message dans les logs, il ne l'envoie à personne."""
        self.assertFalse(courriel_configure())

    @override_settings(
        EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend", EMAIL_HOST=""
    )
    def test_un_backend_smtp_sans_hote_ne_suffit_pas(self):
        self.assertFalse(courriel_configure())

    @override_settings(
        EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend",
        EMAIL_HOST="smtp.exemple.ml",
    )
    def test_avec_un_hote_smtp_il_est_pret(self):
        self.assertTrue(courriel_configure())


class EnvoiDUnCourrielTests(TestCase):
    @override_settings(**SMTP)
    def test_le_message_part(self):
        # Le backend locmem n'est pas « smtp »: on double le contrôle pour
        # éprouver l'envoi lui-même, pas la configuration.
        with patch("apps.common.messagerie.courriel_configure", return_value=True):
            resultat = envoyer_un_courriel(
                destinataire="parent@exemple.ml",
                sujet="Incident disciplinaire",
                message="Un incident vous est signalé.",
            )

        self.assertTrue(resultat.envoye)
        self.assertEqual(len(mail.outbox), 1)
        self.assertEqual(mail.outbox[0].to, ["parent@exemple.ml"])
        self.assertEqual(mail.outbox[0].subject, "Incident disciplinaire")

    def test_sans_configuration_l_envoi_echoue_proprement(self):
        """Une école doit pouvoir tourner sans serveur de courriel."""
        with patch("apps.common.messagerie.courriel_configure", return_value=False):
            resultat = envoyer_un_courriel(
                destinataire="parent@exemple.ml", sujet="Titre", message="Corps"
            )

        self.assertFalse(resultat.envoye)
        self.assertIn("non configure", resultat.erreur)
        self.assertEqual(len(mail.outbox), 0)

    def test_une_adresse_vide_est_refusee_avant_tout_appel(self):
        resultat = envoyer_un_courriel(destinataire="  ", sujet="T", message="M")

        self.assertFalse(resultat.envoye)
        self.assertIn("sans adresse", resultat.erreur)


class PasserelleSmsTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee SMS")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")

    def _passerelle(self, nom="Orange Mali", active=True, etablissement=None):
        return SmsProviderConfig.objects.create(
            etablissement=etablissement or self.etablissement,
            provider_name=nom,
            api_url="https://api.exemple.ml/sms",
            api_token="jeton-secret",
            sender_id="LYCEE",
            is_active=active,
        )

    class _Reponse:
        def __init__(self, status_code, text=""):
            self.status_code = status_code
            self.text = text

    def test_la_passerelle_active_de_l_etablissement_est_retenue(self):
        self._passerelle(active=False)
        active = self._passerelle(nom="Malitel")

        self.assertEqual(passerelle_sms(self.etablissement), active)

    def test_celle_d_un_autre_etablissement_n_est_pas_empruntee(self):
        """Le contrat est signé par l'établissement, pas par l'éditeur."""
        self._passerelle(etablissement=self.autre)

        self.assertIsNone(passerelle_sms(self.etablissement))

    def test_le_sms_part_avec_le_numero_et_l_expediteur(self):
        passerelle = self._passerelle()

        with patch(
            "apps.common.messagerie.requests.post",
            return_value=self._Reponse(200),
        ) as appel:
            resultat = envoyer_un_sms(
                passerelle=passerelle, numero="+22376123456", message="Bonjour"
            )

        self.assertTrue(resultat.envoye)
        charge = appel.call_args.kwargs["json"]
        self.assertEqual(charge["to"], "+22376123456")
        self.assertEqual(charge["message"], "Bonjour")
        self.assertEqual(charge["from"], "LYCEE")
        self.assertIn("jeton-secret", appel.call_args.kwargs["headers"]["Authorization"])

    def test_les_noms_de_champs_suivent_le_fournisseur(self):
        """Ce qui change d'un fournisseur à l'autre est le nom des champs."""
        passerelle = self._passerelle(nom="Twilio")

        with patch(
            "apps.common.messagerie.requests.post",
            return_value=self._Reponse(201),
        ) as appel:
            envoyer_un_sms(passerelle=passerelle, numero="+223", message="Bonjour")

        charge = appel.call_args.kwargs["json"]
        self.assertEqual(charge["To"], "+223")
        self.assertEqual(charge["Body"], "Bonjour")

    def test_sans_passerelle_l_envoi_echoue_proprement(self):
        resultat = envoyer_un_sms(passerelle=None, numero="+223", message="Bonjour")

        self.assertFalse(resultat.envoye)
        self.assertIn("Aucune passerelle", resultat.erreur)

    def test_le_refus_du_fournisseur_porte_sa_raison(self):
        """Crédit épuisé, expéditeur non déclaré: c'est ce qui permet d'agir."""
        passerelle = self._passerelle()

        with patch(
            "apps.common.messagerie.requests.post",
            return_value=self._Reponse(402, "credit epuise"),
        ):
            resultat = envoyer_un_sms(
                passerelle=passerelle, numero="+223", message="Bonjour"
            )

        self.assertFalse(resultat.envoye)
        self.assertIn("402", resultat.erreur)
        self.assertIn("credit epuise", resultat.erreur)

    def test_une_panne_reseau_ne_leve_pas(self):
        import requests

        passerelle = self._passerelle()

        with patch(
            "apps.common.messagerie.requests.post",
            side_effect=requests.RequestException("injoignable"),
        ):
            resultat = envoyer_un_sms(
                passerelle=passerelle, numero="+223", message="Bonjour"
            )

        self.assertFalse(resultat.envoye)
        self.assertIn("injoignable", resultat.erreur)

    def test_un_numero_vide_est_refuse_avant_tout_appel(self):
        passerelle = self._passerelle()

        with patch("apps.common.messagerie.requests.post") as appel:
            resultat = envoyer_un_sms(passerelle=passerelle, numero="", message="M")

        self.assertFalse(resultat.envoye)
        appel.assert_not_called()

    def test_la_table_des_fournisseurs_porte_un_defaut(self):
        """Un fournisseur inconnu doit rester servi, pas rejeté."""
        self.assertIn("defaut", CHAMPS_PAR_FOURNISSEUR)


class DistributionSurTroisCanauxTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Trois Canaux")
        self.parent = User.objects.create_user(
            username="parent_canaux",
            password="Pass1234!",
            role=UserRole.PARENT,
            email="parent@exemple.ml",
            phone="+22376123456",
            etablissement=self.etablissement,
        )

    def _notification(self, canal):
        return Notification.objects.create(
            etablissement=self.etablissement,
            recipient=self.parent,
            channel=canal,
            title="Bulletin disponible",
            message="Le bulletin de votre enfant est disponible.",
        )

    @override_settings(**SMTP)
    def test_le_courriel_part_et_la_notification_est_marquee(self):
        notification = self._notification(NotificationChannel.EMAIL)

        with patch("apps.common.messagerie.courriel_configure", return_value=True):
            resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 1)
        notification.refresh_from_db()
        self.assertTrue(notification.is_sent)
        self.assertEqual(len(mail.outbox), 1)

    def test_le_sms_part_par_la_passerelle_de_l_etablissement(self):
        SmsProviderConfig.objects.create(
            etablissement=self.etablissement,
            provider_name="Orange Mali",
            api_url="https://api.exemple.ml/sms",
            api_token="jeton",
            is_active=True,
        )
        notification = self._notification(NotificationChannel.SMS)

        # Le module source, et non `tasks`: l'import y est local à la
        # fonction, donc résolu à l'exécution.
        with patch(
            "apps.common.messagerie.envoyer_un_sms",
            return_value=ResultatMessage(envoye=True),
        ) as envoi:
            resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 1)
        notification.refresh_from_db()
        self.assertTrue(notification.is_sent)
        # Le titre et le corps voyagent ensemble: un SMS n'a pas d'objet.
        self.assertIn("Bulletin disponible", envoi.call_args.kwargs["message"])

    def test_sans_passerelle_le_sms_reste_en_attente(self):
        """Ne jamais marquer envoyé à vide: l'école croirait les familles prévenues."""
        notification = self._notification(NotificationChannel.SMS)

        resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 0)
        self.assertEqual(resultat["echecs"], 1)
        notification.refresh_from_db()
        self.assertFalse(notification.is_sent)

    def test_sans_serveur_de_courriel_la_notification_n_est_pas_reprise(self):
        notification = self._notification(NotificationChannel.EMAIL)

        with patch("apps.common.messagerie.courriel_configure", return_value=False):
            envoyer_les_notifications_en_attente()

        notification.refresh_from_db()
        self.assertFalse(notification.is_sent)

    @override_settings(**SMTP)
    def test_un_destinataire_sans_adresse_n_est_pas_compte_en_echec(self):
        """Rien à envoyer n'est pas un échec d'envoi."""
        self.parent.email = ""
        self.parent.save(update_fields=["email"])
        self._notification(NotificationChannel.EMAIL)

        with patch("apps.common.messagerie.courriel_configure", return_value=True):
            resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 0)
        self.assertEqual(resultat["echecs"], 0)

    @override_settings(**SMTP)
    def test_un_canal_ferme_n_empeche_pas_les_autres_de_partir(self):
        """Le push non configuré ne doit pas retenir le courriel."""
        courriel = self._notification(NotificationChannel.EMAIL)
        push = self._notification(NotificationChannel.PUSH)

        with patch("apps.common.messagerie.courriel_configure", return_value=True):
            resultat = envoyer_les_notifications_en_attente()

        self.assertEqual(resultat["envoyees"], 1)
        courriel.refresh_from_db()
        push.refresh_from_db()
        self.assertTrue(courriel.is_sent)
        self.assertFalse(push.is_sent)


class ControleDuCourrielTests(TestCase):
    @override_settings(
        DEBUG=False,
        EMAIL_BACKEND="django.core.mail.backends.console.EmailBackend",
        EMAIL_HOST="",
    )
    def test_il_signale_l_absence_de_serveur(self):
        from apps.common import checks

        trouves = checks.outgoing_mail_is_configured(None)

        self.assertEqual(len(trouves), 1)
        self.assertEqual(trouves[0].id, checks.W007_COURRIEL_ABSENT)

    @override_settings(
        DEBUG=False,
        EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend",
        EMAIL_HOST="smtp.exemple.ml",
    )
    def test_il_se_tait_une_fois_configure(self):
        from apps.common import checks

        self.assertEqual(checks.outgoing_mail_is_configured(None), [])

    @override_settings(DEBUG=True, EMAIL_HOST="")
    def test_le_developpement_n_est_pas_concerne(self):
        from apps.common import checks

        self.assertEqual(checks.outgoing_mail_is_configured(None), [])
