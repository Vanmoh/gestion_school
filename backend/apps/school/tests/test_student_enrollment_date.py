"""La date d'inscription doit refleter l'inscription, pas la saisie.

Une ecole saisit rarement le jour meme: les dossiers de septembre sont
enregistres en octobre, et une reprise d'existant l'est en une seule fois.
Tant que le champ etait en `auto_now_add`, toutes ces fiches portaient la date
de saisie et le compteur « nouveaux cette annee » comptait des creations de
lignes. Ce module verrouille les deux sens: on peut antidater, jamais postdater.
"""

from datetime import date, timedelta

from django.core.exceptions import ValidationError
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class StudentEnrollmentDateTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        # L'annee appartient a son ecole: la resolution de « l'annee
        # courante » se fait par etablissement, et une annee sans
        # etablissement n'est celle de personne.
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classroom = ClassRoom.objects.create(
            name="10eme A", academic_year=cls.year, etablissement=cls.etablissement
        )
        cls.directeur = User.objects.create_user(
            username="directeur_inscription",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        self.client.force_authenticate(self.directeur)

    def _eleve(self, suffixe, **champs):
        user = User.objects.create_user(
            username=f"eleve_inscription_{suffixe}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=user,
            classroom=self.classroom,
            etablissement=self.etablissement,
            gender="M",
            **champs,
        )

    def test_the_date_defaults_to_today(self):
        """Le comportement courant ne change pas: seule l'exception s'ouvre."""
        self.assertEqual(self._eleve("defaut").enrollment_date, date.today())

    def test_an_earlier_enrollment_can_be_recorded(self):
        rentree = date(2025, 9, 3)

        eleve = self._eleve("antidate", enrollment_date=rentree)

        eleve.refresh_from_db()
        self.assertEqual(eleve.enrollment_date, rentree)

    def test_a_future_enrollment_is_refused_by_the_model(self):
        demain = date.today() + timedelta(days=1)

        with self.assertRaises(ValidationError) as erreur:
            self._eleve("futur", enrollment_date=demain)

        self.assertIn("enrollment_date", erreur.exception.error_dict)

    def test_the_api_can_correct_an_existing_date(self):
        eleve = self._eleve("correction")
        rentree = date(2025, 9, 3)

        response = self.client.patch(
            f"/api/students/{eleve.id}/",
            {"enrollment_date": rentree.isoformat()},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        eleve.refresh_from_db()
        self.assertEqual(eleve.enrollment_date, rentree)

    def test_the_api_refuses_a_future_date_with_400(self):
        """Le modele leve la ValidationError de Django, que DRF ne traduit pas:
        sans reprise dans le serializer, une faute de frappe sortait en 500."""
        eleve = self._eleve("futur_api")
        demain = date.today() + timedelta(days=1)

        response = self.client.patch(
            f"/api/students/{eleve.id}/",
            {"enrollment_date": demain.isoformat()},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("enrollment_date", response.data)

    def test_the_api_refuses_a_future_birth_date_with_400(self):
        """Meme defaut, meme serializer: le modele repondait 500."""
        eleve = self._eleve("naissance")

        response = self.client.patch(
            f"/api/students/{eleve.id}/",
            {"birth_date": (date.today() + timedelta(days=1)).isoformat()},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("birth_date", response.data)

    def test_a_backdated_student_is_not_counted_as_new(self):
        """Le compteur des statistiques doit suivre l'inscription reelle."""
        self._eleve("ancien", enrollment_date=date(2024, 9, 2))
        self._eleve("nouveau", enrollment_date=date(2025, 9, 2))

        response = self.client.get(
            "/api/students/stats/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["total"], 2)
        self.assertEqual(
            response.data["new_this_year"],
            1,
            "l'eleve inscrit l'annee precedente est compte comme nouveau",
        )
