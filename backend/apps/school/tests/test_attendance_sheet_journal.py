"""Le journal rend visibles les fiches d'appel deja enregistrees.

Une fois la fiche enregistree, rien ne permettait de la revoir: il fallait
resaisir sa classe et sa date de memoire. L'historique existant listait les
enregistrements un par un, tous eleves et toutes dates melanges.
"""

from datetime import date, timedelta

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
    Subject,
    Teacher,
    TeacherAssignment,
)

URL = "/api/attendances/sheet-journal/"


class AttendanceSheetJournalTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.sixieme = ClassRoom.objects.create(
            name="6A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.cinquieme = ClassRoom.objects.create(
            name="5B", academic_year=cls.annee, etablissement=cls.etablissement
        )

        cls.hier = date.today() - timedelta(days=1)
        cls.aujourdhui = date.today()

        # 6A hier: 3 eleves, 1 absent, 1 retard. Fiche validee.
        eleves_6a = [cls._eleve(f"a{i}", cls.sixieme) for i in range(3)]
        Attendance.objects.create(student=eleves_6a[0], date=cls.hier)
        Attendance.objects.create(student=eleves_6a[1], date=cls.hier, is_absent=True)
        Attendance.objects.create(student=eleves_6a[2], date=cls.hier, is_late=True)

        cls.validateur = User.objects.create_user(
            username="directeur_journal",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
            first_name="Le",
            last_name="Directeur",
        )
        AttendanceSheetValidation.objects.create(
            classroom=cls.sixieme,
            date=cls.hier,
            is_locked=True,
            validated_by=cls.validateur,
        )

        # 6A aujourd'hui: 2 eleves, aucun absent. Brouillon, non validee.
        Attendance.objects.create(student=eleves_6a[0], date=cls.aujourdhui)
        Attendance.objects.create(student=eleves_6a[1], date=cls.aujourdhui)

        # 5B hier: 1 eleve absent.
        cls.eleve_5b = cls._eleve("b0", cls.cinquieme)
        Attendance.objects.create(
            student=cls.eleve_5b, date=cls.hier, is_absent=True
        )

    @classmethod
    def _eleve(cls, suffixe, classe):
        user = User.objects.create_user(
            username=f"eleve_{suffixe}_{classe.name}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=classe.etablissement,
        )
        return Student.objects.create(
            user=user, classroom=classe, etablissement=classe.etablissement
        )

    def _journal(self, user, **params):
        self.client.force_authenticate(user)
        response = self.client.get(
            URL, params, HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data

    @staticmethod
    def _ligne(journal, classe_nom, jour):
        for ligne in journal:
            if ligne["classroom_name"] == classe_nom and str(ligne["date"]) == str(jour):
                return ligne
        raise AssertionError(f"fiche absente: {classe_nom} {jour}")

    # --- Agregation ----------------------------------------------------

    def test_one_line_per_class_and_date(self):
        journal = self._journal(self.validateur)

        # 6A hier, 6A aujourd'hui, 5B hier: trois fiches, pas six presences.
        self.assertEqual(len(journal), 3)

    def test_each_line_counts_its_class(self):
        journal = self._journal(self.validateur)
        ligne = self._ligne(journal, "6A", self.hier)

        self.assertEqual(ligne["effectif"], 3)
        self.assertEqual(ligne["absents"], 1)
        self.assertEqual(ligne["retards"], 1)

    def test_a_late_student_is_not_counted_absent(self):
        """Un eleve en retard est present: les deux colonnes sont distinctes."""
        journal = self._journal(self.validateur)
        ligne = self._ligne(journal, "6A", self.hier)

        self.assertEqual(ligne["absents"] + ligne["retards"], 2)
        self.assertEqual(ligne["effectif"], 3)

    def test_the_most_recent_sheets_come_first(self):
        journal = self._journal(self.validateur)

        dates = [str(ligne["date"]) for ligne in journal]
        self.assertEqual(dates, sorted(dates, reverse=True))

    # --- Etat ----------------------------------------------------------

    def test_a_validated_sheet_carries_who_locked_it(self):
        ligne = self._ligne(self._journal(self.validateur), "6A", self.hier)

        self.assertTrue(ligne["is_locked"])
        self.assertEqual(ligne["validated_by_name"], "Le Directeur")

    def test_a_draft_sheet_appears_too(self):
        """Lister les seules validations rendrait les brouillons invisibles."""
        ligne = self._ligne(self._journal(self.validateur), "6A", self.aujourdhui)

        self.assertFalse(ligne["is_locked"])
        self.assertEqual(ligne["validated_by_name"], "")
        self.assertIsNone(ligne["validated_at"])

    # --- Filtres -------------------------------------------------------

    def test_it_filters_on_one_class(self):
        journal = self._journal(self.validateur, classroom=self.cinquieme.id)

        self.assertEqual(len(journal), 1)
        self.assertEqual(journal[0]["classroom_name"], "5B")

    def test_it_filters_on_a_period(self):
        journal = self._journal(
            self.validateur,
            **{"from": str(self.aujourdhui), "to": str(self.aujourdhui)},
        )

        self.assertEqual(len(journal), 1)
        self.assertEqual(str(journal[0]["date"]), str(self.aujourdhui))

    # --- Cloisonnement -------------------------------------------------

    def test_a_teacher_only_sees_the_classes_assigned_to_him(self):
        enseignant_user = User.objects.create_user(
            username="prof_journal",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        enseignant = Teacher.objects.create(
            user=enseignant_user,
            employee_code="ENS-J1",
            hire_date=date(2024, 9, 1),
            etablissement=self.etablissement,
        )
        matiere = Subject.objects.create(
            name="Maths", code="M1", classroom=self.sixieme
        )
        TeacherAssignment.objects.create(
            teacher=enseignant, subject=matiere, classroom=self.sixieme
        )

        journal = self._journal(enseignant_user)

        noms = {ligne["classroom_name"] for ligne in journal}
        self.assertEqual(noms, {"6A"})

    def test_another_school_never_appears(self):
        autre_etab = Etablissement.objects.create(name="Autre lycee")
        autre_annee = AcademicYear.objects.create(
            name="2025-2026 bis",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
        )
        autre_classe = ClassRoom.objects.create(
            name="ZZZ Intruse", academic_year=autre_annee, etablissement=autre_etab
        )
        intrus_user = User.objects.create_user(
            username="eleve_intrus_journal",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=autre_etab,
        )
        intrus = Student.objects.create(
            user=intrus_user, classroom=autre_classe, etablissement=autre_etab
        )
        Attendance.objects.create(student=intrus, date=self.hier, is_absent=True)

        journal = self._journal(self.validateur)

        noms = {ligne["classroom_name"] for ligne in journal}
        self.assertNotIn("ZZZ Intruse", noms)

    def test_families_are_refused(self):
        for role in (UserRole.PARENT, UserRole.STUDENT):
            with self.subTest(role=role):
                famille = User.objects.create_user(
                    username=f"famille_journal_{role}",
                    password="Pass1234!",
                    role=role,
                    etablissement=self.etablissement,
                )
                self.client.force_authenticate(famille)
                response = self.client.get(URL)

                self.assertIn(
                    response.status_code,
                    (status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN),
                )

    def test_it_requires_authentication(self):
        self.client.force_authenticate(None)
        response = self.client.get(URL)

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
