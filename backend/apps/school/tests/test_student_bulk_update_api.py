"""Une modification groupee ne doit jamais deborder du perimetre.

Archiver une promotion ou deplacer une classe entiere se fait en un appel.
Le risque n'est plus la lenteur mais la portee: un identifiant devine ne doit
pas permettre de toucher l'eleve d'un autre etablissement, et une demande
partiellement invalide ne doit rien appliquer du tout.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class StudentBulkUpdateTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )

        cls.ltob = Etablissement.objects.create(name="LTOB")
        cls.autre = Etablissement.objects.create(name="Autre lycee")

        cls.classe_a = ClassRoom.objects.create(
            name="10eme A", academic_year=cls.year, etablissement=cls.ltob
        )
        cls.classe_b = ClassRoom.objects.create(
            name="10eme B", academic_year=cls.year, etablissement=cls.ltob
        )
        cls.classe_autre = ClassRoom.objects.create(
            name="6eme", academic_year=cls.year, etablissement=cls.autre
        )

        cls.directeur = User.objects.create_user(
            username="directeur_bulk",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.ltob,
        )

        def eleve(suffixe, classe, etablissement):
            user = User.objects.create_user(
                username=f"eleve_bulk_{suffixe}",
                password="Pass1234!",
                role=UserRole.STUDENT,
                etablissement=etablissement,
            )
            return Student.objects.create(
                user=user, classroom=classe, etablissement=etablissement
            )

        cls.eleve1 = eleve("1", cls.classe_a, cls.ltob)
        cls.eleve2 = eleve("2", cls.classe_a, cls.ltob)
        cls.intrus = eleve("intrus", cls.classe_autre, cls.autre)

    def setUp(self):
        self.client.force_authenticate(self.directeur)

    def _bulk(self, payload):
        return self.client.post(
            "/api/students/bulk-update/",
            payload,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.ltob.id),
        )

    def test_it_archives_several_students_at_once(self):
        response = self._bulk(
            {"ids": [self.eleve1.id, self.eleve2.id], "is_archived": True}
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["updated"], 2)
        self.eleve1.refresh_from_db()
        self.eleve2.refresh_from_db()
        self.assertTrue(self.eleve1.is_archived)
        self.assertTrue(self.eleve2.is_archived)

    def test_it_moves_several_students_to_another_class(self):
        response = self._bulk(
            {"ids": [self.eleve1.id, self.eleve2.id], "classroom": self.classe_b.id}
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.eleve1.refresh_from_db()
        self.assertEqual(self.eleve1.classroom_id, self.classe_b.id)

    def test_a_student_of_another_school_blocks_the_whole_request(self):
        """Refus global: un rapport partiel laisserait croire au succes."""
        response = self._bulk(
            {"ids": [self.eleve1.id, self.intrus.id], "is_archived": True}
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.eleve1.refresh_from_db()
        self.assertFalse(
            self.eleve1.is_archived,
            "l'eleve legitime a ete modifie malgre le refus",
        )

    def test_a_class_of_another_school_is_refused(self):
        """Sinon un identifiant devine deplace un eleve hors de son ecole."""
        response = self._bulk(
            {"ids": [self.eleve1.id], "classroom": self.classe_autre.id}
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.eleve1.refresh_from_db()
        self.assertEqual(self.eleve1.classroom_id, self.classe_a.id)

    def test_an_empty_selection_is_refused(self):
        self.assertEqual(
            self._bulk({"ids": [], "is_archived": True}).status_code,
            status.HTTP_400_BAD_REQUEST,
        )

    def test_a_request_without_any_change_is_refused(self):
        response = self._bulk({"ids": [self.eleve1.id]})

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_read_only_profile_cannot_use_it(self):
        eleve_user = User.objects.create_user(
            username="eleve_lecteur",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.ltob,
        )
        self.client.force_authenticate(eleve_user)

        response = self._bulk({"ids": [self.eleve1.id], "is_archived": True})

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
