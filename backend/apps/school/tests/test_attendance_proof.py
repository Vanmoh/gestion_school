"""Le justificatif d'absence: depot, remplacement, retrait.

Le champ `proof` existait en base depuis l'origine et les statistiques
mensuelles comptaient deja les justificatifs -- mais aucune route ne
permettait d'en deposer un, si bien que le compteur affichait zero en
permanence.
"""

from datetime import date, timedelta

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Attendance,
    AttendanceSheetValidation,
    ClassRoom,
    Etablissement,
    Student,
)

SHEET_URL = "/api/attendances/class-sheet/"


def _fichier(nom="mot_excuse.pdf"):
    return SimpleUploadedFile(nom, b"%PDF-1.4 mot d'excuse", content_type="application/pdf")


class AttendanceProofTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.jour = date.today() - timedelta(days=1)

        cls.eleve = cls._eleve("absent")
        cls.present = cls._eleve("present")

        cls.absence = Attendance.objects.create(
            student=cls.eleve, date=cls.jour, is_absent=True, reason="Maladie"
        )
        cls.presence = Attendance.objects.create(student=cls.present, date=cls.jour)

        cls.surveillant = cls._compte("surveillant_proof", UserRole.SUPERVISOR)
        cls.directeur = cls._compte("directeur_proof", UserRole.DIRECTOR)
        cls.comptable = cls._compte("comptable_proof", UserRole.ACCOUNTANT)

    @classmethod
    def _eleve(cls, suffixe):
        user = User.objects.create_user(
            username=f"eleve_{suffixe}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=user, classroom=cls.classe, etablissement=cls.etablissement
        )

    @classmethod
    def _compte(cls, username, role):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=role,
            etablissement=cls.etablissement,
        )

    def _url(self, attendance):
        return f"/api/attendances/{attendance.id}/proof/"

    def _deposer(self, user, attendance, fichier=None):
        self.client.force_authenticate(user)
        return self.client.post(
            self._url(attendance),
            {"proof": fichier or _fichier()},
            format="multipart",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def tearDown(self):
        for row in Attendance.objects.exclude(proof=""):
            if row.proof:
                row.proof.delete(save=False)

    # --- Depot ---------------------------------------------------------

    def test_a_supervisor_files_a_proof(self):
        response = self._deposer(self.surveillant, self.absence)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["has_proof"])
        self.assertTrue(response.data["proof_name"].endswith(".pdf"))

        self.absence.refresh_from_db()
        self.assertTrue(self.absence.proof)

    def test_a_second_file_replaces_the_first(self):
        self._deposer(self.surveillant, self.absence, _fichier("premier.pdf"))
        self.absence.refresh_from_db()
        ancien = self.absence.proof.name

        response = self._deposer(self.surveillant, self.absence, _fichier("second.pdf"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.absence.refresh_from_db()
        self.assertNotEqual(self.absence.proof.name, ancien)
        self.assertIn("second", self.absence.proof.name)

    def test_a_present_student_has_nothing_to_justify(self):
        response = self._deposer(self.surveillant, self.presence)

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_an_empty_post_is_refused(self):
        self.client.force_authenticate(self.surveillant)
        response = self.client.post(
            self._url(self.absence),
            {},
            format="multipart",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    # --- Une fiche verrouillee accepte encore le mot d'excuse -----------

    def test_a_locked_sheet_still_accepts_a_proof(self):
        """Le mot arrive le lendemain, apres validation de la fiche.

        Le refuser obligerait a deverrouiller la journee entiere pour classer
        un papier.
        """
        AttendanceSheetValidation.objects.create(
            classroom=self.classe,
            date=self.jour,
            is_locked=True,
            validated_by=self.directeur,
        )

        response = self._deposer(self.surveillant, self.absence)

        self.assertEqual(response.status_code, status.HTTP_200_OK)

    # --- Droits --------------------------------------------------------

    def test_the_accountant_only_reads(self):
        response = self._deposer(self.comptable, self.absence)

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_removing_is_reserved_to_the_administration(self):
        self._deposer(self.surveillant, self.absence)

        self.client.force_authenticate(self.surveillant)
        refus = self.client.delete(
            self._url(self.absence), HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )
        self.assertEqual(refus.status_code, status.HTTP_403_FORBIDDEN)

        self.client.force_authenticate(self.directeur)
        retrait = self.client.delete(
            self._url(self.absence), HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )
        self.assertEqual(retrait.status_code, status.HTTP_200_OK)

        self.absence.refresh_from_db()
        self.assertFalse(self.absence.proof)

    # --- La fiche et les statistiques le voient -------------------------

    def test_the_class_sheet_shows_which_lines_are_justified(self):
        self._deposer(self.surveillant, self.absence)

        self.client.force_authenticate(self.surveillant)
        response = self.client.get(
            SHEET_URL,
            {"classroom": self.classe.id, "date": self.jour.isoformat()},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        lignes = {row["student"]: row for row in response.data["items"]}
        self.assertTrue(lignes[self.eleve.id]["has_proof"])
        self.assertTrue(lignes[self.eleve.id]["proof_url"])
        self.assertFalse(lignes[self.present.id]["has_proof"])

    def test_the_monthly_counter_stops_showing_zero(self):
        """Le compteur « Justificatifs » n'avait aucune source avant.

        Il compte les pieces reellement deposees: un FileField vide vaut
        tantot NULL, tantot la chaine vide selon l'ecriture.
        """
        self.client.force_authenticate(self.surveillant)
        avant = self.client.get(
            "/api/attendances/monthly_stats/",
            {"month": self.jour.strftime("%Y-%m")},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(avant.data["justifications"], 0)

        self._deposer(self.surveillant, self.absence)

        self.client.force_authenticate(self.surveillant)
        apres = self.client.get(
            "/api/attendances/monthly_stats/",
            {"month": self.jour.strftime("%Y-%m")},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(apres.data["justifications"], 1)

    # --- Le ré-enregistrement de la fiche ne perd pas la piece ----------

    def test_saving_the_sheet_again_keeps_the_proof(self):
        self._deposer(self.surveillant, self.absence)

        self.client.force_authenticate(self.surveillant)
        response = self.client.post(
            SHEET_URL,
            {
                "classroom": self.classe.id,
                "date": self.jour.isoformat(),
                "items": [
                    {
                        "student": self.eleve.id,
                        "is_absent": True,
                        "is_late": False,
                        "reason": "Maladie confirmee",
                    }
                ],
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.absence.refresh_from_db()
        self.assertTrue(self.absence.proof)
        self.assertEqual(self.absence.reason, "Maladie confirmee")
