"""Un lien de bulletin doit sortir du bâtiment.

Sans `PUBLIC_BASE_URL`, le lien était bâti sur l'adresse de la requête.
Préparé depuis l'application servie en Wi-Fi, il portait celle du poste —
« http://192.168.1.25:8000 » — et le parent qui cliquait depuis sa connexion
mobile n'ouvrait rien. WhatsApp ne le rendait même pas cliquable: une adresse
IP privée avec un port n'est pas linkifiée.

L'envoi refuse désormais de partir dans ce cas. Bloquer plutôt qu'avertir:
soixante liens morts partis à soixante familles font soixante appels à
l'école, et personne ne sait pourquoi.
"""

from django.test import SimpleTestCase, override_settings

from apps.reports.bulletin_delivery import (
    base_est_publique,
    base_publique,
    motif_de_base_non_publique,
    texte_du_message,
)


class BasePubliqueTests(SimpleTestCase):
    def test_un_domaine_en_https_sort(self):
        self.assertTrue(
            base_est_publique("https://gestion-school-jkzf.onrender.com")
        )

    def test_un_domaine_en_http_sort_aussi(self):
        """Le schéma n'est pas le critère: la joignabilité l'est."""
        self.assertTrue(base_est_publique("http://ecole.ml"))

    def test_une_adresse_de_reseau_local_ne_sort_pas(self):
        for adresse in (
            "http://192.168.1.25:8000",
            "http://10.0.0.4:8000",
            "http://172.17.0.2:8000",
            "http://172.31.255.1",
            "http://127.0.0.1:8000",
            "http://localhost:8000",
            "http://serveur-ecole.local",
        ):
            with self.subTest(adresse=adresse):
                self.assertFalse(base_est_publique(adresse))

    def test_une_adresse_publique_en_172_sort(self):
        """La plage privée s'arrête à 172.31: 172.32 est publique."""
        self.assertTrue(base_est_publique("http://172.32.0.1"))
        self.assertTrue(base_est_publique("http://172.15.0.1"))

    def test_une_base_vide_ne_sort_pas(self):
        # Le lien serait relatif: ni ouvrable, ni cliquable.
        self.assertFalse(base_est_publique(""))

    def test_une_adresse_sans_schema_ne_sort_pas(self):
        self.assertFalse(base_est_publique("ecole.ml"))

    def test_un_nom_sans_point_ne_sort_pas(self):
        self.assertFalse(base_est_publique("http://serveur-ecole:8000"))

    def test_le_motif_dit_comment_corriger(self):
        motif = motif_de_base_non_publique("http://192.168.1.25:8000")

        self.assertIn("192.168.1.25", motif)
        self.assertIn("PUBLIC_BASE_URL", motif)

    def test_le_motif_couvre_aussi_l_absence_de_reglage(self):
        motif = motif_de_base_non_publique("")

        self.assertIn("aucune adresse publique", motif)
        self.assertIn("PUBLIC_BASE_URL", motif)


class BasePubliquePrimeSurLaRequeteTests(SimpleTestCase):
    class _Requete:
        def build_absolute_uri(self, chemin):
            return f"http://192.168.1.25:8000{chemin}"

    @override_settings(PUBLIC_BASE_URL="https://api.ecole.ml")
    def test_le_reglage_l_emporte_sur_la_requete(self):
        self.assertEqual(base_publique(self._Requete()), "https://api.ecole.ml")

    @override_settings(PUBLIC_BASE_URL="")
    def test_sans_reglage_la_requete_sert_de_repli(self):
        # Ce repli est précisément ce qui produisait des liens locaux.
        self.assertEqual(
            base_publique(self._Requete()), "http://192.168.1.25:8000"
        )


class MessageAuParentTests(SimpleTestCase):
    def _message(self, lien="https://api.ecole.ml/api/reports/bulletin-partage/1/1/T1/999/abc/"):
        return texte_du_message(
            nom_eleve="Awa Traoré",
            nom_classe="6A",
            periode="T1",
            annee="2025-2026",
            nom_ecole="Lycée Test",
            lien=lien,
        )

    def test_le_lien_est_seul_sur_sa_ligne(self):
        """Une ponctuation accolée casse la détection chez certains clients."""
        lien = "https://api.ecole.ml/api/reports/bulletin-partage/1/1/T1/999/abc/"
        lignes = self._message(lien).split("\n")

        self.assertIn(lien, lignes)
        ligne_du_lien = lignes[lignes.index(lien)]
        self.assertEqual(ligne_du_lien.strip(), ligne_du_lien)

    def test_le_message_ne_s_ouvre_pas_sur_une_URL(self):
        """Un message qui commence par un lien ressemble à une arnaque."""
        self.assertFalse(self._message().startswith("http"))

    def test_il_nomme_l_eleve_et_l_ecole(self):
        message = self._message()

        self.assertIn("Awa Traoré", message)
        self.assertIn("Lycée Test", message)
