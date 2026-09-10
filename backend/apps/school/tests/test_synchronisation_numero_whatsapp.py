"""Le numéro WhatsApp suit le téléphone, sans qu'on y pense.

Il existe deux numéros: `User.phone`, champ de répertoire modifié dans
Gestion utilisateurs, et `ParentProfile.whatsapp_phone`, seul utilisé pour
l'envoi des bulletins. On corrigeait le premier en croyant avoir tout fait,
et l'envoi partait sur l'ancien numéro — ou sur rien.

La règle: le numéro WhatsApp suit le téléphone **tant que personne ne les a
dissociés**. Un numéro saisi volontairement différent — le portable du tuteur
quand la fiche porte le fixe du domicile — n'est jamais écrasé.
"""

from django.test import TestCase, override_settings

from apps.accounts.models import User, UserRole
from apps.school.models import Etablissement, ParentProfile


@override_settings(DEFAULT_PHONE_COUNTRY_CODE="223", NATIONAL_PHONE_LENGTH=8)
class SynchronisationDuNumeroTests(TestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Synchro")

    def _parent(self, telephone="76 12 34 56", whatsapp=""):
        user = User.objects.create_user(
            username=f"parent_{telephone.replace(' ', '')}",
            password="Pass1234!",
            role=UserRole.PARENT,
            phone=telephone,
            etablissement=self.etablissement,
        )
        profil = ParentProfile.objects.create(
            user=user, etablissement=self.etablissement, whatsapp_phone=whatsapp
        )
        return user, profil

    # ----- le cas qui posait problème ------------------------------------

    def test_corriger_le_telephone_met_a_jour_le_numero_whatsapp(self):
        """C'est exactement le geste qui ne servait à rien."""
        user, profil = self._parent(telephone="76 12 34 56")
        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22376123456")

        user.phone = "66 74 22 32"
        user.save(update_fields=["phone"])

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22366742232")

    def test_un_numero_whatsapp_vide_se_remplit(self):
        user, profil = self._parent(telephone="", whatsapp="")
        self.assertEqual(profil.whatsapp_phone, "")

        user.phone = "76 12 34 56"
        user.save(update_fields=["phone"])

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22376123456")

    def test_le_format_international_est_accepte(self):
        user, profil = self._parent(telephone="")

        user.phone = "+223 66 74 22 32"
        user.save(update_fields=["phone"])

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22366742232")

    # ----- ce qui ne doit jamais être écrasé -----------------------------

    def test_un_numero_dissocie_est_respecte(self):
        """Le portable du tuteur, quand la fiche porte le fixe du domicile."""
        user, profil = self._parent(
            telephone="76 12 34 56", whatsapp="+22399887766"
        )

        user.phone = "66 74 22 32"
        user.save(update_fields=["phone"])

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22399887766")

    def test_un_telephone_illisible_ne_devine_rien(self):
        """Deux numéros dans la même case: lequel est celui du tuteur ?"""
        user, profil = self._parent(telephone="76 12 34 56")
        profil.refresh_from_db()
        avant = profil.whatsapp_phone

        user.phone = "76 12 34 56 / bureau 66 74 22 32"
        user.save(update_fields=["phone"])

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, avant)

    def test_vider_le_telephone_n_efface_pas_le_numero_whatsapp(self):
        """Effacer un contact ne doit pas couper l'envoi en silence."""
        user, profil = self._parent(telephone="76 12 34 56")
        profil.refresh_from_db()

        user.phone = ""
        user.save(update_fields=["phone"])

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22376123456")

    # ----- portée ---------------------------------------------------------

    def test_un_compte_sans_fiche_parent_ne_declenche_rien(self):
        enseignant = User.objects.create_user(
            username="enseignant_synchro",
            password="Pass1234!",
            role=UserRole.TEACHER,
            phone="76 12 34 56",
            etablissement=self.etablissement,
        )

        enseignant.phone = "66 74 22 32"
        enseignant.save(update_fields=["phone"])

        self.assertFalse(ParentProfile.objects.filter(user=enseignant).exists())

    def test_enregistrer_sans_changer_le_telephone_ne_casse_rien(self):
        user, profil = self._parent(
            telephone="76 12 34 56", whatsapp="+22399887766"
        )

        user.first_name = "Awa"
        user.save(update_fields=["first_name"])

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22399887766")

    def test_la_synchronisation_survit_a_un_save_complet(self):
        """`save()` sans `update_fields`: le chemin de l'admin Django."""
        user, profil = self._parent(telephone="76 12 34 56")
        profil.refresh_from_db()

        user.phone = "66 74 22 32"
        user.save()

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22366742232")
