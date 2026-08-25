"""Le catalogage confie au worker: la remise du message, et ses garde-fous.

Le service web ne catalogue plus le fonds lui-meme au demarrage; il depose un
message dans la file. Ce qui se teste ici n'est donc pas l'import (voir
test_library_documents) mais la remise: quels arguments partent, et surtout ce
qui arrive quand le courtier ne repond pas -- car un demarrage d'API ne doit
jamais dependre de Redis.
"""

from io import StringIO
from unittest.mock import Mock, patch

from django.conf import settings
from django.core.management import call_command
from django.test import SimpleTestCase

from apps.school import tasks
from apps.school.management.commands import queue_library_catalogue

CHEMIN = "apps.school.management.commands.queue_library_catalogue.import_library_catalogue"


class QueueLibraryCatalogueCommandTests(SimpleTestCase):
    """La commande lancee par entrypoint.sh a chaque demarrage du conteneur."""

    def _lancer(self, *args, tache=None):
        sortie, erreurs = StringIO(), StringIO()
        with patch(CHEMIN, tache or Mock()) as double:
            call_command(
                "queue_library_catalogue", *args, stdout=sortie, stderr=erreurs
            )
        return double, sortie.getvalue(), erreurs.getvalue()

    def test_le_message_part_sans_recataloguer_ce_qui_l_est_deja(self):
        """Render reveille le service bien plus souvent qu'il ne le deploie."""
        tache, sortie, _ = self._lancer()

        tache.delay.assert_called_once_with(si_vide=True)
        self.assertIn("Catalogue confie au worker", sortie)

    def test_forcer_relit_la_source_malgre_le_catalogue_en_place(self):
        tache, _, _ = self._lancer("--forcer")

        tache.delay.assert_called_once_with(si_vide=False)

    def test_un_courtier_injoignable_ne_bloque_pas_le_demarrage(self):
        """Le cas qui compte: sans Redis, l'API doit demarrer quand meme.

        Une exception ici remonterait dans entrypoint.sh, et le conteneur ne
        servirait plus rien -- pour un catalogue dont l'absence se rattrape
        toute seule (relais de la source, puis tache planifiee de 3h15).
        """
        muet = Mock()
        muet.delay.side_effect = OSError("Connection refused")

        _, sortie, erreurs = self._lancer(tache=muet)

        self.assertIn("file de travaux injoignable", erreurs)
        self.assertNotIn("confie au worker", sortie)

    def test_la_commande_ne_catalogue_rien_elle_meme(self):
        """Aucun appel a la source depuis le processus web, meme indirect."""
        with patch.object(queue_library_catalogue, "import_library_catalogue", Mock()):
            with patch("apps.school.tasks.call_command") as import_reel:
                call_command("queue_library_catalogue", stdout=StringIO())

        import_reel.assert_not_called()


class ImportLibraryCatalogueTaskTests(SimpleTestCase):
    """La tache elle-meme, executee cote worker."""

    def test_la_tache_catalogue_sans_rapatrier_aucun_fichier(self):
        """Plusieurs gigaoctets n'ont rien a faire dans une file declenchee
        a chaque demarrage: le rapatriement reste manuel."""
        with patch("apps.school.tasks.call_command") as commande:
            tasks.import_library_catalogue()

        commande.assert_called_once_with(
            "import_bkalan", "--catalogue-seul", "--si-vide"
        )

    def test_sans_si_vide_la_source_est_relue(self):
        with patch("apps.school.tasks.call_command") as commande:
            tasks.import_library_catalogue(si_vide=False)

        commande.assert_called_once_with("import_bkalan", "--catalogue-seul")

    def test_le_filet_planifie_designe_une_tache_qui_existe(self):
        """CELERY_BEAT_SCHEDULE nomme la tache par une chaine: renommer la
        fonction casserait le rendez-vous de 3h15 sans qu'aucun import ne
        proteste."""
        nomme = settings.CELERY_BEAT_SCHEDULE["catalogue-fonds-documentaire"]["task"]

        self.assertEqual(nomme, tasks.import_library_catalogue.name)
