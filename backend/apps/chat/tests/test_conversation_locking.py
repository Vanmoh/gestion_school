"""Le verrou de conversation ne doit jamais porter sur un SELECT DISTINCT.

PostgreSQL rejette `FOR UPDATE` combine a `DISTINCT`. La requete de portee
l'est par construction (jointure sur les participants), donc verrouiller
directement dessus faisait echouer tout le cote ecriture du chat: envoi,
marquage lu, fermeture, envoi de fichier, gestion des groupes.

SQLite ignore purement et simplement select_for_update
(has_select_for_update = False), d'ou une suite de tests verte en local et une
panne systematique en production. Ce test verifie donc la forme de la requete,
independamment du moteur; les tests d'API l'exercent en plus sur PostgreSQL en
integration continue.
"""

from django.test import SimpleTestCase

from apps.chat.models import Conversation
from apps.chat.views import _locked_conversation_queryset


class ConversationLockShapeTests(SimpleTestCase):
    def test_the_locking_query_is_not_distinct(self):
        query = _locked_conversation_queryset(1).query

        self.assertTrue(query.select_for_update, "le verrou n'est pas demande")
        self.assertFalse(
            query.distinct,
            "FOR UPDATE combine a DISTINCT: PostgreSQL rejettera la requete",
        )

    def test_the_locking_query_carries_no_join(self):
        """Une jointure ramenerait le probleme par un autre chemin.

        On inspecte les tables de la requete plutot que son SQL: compiler un
        FOR UPDATE demande une connexion, ce qui ferait dependre ce test d'une
        base et, sur SQLite, lui ferait rater exactement ce qu'il verifie.
        """
        query = _locked_conversation_queryset(1).query

        self.assertEqual(
            list(query.alias_map),
            [Conversation._meta.db_table],
            "le verrou porte sur une requete jointe",
        )
