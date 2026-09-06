"""Ce que la normalisation accepte, et surtout ce qu'elle refuse.

Le refus est ici la partie qui compte: un numero mal devine envoie le
bulletin d'un enfant chez un inconnu, et rien ne le rattrape.
"""

from django.test import SimpleTestCase, override_settings

from apps.school.phone_utils import est_au_format_e164, normaliser_numero


@override_settings(DEFAULT_PHONE_COUNTRY_CODE="223")
class NormalisationDesNumerosTests(SimpleTestCase):
    def test_les_formes_courantes_donnent_le_meme_numero(self):
        """Toutes les habitudes de saisie mènent au même E.164."""
        for saisie in (
            "76123456",
            "76 12 34 56",
            "76-12-34-56",
            "76.12.34.56",
            " 76 12 34 56 ",
            "+22376123456",
            "+223 76 12 34 56",
            "00223 76 12 34 56",
            "223 76 12 34 56",
            "(223) 76-12-34-56",
        ):
            with self.subTest(saisie=saisie):
                self.assertEqual(normaliser_numero(saisie), "+22376123456")

    def test_deux_numeros_dans_la_meme_case_sont_refuses(self):
        """La forme la plus repandue des fiches papier, et la plus piegeuse.

        Prendre le premier des deux reviendrait a decider a la place de
        l'ecole a quel telephone envoyer le bulletin d'un eleve.
        """
        for saisie in (
            "76 12 34 56 / 66 74 22 32",
            "76123456, 66742232",
            "76123456 ou 66742232",
            "76123456; 66742232",
        ):
            with self.subTest(saisie=saisie):
                self.assertIsNone(normaliser_numero(saisie))

    def test_une_saisie_inexploitable_est_refusee(self):
        for saisie in ("", None, "   ", "bureau", "76 12 34", "76123456x", "+"):
            with self.subTest(saisie=saisie):
                self.assertIsNone(normaliser_numero(saisie))

    def test_le_zero_national_de_tete_ne_survit_pas_a_l_indicatif(self):
        """« 077... » compose localement devient « +22377... », pas « +2230... »."""
        self.assertEqual(normaliser_numero("077123456"), "+22377123456")

    def test_un_numero_deja_international_garde_son_pays(self):
        """L'indicatif par defaut ne recouvre jamais un « + » explicite."""
        self.assertEqual(normaliser_numero("+33612345678"), "+33612345678")

    @override_settings(DEFAULT_PHONE_COUNTRY_CODE="")
    def test_sans_indicatif_configure_un_numero_national_est_refuse(self):
        """« 76123456 » n'existe pas hors de son pays: on ne l'invente pas."""
        self.assertIsNone(normaliser_numero("76123456"))
        self.assertEqual(normaliser_numero("+22376123456"), "+22376123456")

    def test_le_controle_de_format_ne_transforme_rien(self):
        self.assertTrue(est_au_format_e164("+22376123456"))
        self.assertFalse(est_au_format_e164("76123456"))
        self.assertFalse(est_au_format_e164("+0223761234"))
        self.assertFalse(est_au_format_e164(""))
