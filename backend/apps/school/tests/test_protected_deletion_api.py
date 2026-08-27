"""Supprimer un element encore utilise: une regle, pas une panne.

Les cles etrangeres du projet sont en `PROTECT` et c'est voulu -- une
classe qui porte des notes ne se supprime pas. Mais l'echec sortait en 500
avec une trace: le directeur lisait « Internal Server Error » sans savoir
ce qui bloquait. Ces tests verrouillent la traduction en 409 et le fait que
rien n'est supprime au passage.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Grade,
    Student,
    Subject,
)


class ProtectedDeletionApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")
        self.admin = User.objects.create_user(
            username="admin_protect",
            password="admin12345",
            role=UserRole.SUPER_ADMIN,
            etablissement=self.etablissement,
        )
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.classe = ClassRoom.objects.create(
            name="6A",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        self.matiere = Subject.objects.create(name="Maths", coefficient=Decimal("4"))
        eleve_user = User.objects.create_user(
            username="eleve_protect",
            password="eleve12345",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.eleve = Student.objects.create(
            user=eleve_user,
            matricule="M001",
            classroom=self.classe,
            etablissement=self.etablissement,
        )
        self.note = Grade.objects.create(
            student=self.eleve,
            subject=self.matiere,
            classroom=self.classe,
            academic_year=self.annee,
            term="T1",
            value=Decimal("12"),
        )
        self.client.force_authenticate(self.admin)

    def test_deleting_a_classroom_with_grades_answers_409_and_names_the_cause(self):
        reponse = self.client.delete(f"/api/classrooms/{self.classe.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_409_CONFLICT)
        detail = reponse.data["detail"]
        self.assertIn("Suppression impossible", detail)
        # Le message nomme ce qui bloque: sans cela, l'utilisateur ne sait
        # pas quoi retirer pour y arriver.
        self.assertIn("des notes", detail)
        self.assertTrue(ClassRoom.objects.filter(id=self.classe.id).exists())

    def test_deleting_a_subject_with_grades_answers_409(self):
        reponse = self.client.delete(f"/api/subjects/{self.matiere.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_409_CONFLICT)
        self.assertIn("des notes", reponse.data["detail"])
        self.assertTrue(Subject.objects.filter(id=self.matiere.id).exists())

    def test_deleting_an_academic_year_still_in_use_answers_409(self):
        reponse = self.client.delete(f"/api/academic-years/{self.annee.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_409_CONFLICT)
        self.assertTrue(AcademicYear.objects.filter(id=self.annee.id).exists())

    def test_a_free_classroom_is_still_deletable(self):
        """Le garde-fou ne doit pas bloquer ce qui n'est utilise par rien."""
        libre = ClassRoom.objects.create(
            name="6B",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )

        reponse = self.client.delete(f"/api/classrooms/{libre.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(ClassRoom.objects.filter(id=libre.id).exists())

    def test_the_cause_becomes_removable_once_the_grade_is_gone(self):
        """Le message dit quoi faire, et faire cela doit suffire."""
        self.note.delete()

        reponse = self.client.delete(f"/api/subjects/{self.matiere.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Subject.objects.filter(id=self.matiere.id).exists())
