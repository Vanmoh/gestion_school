"""Supprimer un compte demande toujours une confirmation.

La confirmation n'etait exigee que si le compte portait des donnees liees.
Un compte nu -- un parent sans enfant rattache, un comptable, un surveillant
-- partait donc au premier appel, sans question. Pire: l'ecran obtenait
l'inventaire de ce qu'une suppression emporterait en lancant cette
suppression et en lisant le refus. Un compte sans rien d'attache etait donc
detruit a l'instant ou l'ecran cherchait a savoir ce qu'il emportait.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student, Teacher


class SuppressionDeCompteTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Suppression", code="ESUP")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 supp",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.admin = User.objects.create_user(
            username="admin_suppression",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.admin)

    def _compte_nu(self, username="compte_nu"):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )

    def _compte_charge(self, username="compte_charge"):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        Teacher.objects.create(
            user=user,
            employee_code=f"EMP-{username[:8]}",
            hire_date=date(2025, 9, 1),
            etablissement=self.etablissement,
        )
        return user

    def _supprimer(self, user, **params):
        suffixe = "?confirm=true" if params.get("confirme") else ""
        return self.client.delete(
            f"/api/auth/users/{user.id}/{suffixe}",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_un_compte_nu_ne_part_pas_sans_confirmation(self):
        # Le defaut signale: il partait au premier appel, sans question.
        compte = self._compte_nu()

        reponse = self._supprimer(compte)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=compte.pk).exists())
        self.assertIn("définitive", str(reponse.data["detail"]))

    def test_un_compte_nu_part_une_fois_confirme(self):
        compte = self._compte_nu("compte_nu_confirme")

        reponse = self._supprimer(compte, confirme=True)

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(pk=compte.pk).exists())

    def test_un_compte_charge_annonce_ce_qu_il_emporte(self):
        compte = self._compte_charge()

        reponse = self._supprimer(compte)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=compte.pk).exists())
        self.assertIn("linked_data", reponse.data)

    def test_l_inventaire_se_lit_sans_rien_detruire(self):
        # C'est le coeur du defaut: demander « qu'est-ce que cela emporte ? »
        # ne doit pas emporter le compte.
        compte = self._compte_charge("compte_inventaire")

        reponse = self.client.get(
            f"/api/auth/users/{compte.id}/donnees-liees/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertIn("linked_data", reponse.data)
        self.assertTrue(User.objects.filter(pk=compte.pk).exists())

    def test_l_inventaire_d_un_compte_nu_est_vide_et_le_laisse_vivre(self):
        compte = self._compte_nu("compte_nu_inventaire")

        reponse = self.client.get(
            f"/api/auth/users/{compte.id}/donnees-liees/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["linked_data"], {})
        self.assertTrue(User.objects.filter(pk=compte.pk).exists())

    def test_on_ne_supprime_pas_son_propre_compte(self):
        reponse = self._supprimer(self.admin, confirme=True)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=self.admin.pk).exists())
