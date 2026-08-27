"""Absences, incidents et depenses appartiennent enfin a une annee.

Ces modeles ne portaient qu'une date. Le dossier d'un eleve affichait donc
ses absences de toutes les annees confondues, et rien ne les separait une
fois l'eleve passe en classe superieure.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Attendance,
    ClassRoom,
    DisciplineIncident,
    Etablissement,
    Expense,
    Student,
)


class AnneeSurLesFaitsTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")
        self.directeur = User.objects.create_user(
            username="directeur_faits",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )

        self.annee_passee = AcademicYear.objects.create(
            name="2024-2025",
            start_date=date(2024, 9, 1),
            end_date=date(2025, 6, 30),
            etablissement=self.etablissement,
        )
        self.annee_courante = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )

        self.classe = ClassRoom.objects.create(
            name="5e A",
            academic_year=self.annee_courante,
            etablissement=self.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_faits",
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

        # Un fait par annee: c'est leur separation qu'on verifie.
        self.absence_passee = Attendance.objects.create(
            student=self.eleve, date=date(2024, 10, 1), is_absent=True,
            academic_year=self.annee_passee,
        )
        self.absence_courante = Attendance.objects.create(
            student=self.eleve, date=date(2025, 10, 1), is_absent=True,
            academic_year=self.annee_courante,
        )
        self.incident_passe = DisciplineIncident.objects.create(
            student=self.eleve, incident_date=date(2024, 11, 5),
            category="retard", description="Retard",
            academic_year=self.annee_passee,
        )

        self.client.force_authenticate(self.directeur)

    def _entetes(self, annee=None):
        entetes = {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}
        if annee is not None:
            entetes["HTTP_X_ACADEMIC_YEAR_ID"] = str(annee.id)
        return entetes

    def _resultats(self, reponse):
        data = reponse.data
        if isinstance(data, dict) and "results" in data:
            return data["results"]
        return data

    # ----- listes ---------------------------------------------------------

    def test_attendances_follow_the_selected_year(self):
        passees = self._resultats(
            self.client.get("/api/attendances/", **self._entetes(self.annee_passee))
        )
        self.assertEqual([row["id"] for row in passees], [self.absence_passee.id])

        courantes = self._resultats(
            self.client.get("/api/attendances/", **self._entetes(self.annee_courante))
        )
        self.assertEqual([row["id"] for row in courantes], [self.absence_courante.id])

    def test_without_a_year_header_both_years_are_returned(self):
        toutes = self._resultats(
            self.client.get("/api/attendances/", **self._entetes())
        )
        self.assertEqual(len(toutes), 2)

    def test_discipline_incidents_follow_the_selected_year(self):
        courants = self._resultats(
            self.client.get(
                "/api/discipline-incidents/", **self._entetes(self.annee_courante)
            )
        )
        self.assertEqual(courants, [])

    # ----- creation -------------------------------------------------------

    def test_a_new_attendance_takes_the_working_year(self):
        """Sans ce report, chaque nouvelle absence repartirait sans annee.

        Le client n'envoie pas le champ: c'est la vue qui le pose, d'apres
        l'annee de travail.
        """
        reponse = self.client.post(
            "/api/attendances/",
            {"student": self.eleve.id, "date": "2025-11-12", "is_absent": True},
            format="json",
            **self._entetes(self.annee_courante),
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        creee = Attendance.objects.get(id=reponse.data["id"])
        self.assertEqual(creee.academic_year_id, self.annee_courante.id)

    def test_a_new_incident_takes_the_working_year_without_losing_its_rules(self):
        """Le report d'annee ne doit pas court-circuiter la vue.

        Poser l'annee par un `save()` direct aurait saute le `perform_create`
        du module, celui qui fixe le declarant et bride l'enseignant.
        """
        reponse = self.client.post(
            "/api/discipline-incidents/",
            {
                "student": self.eleve.id,
                "incident_date": "2025-11-12",
                "category": "indiscipline",
                "description": "Bavardage",
            },
            format="json",
            **self._entetes(self.annee_courante),
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        cree = DisciplineIncident.objects.get(id=reponse.data["id"])
        self.assertEqual(cree.academic_year_id, self.annee_courante.id)
        # Le declarant reste pose par la vue du module.
        self.assertEqual(cree.reported_by_id, self.directeur.id)

    def test_an_expense_takes_the_working_year(self):
        reponse = self.client.post(
            "/api/expenses/",
            {"label": "Craie", "amount": "5000", "date": "2025-11-12", "category": "fourniture"},
            format="json",
            **self._entetes(self.annee_courante),
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        creee = Expense.objects.get(id=reponse.data["id"])
        self.assertEqual(creee.academic_year_id, self.annee_courante.id)

    # ----- dossier eleve --------------------------------------------------

    def test_the_student_file_follows_the_selected_year(self):
        """C'est le defaut le plus visible que ce lot corrige."""
        reponse = self.client.get(
            f"/api/students/{self.eleve.id}/dossier/",
            **self._entetes(self.annee_passee),
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)

        sections = {row["key"]: row for row in reponse.data["sections"]}
        absences = sections["attendance"]["items"]
        self.assertEqual([row["id"] for row in absences], [self.absence_passee.id])

        incidents = sections["discipline"]["items"]
        self.assertEqual([row["id"] for row in incidents], [self.incident_passe.id])

    def test_the_student_file_without_a_year_keeps_every_year(self):
        reponse = self.client.get(
            f"/api/students/{self.eleve.id}/dossier/", **self._entetes()
        )

        sections = {row["key"]: row for row in reponse.data["sections"]}
        self.assertEqual(len(sections["attendance"]["items"]), 2)
