"""Les comptes de demonstration ne doivent pas survivre a la mise en ligne.

`seed_demo_data` cree huit comptes dont le mot de passe etait publie dans le
README, `superadmin` compris -- qui est super-utilisateur. Le guide de
deploiement demandait par ailleurs de semer la base cloud: ces comptes ont
donc existe en ligne, ouverts a qui avait lu le depot.

Trois barrieres ferment cette porte, et chacune est verifiee ici: le refus
de semer hors developpement, le controle qui les signale a chaque demarrage,
et la commande qui les enleve.
"""

from io import StringIO
from unittest.mock import patch

from django.core.management import CommandError, call_command
from django.test import SimpleTestCase, TestCase, override_settings

from apps.accounts.models import User, UserRole
from apps.common import checks
from apps.common.management.commands.seed_demo_data import Command as SeedDemoData
from apps.common.comptes_demo import (
    NOMS_DES_COMPTES_DE_DEMONSTRATION,
    comptes_de_demonstration_presents,
)


class SeedRefusEnProductionTests(TestCase):
    """Django force DEBUG=False sous test: la base de test est donc exemptee.

    Ces tests font semblant de tourner sur une vraie base pour verifier le
    refus, puisque c'est precisement le cas qu'aucun test ne rencontre
    naturellement.
    """

    def _faire_passer_pour_une_vraie_base(self):
        patch_base = patch.object(
            SeedDemoData, "_tourne_sur_une_base_de_test", staticmethod(lambda: False)
        )
        patch_base.start()
        self.addCleanup(patch_base.stop)

    @override_settings(DEBUG=False)
    def test_il_refuse_de_semer_quand_debug_est_faux(self):
        self._faire_passer_pour_une_vraie_base()

        with self.assertRaises(CommandError) as erreur:
            call_command("seed_demo_data", stdout=StringIO())

        self.assertIn("DEBUG=False", str(erreur.exception))
        self.assertFalse(comptes_de_demonstration_presents().exists())

    @override_settings(DEBUG=False)
    def test_forcer_reste_possible_pour_une_base_jetable(self):
        """Une base de recette doit pouvoir etre semee malgre DEBUG=False."""
        self._faire_passer_pour_une_vraie_base()

        call_command("seed_demo_data", "--forcer", stdout=StringIO())

        self.assertTrue(comptes_de_demonstration_presents().exists())

    @override_settings(DEBUG=False)
    def test_une_base_de_test_n_est_pas_prise_pour_une_production(self):
        """Sans cette exception, tous les tests qui sement seraient coupes."""
        call_command("seed_demo_data", stdout=StringIO())

        self.assertTrue(comptes_de_demonstration_presents().exists())


class ControleDesComptesDemoTests(TestCase):
    def _creer_comptes(self):
        User.objects.create_user(
            username="superadmin", password="x", role=UserRole.SUPER_ADMIN
        )
        User.objects.create_user(
            username="eleve1", password="x", role=UserRole.STUDENT
        )

    @override_settings(DEBUG=False)
    def test_il_signale_les_comptes_presents_en_production(self):
        self._creer_comptes()

        trouves = checks.demonstration_accounts_are_gone_in_production(None)

        self.assertEqual(len(trouves), 1)
        self.assertEqual(trouves[0].id, checks.W005_COMPTES_DEMO)
        self.assertIn("superadmin", trouves[0].msg)
        self.assertIn("eleve1", trouves[0].msg)

    @override_settings(DEBUG=False)
    def test_il_se_tait_quand_la_base_est_propre(self):
        User.objects.create_user(
            username="directrice.reelle", password="x", role=UserRole.DIRECTOR
        )

        self.assertEqual(
            checks.demonstration_accounts_are_gone_in_production(None), []
        )

    @override_settings(DEBUG=True)
    def test_le_developpement_n_est_pas_concerne(self):
        self._creer_comptes()

        self.assertEqual(
            checks.demonstration_accounts_are_gone_in_production(None), []
        )


class PurgeDesComptesDemoTests(TestCase):
    def setUp(self):
        for nom in NOMS_DES_COMPTES_DE_DEMONSTRATION:
            User.objects.create_user(
                username=nom,
                password="motdepasse-connu",
                role=UserRole.SUPER_ADMIN if nom == "superadmin" else UserRole.STUDENT,
                is_superuser=nom == "superadmin",
            )
        self.reelle = User.objects.create_user(
            username="directrice.reelle", password="x", role=UserRole.DIRECTOR
        )

    def _appeler(self, *args):
        sortie = StringIO()
        call_command("purger_comptes_demo", *args, stdout=sortie)
        return sortie.getvalue()

    def test_elle_supprime_les_comptes_de_demonstration(self):
        self._appeler()

        self.assertFalse(comptes_de_demonstration_presents().exists())

    def test_elle_ne_touche_pas_aux_comptes_reels(self):
        self._appeler()

        self.assertTrue(User.objects.filter(pk=self.reelle.pk).exists())

    def test_la_simulation_ne_supprime_rien(self):
        sortie = self._appeler("--dry-run")

        self.assertIn("[simulation]", sortie)
        self.assertEqual(
            comptes_de_demonstration_presents().count(),
            len(NOMS_DES_COMPTES_DE_DEMONSTRATION),
        )

    def test_desactiver_ferme_sans_effacer(self):
        """Le choix a faire si un compte de demo a servi de compte de travail."""
        self._appeler("--desactiver")

        comptes = comptes_de_demonstration_presents()
        self.assertEqual(comptes.count(), len(NOMS_DES_COMPTES_DE_DEMONSTRATION))
        self.assertFalse(comptes.filter(is_active=True).exists())

    def test_desactiver_retire_aussi_les_privileges(self):
        """Un `is_active = True` pose par megarde ne doit pas rouvrir l'admin."""
        self._appeler("--desactiver")

        superadmin = User.objects.get(username="superadmin")
        self.assertFalse(superadmin.is_superuser)
        self.assertFalse(superadmin.is_staff)
        self.assertFalse(superadmin.has_usable_password())

    def test_sur_une_base_propre_elle_le_dit_sans_echouer(self):
        self._appeler()

        sortie = self._appeler()

        self.assertIn("Aucun compte de demonstration", sortie)


class ListeDesComptesTests(SimpleTestCase):
    def test_la_liste_couvre_les_comptes_semes(self):
        """Un compte ajoute au seed sans l'etre ici echapperait a la purge."""
        import re
        from pathlib import Path

        from django.conf import settings

        source = (
            Path(settings.BASE_DIR)
            / "apps/common/management/commands/seed_demo_data.py"
        ).read_text(encoding="utf-8")
        semes = set(re.findall(r'username="([a-z0-9_.]+)"', source))

        self.assertEqual(semes, set(NOMS_DES_COMPTES_DE_DEMONSTRATION))
