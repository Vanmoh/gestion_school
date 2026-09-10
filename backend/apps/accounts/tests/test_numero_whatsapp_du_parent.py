"""Le numéro WhatsApp, là où l'administration corrige les contacts.

Il existe deux numéros: `User.phone`, champ de répertoire modifié dans
Gestion utilisateurs, et `ParentProfile.whatsapp_phone`, seul utilisé pour
l'envoi des bulletins. Ils ont été séparés à dessein — le second n'admet
qu'une forme, E.164, quand le premier porte souvent deux numéros ou une note
(« bureau »).

Mais rien ne le disait: on corrigeait le téléphone dans Gestion utilisateurs,
on croyait avoir tout fait, et l'envoi continuait de partir sur l'ancien
numéro — ou sur rien.
"""

from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import Etablissement, ParentProfile


@override_settings(DEFAULT_PHONE_COUNTRY_CODE="223", NATIONAL_PHONE_LENGTH=8)
class NumeroWhatsAppDuParentTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee des Contacts")
        self.directeur = User.objects.create_user(
            username="directeur_contacts",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.parent_user = User.objects.create_user(
            username="parent_contacts",
            password="Pass1234!",
            role=UserRole.PARENT,
            phone="76 12 34 56",
            etablissement=self.etablissement,
        )
        self.parent = ParentProfile.objects.create(
            user=self.parent_user, etablissement=self.etablissement
        )
        self.client.force_authenticate(self.directeur)

    def _fiche(self):
        reponse = self.client.get(f"/api/auth/users/{self.parent_user.id}/")
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        return reponse.data

    # ----- ce que la fiche montre ---------------------------------------

    def test_la_fiche_porte_le_numero_whatsapp(self):
        self.parent.whatsapp_phone = "+22376123456"
        self.parent.save(update_fields=["whatsapp_phone"])

        self.assertEqual(self._fiche()["whatsapp_phone"], "+22376123456")

    def test_elle_porte_aussi_l_accord_du_parent(self):
        """Sans accord, aucun envoi n'est préparé: il faut le voir ici."""
        self.assertFalse(self._fiche()["whatsapp_consent"])

    def test_sans_numero_whatsapp_le_telephone_est_propose(self):
        fiche = self._fiche()

        self.assertEqual(fiche["whatsapp_phone"], "")
        self.assertEqual(fiche["whatsapp_phone_suggestion"], "+22376123456")

    def test_rien_n_est_propose_quand_le_numero_existe_deja(self):
        self.parent.whatsapp_phone = "+22366000000"
        self.parent.save(update_fields=["whatsapp_phone"])

        self.assertEqual(self._fiche()["whatsapp_phone_suggestion"], "")

    def test_un_telephone_illisible_ne_propose_rien(self):
        """« 76 12 34 56 / bureau 66 74 22 32 » ne se tranche pas tout seul."""
        self.parent_user.phone = "76 12 34 56 / bureau 66 74 22 32"
        self.parent_user.save(update_fields=["phone"])

        self.assertEqual(self._fiche()["whatsapp_phone_suggestion"], "")

    def test_un_compte_sans_fiche_parent_n_a_rien_a_proposer(self):
        enseignant = User.objects.create_user(
            username="enseignant_contacts",
            password="Pass1234!",
            role=UserRole.TEACHER,
            phone="76 99 88 77",
            etablissement=self.etablissement,
        )

        reponse = self.client.get(f"/api/auth/users/{enseignant.id}/")

        self.assertEqual(reponse.data["whatsapp_phone"], "")
        self.assertEqual(reponse.data["whatsapp_phone_suggestion"], "")

    # ----- ce qu'on peut y corriger --------------------------------------

    def test_le_numero_whatsapp_se_corrige_depuis_la_fiche(self):
        reponse = self.client.patch(
            f"/api/auth/users/{self.parent_user.id}/",
            {"whatsapp_phone_input": "66 74 22 32"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.parent.refresh_from_db()
        self.assertEqual(self.parent.whatsapp_phone, "+22366742232")

    def test_il_est_normalise_a_la_saisie(self):
        """Le champ n'admet qu'une forme: elle est produite, pas exigée."""
        self.client.patch(
            f"/api/auth/users/{self.parent_user.id}/",
            {"whatsapp_phone_input": "+223 76 12 34 56"},
            format="json",
        )

        self.parent.refresh_from_db()
        self.assertEqual(self.parent.whatsapp_phone, "+22376123456")

    def test_un_numero_illisible_est_refuse(self):
        reponse = self.client.patch(
            f"/api/auth/users/{self.parent_user.id}/",
            {"whatsapp_phone_input": "pas un numero"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("whatsapp_phone_input", reponse.data)

    def test_le_vider_est_possible(self):
        self.parent.whatsapp_phone = "+22376123456"
        self.parent.save(update_fields=["whatsapp_phone"])

        self.client.patch(
            f"/api/auth/users/{self.parent_user.id}/",
            {"whatsapp_phone_input": ""},
            format="json",
        )

        self.parent.refresh_from_db()
        self.assertEqual(self.parent.whatsapp_phone, "")

    def test_corriger_le_telephone_seul_ne_touche_pas_au_numero_whatsapp(self):
        """Le piège d'origine, fixé pour qu'il reste visible.

        Les deux champs restent distincts: c'est voulu. Ce qui change, c'est
        qu'on voit désormais les deux au même endroit, et qu'on peut corriger
        le second sans quitter l'écran.
        """
        self.parent.whatsapp_phone = "+22376123456"
        self.parent.save(update_fields=["whatsapp_phone"])

        self.client.patch(
            f"/api/auth/users/{self.parent_user.id}/",
            {"phone": "66 00 00 00"},
            format="json",
        )

        self.parent.refresh_from_db()
        self.assertEqual(self.parent.whatsapp_phone, "+22376123456")

    def test_le_numero_ne_s_applique_pas_a_un_compte_sans_fiche_parent(self):
        enseignant = User.objects.create_user(
            username="enseignant_sans_profil",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )

        reponse = self.client.patch(
            f"/api/auth/users/{enseignant.id}/",
            {"whatsapp_phone_input": "76 12 34 56"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
