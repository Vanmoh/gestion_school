"""Effacer une annee scolaire: qui le peut, et ce qui l'en empeche.

La matrice ouvre le module academique en administration a la direction, pour
qu'elle ouvre, cloture et rouvre ses annees. Effacer n'est pas de cet ordre:
c'est le seul geste du module qu'aucun autre geste du module ne repare. Un
affinement le reserve donc au super administrateur.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.access import affinement_autorise
from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement


class SuppressionAnneeScolaireTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Suppression")

        self.super_admin = User.objects.create_user(
            username="superadmin_suppression_annee",
            password="pass123456",
            role=UserRole.SUPER_ADMIN,
            etablissement=self.etablissement,
        )
        self.directeur = User.objects.create_user(
            username="directeur_suppression_annee",
            password="pass123456",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )

        self.annee = AcademicYear.objects.create(
            name="2024-2025",
            start_date=date(2024, 9, 1),
            end_date=date(2025, 6, 30),
            etablissement=self.etablissement,
        )

    def _url(self, annee=None):
        return f"/api/academic-years/{(annee or self.annee).id}/"

    # --- La matrice -------------------------------------------------------

    def test_l_affinement_ne_vise_que_le_super_admin(self):
        self.assertTrue(
            affinement_autorise(UserRole.SUPER_ADMIN, "suppression_annee_scolaire")
        )
        for role in (
            UserRole.DIRECTOR,
            UserRole.CENSOR,
            UserRole.ACCOUNTANT,
            UserRole.TEACHER,
            UserRole.PARENT,
        ):
            self.assertFalse(
                affinement_autorise(role, "suppression_annee_scolaire"),
                msg=f"{role} ne doit pas pouvoir supprimer une annee",
            )

    def test_l_affinement_est_annonce_au_client(self):
        # Le bouton ne doit pas s'afficher pour se faire refuser au clic:
        # l'ecran lit cette table pour decider de le montrer.
        self.client.force_authenticate(self.directeur)
        reponse = self.client.get("/api/auth/permissions/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        capacites = reponse.data.get("capabilities") or {}
        self.assertIn("suppression_annee_scolaire", capacites)
        self.assertFalse(capacites["suppression_annee_scolaire"])

    # --- Le refus ---------------------------------------------------------

    def test_la_direction_ne_supprime_pas_une_annee(self):
        self.client.force_authenticate(self.directeur)

        reponse = self.client.delete(self._url())

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(AcademicYear.objects.filter(pk=self.annee.pk).exists())

    def test_le_super_admin_supprime_une_annee_vide(self):
        self.client.force_authenticate(self.super_admin)

        reponse = self.client.delete(self._url())

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(AcademicYear.objects.filter(pk=self.annee.pk).exists())

    # --- Ce qui retient ---------------------------------------------------

    def test_une_annee_qui_porte_des_donnees_ne_part_pas(self):
        ClassRoom.objects.create(
            name="6e A",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(self.super_admin)

        reponse = self.client.delete(self._url())

        self.assertEqual(reponse.status_code, status.HTTP_409_CONFLICT)
        self.assertTrue(AcademicYear.objects.filter(pk=self.annee.pk).exists())

    def test_le_refus_nomme_ce_qui_retient_et_en_quelle_quantite(self):
        # « Utilisee ailleurs » n'aide pas a decider: deux classes vides se
        # nettoient, trois mille notes non.
        for rang in range(3):
            ClassRoom.objects.create(
                name=f"6e {rang}",
                academic_year=self.annee,
                etablissement=self.etablissement,
            )
        self.client.force_authenticate(self.super_admin)

        reponse = self.client.delete(self._url())

        detail = str(reponse.data.get("detail", ""))
        self.assertIn("2024-2025", detail)
        self.assertIn("3", detail)

    def test_une_annee_d_une_autre_ecole_reste_hors_de_portee(self):
        autre = Etablissement.objects.create(name="Lycee Voisin Suppression")
        annee_voisine = AcademicYear.objects.create(
            name="2024-2025",
            start_date=date(2024, 9, 1),
            end_date=date(2025, 6, 30),
            etablissement=autre,
        )
        directeur_voisin = User.objects.create_user(
            username="directeur_voisin_suppression",
            password="pass123456",
            role=UserRole.DIRECTOR,
            etablissement=autre,
        )
        self.client.force_authenticate(directeur_voisin)

        reponse = self.client.delete(self._url(self.annee))

        self.assertIn(
            reponse.status_code,
            {status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND},
        )
        self.assertTrue(AcademicYear.objects.filter(pk=self.annee.pk).exists())
        self.assertTrue(AcademicYear.objects.filter(pk=annee_voisine.pk).exists())
