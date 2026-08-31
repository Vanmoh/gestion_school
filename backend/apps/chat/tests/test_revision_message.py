"""Corriger ou retirer un message deja envoye.

Rien ne le permettait: un message parti dans le mauvais groupe y restait a
vie. Retirer efface le contenu sans supprimer la ligne -- un trou au milieu
du fil serait inexplicable, et l'on perdrait la trace de qui a retire quoi.
"""

from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.chat.models import ChatMessage, Conversation, ConversationParticipant
from apps.school.models import Etablissement


class RevisionMessageTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="IFP-OBK Test",
            address="Quartier test",
            phone="670000000",
            email="test@ifp-obk.com",
        )
        self.auteur = User.objects.create_user(
            username="auteur",
            password="Pass1234!",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )
        self.autre = User.objects.create_user(
            username="autre",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )

        self.conversation = Conversation.objects.create(
            is_group=False, etablissement=self.etablissement
        )
        for compte in (self.auteur, self.autre):
            ConversationParticipant.objects.create(
                conversation=self.conversation, user=compte
            )

        self.message = ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.auteur,
            content="Reunion a 14h",
        )

        self.client_auteur = APIClient()
        self.client_auteur.force_authenticate(self.auteur)
        self.client_autre = APIClient()
        self.client_autre.force_authenticate(self.autre)

    def _url(self, message=None):
        return f"/api/chat/messages/{(message or self.message).id}/"

    def test_l_auteur_corrige_son_message(self):
        reponse = self.client_auteur.patch(
            self._url(), {"content": "Reunion a 15h"}, format="json"
        )

        self.assertEqual(reponse.status_code, 200)
        self.message.refresh_from_db()
        self.assertEqual(self.message.content, "Reunion a 15h")
        self.assertIsNotNone(
            self.message.edited_at,
            "la correction doit se voir: sinon on fait dire a quelqu'un ce "
            "qu'il n'avait pas ecrit",
        )

    def test_l_auteur_retire_son_message(self):
        reponse = self.client_auteur.delete(self._url())

        self.assertEqual(reponse.status_code, 200)
        self.message.refresh_from_db()
        self.assertIsNotNone(self.message.deleted_at)
        self.assertEqual(self.message.deleted_by_id, self.auteur.id)
        self.assertEqual(self.message.content, "")
        # La ligne reste: un trou au milieu du fil serait inexplicable.
        self.assertTrue(ChatMessage.objects.filter(id=self.message.id).exists())

    def test_un_message_retire_ne_livre_plus_son_texte(self):
        self.client_auteur.delete(self._url())

        reponse = self.client_autre.get(
            f"/api/chat/conversations/{self.conversation.id}/messages/"
        )
        self.assertEqual(reponse.status_code, 200)
        ligne = next(m for m in reponse.data if m["id"] == self.message.id)
        self.assertEqual(ligne["content"], "")
        self.assertIsNotNone(ligne["deleted_at"])

    def test_on_ne_touche_pas_au_message_d_un_autre(self):
        reponse = self.client_autre.patch(
            self._url(), {"content": "Reunion annulee"}, format="json"
        )

        self.assertEqual(reponse.status_code, 403)
        self.message.refresh_from_db()
        self.assertEqual(self.message.content, "Reunion a 14h")

    def test_un_message_ancien_ne_se_corrige_plus(self):
        """Passe le delai, d'autres l'ont lu et cite."""
        ChatMessage.objects.filter(id=self.message.id).update(
            created_at=timezone.now() - timedelta(minutes=30)
        )

        reponse = self.client_auteur.patch(
            self._url(), {"content": "Reunion a 16h"}, format="json"
        )

        self.assertEqual(reponse.status_code, 400)
        self.message.refresh_from_db()
        self.assertEqual(self.message.content, "Reunion a 14h")

    def test_un_message_ancien_se_retire_toujours(self):
        """Retirer reste possible: c'est le seul recours contre une fuite."""
        ChatMessage.objects.filter(id=self.message.id).update(
            created_at=timezone.now() - timedelta(days=3)
        )

        reponse = self.client_auteur.delete(self._url())

        self.assertEqual(reponse.status_code, 200)
        self.message.refresh_from_db()
        self.assertIsNotNone(self.message.deleted_at)

    def test_une_correction_vide_est_refusee(self):
        reponse = self.client_auteur.patch(
            self._url(), {"content": "   "}, format="json"
        )

        self.assertEqual(reponse.status_code, 400)
        self.message.refresh_from_db()
        self.assertEqual(self.message.content, "Reunion a 14h")

    def test_un_message_deja_retire_ne_se_corrige_pas(self):
        self.client_auteur.delete(self._url())

        reponse = self.client_auteur.patch(
            self._url(), {"content": "Rattrapage"}, format="json"
        )

        self.assertEqual(reponse.status_code, 400)

    def test_un_etranger_a_la_conversation_est_econduit(self):
        etranger = User.objects.create_user(
            username="etranger",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        client = APIClient()
        client.force_authenticate(etranger)

        reponse = client.delete(self._url())

        self.assertIn(reponse.status_code, (403, 404))
        self.message.refresh_from_db()
        self.assertIsNone(self.message.deleted_at)
