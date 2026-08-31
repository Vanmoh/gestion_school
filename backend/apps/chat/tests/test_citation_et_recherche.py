"""Repondre a un message precis, et retrouver ce qui a ete dit.

Dans un groupe actif, sans citation on ne sait plus a quoi repond quoi. Et
la recherche ne portait que sur les noms de conversations: retrouver « la
note de service sur les conges » demandait de remonter le fil a la main.
"""

from django.test import TestCase
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.chat.models import ChatMessage, Conversation, ConversationParticipant
from apps.school.models import Etablissement


class CitationEtRechercheTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="IFP-OBK Test",
            address="Quartier test",
            phone="670000000",
            email="test@ifp-obk.com",
        )
        self.censeur = User.objects.create_user(
            username="censeur",
            password="Pass1234!",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
            first_name="Ousseini",
            last_name="Sissoko",
        )
        self.enseignant = User.objects.create_user(
            username="enseignant",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )

        self.conversation = Conversation.objects.create(
            is_group=True, title="Salle des profs", etablissement=self.etablissement
        )
        self.ailleurs = Conversation.objects.create(
            is_group=False, etablissement=self.etablissement
        )
        for conversation in (self.conversation, self.ailleurs):
            for compte in (self.censeur, self.enseignant):
                ConversationParticipant.objects.create(
                    conversation=conversation, user=compte
                )

        self.client = APIClient()
        self.client.force_authenticate(self.enseignant)

    def _envoyer(self, contenu, reply_to=None):
        return self.client.post(
            f"/api/chat/conversations/{self.conversation.id}/send/",
            {"content": contenu, "reply_to": reply_to},
            format="json",
        )

    def test_une_reponse_cite_le_message_vise(self):
        vise = ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.censeur,
            content="Qui peut surveiller la retenue de samedi ?",
        )

        reponse = self._envoyer("Moi", reply_to=vise.id)

        self.assertEqual(reponse.status_code, 201, reponse.data)
        self.assertEqual(reponse.data["reply_to"], vise.id)
        apercu = reponse.data["reply_to_apercu"]
        self.assertEqual(apercu["sender_name"], "Ousseini Sissoko")
        self.assertIn("retenue", apercu["extrait"])

    def test_on_ne_cite_pas_un_message_d_une_autre_conversation(self):
        """Sinon la citation ferait fuiter un extrait de l'autre fil."""
        etranger = ChatMessage.objects.create(
            conversation=self.ailleurs,
            sender=self.censeur,
            content="Sujet confidentiel",
        )

        reponse = self._envoyer("Bien recu", reply_to=etranger.id)

        self.assertEqual(reponse.status_code, 201)
        self.assertIsNone(reponse.data["reply_to"])
        self.assertIsNone(reponse.data["reply_to_apercu"])

    def test_citer_un_message_retire_ne_ressuscite_pas_son_texte(self):
        vise = ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.censeur,
            content="Texte a retirer",
        )
        self._envoyer("Compris", reply_to=vise.id)
        self.client.force_authenticate(self.censeur)
        self.client.delete(f"/api/chat/messages/{vise.id}/")
        self.client.force_authenticate(self.enseignant)

        page = self.client.get(
            f"/api/chat/conversations/{self.conversation.id}/messages/"
        )
        citation = next(
            m["reply_to_apercu"] for m in page.data if m["reply_to"] == vise.id
        )
        self.assertNotIn("Texte a retirer", citation["extrait"])
        self.assertEqual(citation["extrait"], "Message retire")

    def test_la_recherche_porte_sur_le_contenu(self):
        ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.censeur,
            content="Note de service sur les conges de fin d annee",
        )
        ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.censeur,
            content="Rappel: conseil de classe mardi",
        )

        reponse = self.client.get(
            f"/api/chat/conversations/{self.conversation.id}/messages/",
            {"q": "conges"},
        )

        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(len(reponse.data), 1)
        self.assertIn("conges", reponse.data[0]["content"])

    def test_la_recherche_ignore_la_casse(self):
        ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.censeur,
            content="Reunion PEDAGOGIQUE",
        )

        reponse = self.client.get(
            f"/api/chat/conversations/{self.conversation.id}/messages/",
            {"q": "pedagogique"},
        )

        self.assertEqual(len(reponse.data), 1)

    def test_la_recherche_ne_ramene_pas_les_messages_retires(self):
        vise = ChatMessage.objects.create(
            conversation=self.conversation,
            sender=self.enseignant,
            content="Erreur de destinataire",
        )
        self.client.delete(f"/api/chat/messages/{vise.id}/")

        reponse = self.client.get(
            f"/api/chat/conversations/{self.conversation.id}/messages/",
            {"q": "destinataire"},
        )

        self.assertEqual(len(reponse.data), 0)

    def test_sans_recherche_le_fil_reste_entier(self):
        for i in range(3):
            ChatMessage.objects.create(
                conversation=self.conversation,
                sender=self.censeur,
                content=f"Message {i}",
            )

        reponse = self.client.get(
            f"/api/chat/conversations/{self.conversation.id}/messages/"
        )

        self.assertEqual(len(reponse.data), 3)
