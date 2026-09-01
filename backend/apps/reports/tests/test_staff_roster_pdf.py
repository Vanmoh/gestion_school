"""La liste du personnel enseignant, imprimable et cloisonnee."""

from datetime import date

from django.db import connection
from django.test.utils import CaptureQueriesContext
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
)


class StaffRosterPdfTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.sixieme = ClassRoom.objects.create(
            name="6A", academic_year=cls.year, etablissement=cls.etablissement
        )
        cls.cinquieme = ClassRoom.objects.create(
            name="5B", academic_year=cls.year, etablissement=cls.etablissement
        )

        cls.directeur = cls._make_user("directeur_staff", UserRole.DIRECTOR)
        cls.enseignant_lecteur = cls._make_user("ens_lecteur", UserRole.TEACHER)

        cls.amadou = cls._make_teacher("amadou", "Amadou", "DIALLO", "ENS-001")
        cls.fatou = cls._make_teacher("fatou", "Fatou", "KEITA", "ENS-002")

        maths_6a = Subject.objects.create(
            name="Mathematiques", code="M6A", classroom=cls.sixieme
        )
        maths_5b = Subject.objects.create(
            name="Mathematiques", code="M5B", classroom=cls.cinquieme
        )
        physique = Subject.objects.create(
            name="Physique", code="PH6A", classroom=cls.sixieme
        )

        # Meme matiere sur deux classes: la colonne ne doit pas la repeter.
        TeacherAssignment.objects.create(
            teacher=cls.amadou, subject=maths_6a, classroom=cls.sixieme
        )
        TeacherAssignment.objects.create(
            teacher=cls.amadou, subject=maths_5b, classroom=cls.cinquieme
        )
        TeacherAssignment.objects.create(
            teacher=cls.amadou, subject=physique, classroom=cls.sixieme
        )

    @classmethod
    def _make_user(cls, username, role, etablissement=None):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=role,
            etablissement=etablissement or cls.etablissement,
        )

    @classmethod
    def _make_teacher(cls, suffixe, prenom, nom, code, etablissement=None):
        user = User.objects.create_user(
            username=f"ens_{suffixe}",
            password="Pass1234!",
            role=UserRole.TEACHER,
            first_name=prenom,
            last_name=nom,
            etablissement=etablissement or cls.etablissement,
        )
        return Teacher.objects.create(
            user=user,
            employee_code=code,
            hire_date=date(2024, 9, 1),
            etablissement=etablissement or cls.etablissement,
        )

    def _get(self, *, attendu=status.HTTP_200_OK):
        response = self.client.get(
            "/api/reports/staff-roster/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(response.status_code, attendu)
        return response

    def test_the_staff_list_is_a_real_pdf(self):
        self.client.force_authenticate(self.directeur)
        response = self._get()

        self.assertEqual(response["Content-Type"], "application/pdf")
        self.assertIn("liste_enseignants.pdf", response["Content-Disposition"])
        self.assertTrue(response.content.startswith(b"%PDF-"))
        self.assertGreater(len(response.content), 1000)

    def test_a_subject_taught_in_several_classes_appears_once(self):
        from apps.reports.views import _teacher_subjects_label

        teacher = Teacher.objects.prefetch_related("assignments__subject").get(
            id=self.amadou.id
        )

        # Trois affectations, deux matieres: repeter "Mathematiques" remplirait
        # la colonne sans rien apprendre.
        self.assertEqual(
            _teacher_subjects_label(teacher), "Mathematiques, Physique"
        )

    def test_the_subject_column_costs_a_fixed_number_of_queries(self):
        """Garde-fou N+1: sans prefetch, chaque enseignant coutait 2 requetes."""
        self.client.force_authenticate(self.directeur)

        # Un appel a blanc d'abord: la toute premiere requete d'un compte cree
        # sa ligne de presence, ce qui coute quelques requetes une fois pour
        # toutes. Sans cet echauffement, la mesure « maigre » porterait cette
        # creation et la mesure « chargee » non -- un ecart qui ne dit rien du
        # N+1 qu'on surveille ici.
        self._get()

        with CaptureQueriesContext(connection) as maigre:
            self._get()

        for index in range(8):
            enseignant = self._make_teacher(
                f"extra{index}", f"Prenom{index}", f"NOM{index}", f"ENS-1{index:02d}"
            )
            matiere = Subject.objects.create(
                name=f"Matiere {index}", code=f"MX{index}", classroom=self.sixieme
            )
            TeacherAssignment.objects.create(
                teacher=enseignant, subject=matiere, classroom=self.sixieme
            )

        with CaptureQueriesContext(connection) as charge:
            self._get()

        self.assertEqual(len(charge), len(maigre))

    def test_an_empty_school_still_produces_a_document(self):
        Teacher.objects.all().delete()

        self.client.force_authenticate(self.directeur)
        response = self._get()

        self.assertTrue(response.content.startswith(b"%PDF-"))

    def test_teachers_may_print_the_staff_list(self):
        self.client.force_authenticate(self.enseignant_lecteur)
        response = self._get()

        self.assertTrue(response.content.startswith(b"%PDF-"))

    def test_families_are_refused(self):
        for role, username in (
            (UserRole.PARENT, "parent_staff"),
            (UserRole.STUDENT, "eleve_staff"),
        ):
            with self.subTest(role=role):
                user = self._make_user(username, role)
                self.client.force_authenticate(user)
                self._get(attendu=status.HTTP_403_FORBIDDEN)

    def test_the_list_stops_at_the_school_boundary(self):
        autre_etab = Etablissement.objects.create(name="Autre lycee")
        self._make_teacher(
            "intrus", "Ibrahim", "ZZZINTRUS", "ENS-999", etablissement=autre_etab
        )

        self.client.force_authenticate(self.directeur)
        response = self._get()

        self.assertNotIn(b"ZZZINTRUS", response.content)

    def test_a_user_without_a_school_is_refused(self):
        """Regression: le document sortait tout le personnel de toutes les ecoles.

        Le compte `directeur` du jeu de demonstration n'a pas d'etablissement.
        Le filtre ne s'appliquait donc pas, et la liste melangeait 44
        enseignants de quatre etablissements. Refuser vaut mieux que fuiter.
        """
        orphelin = User.objects.create_user(
            username="directeur_orphelin",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
        )
        self.assertIsNone(orphelin.etablissement_id)

        self.client.force_authenticate(orphelin)
        response = self.client.get("/api/reports/staff-roster/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_long_subject_list_is_cut_instead_of_overflowing(self):
        """Regression: les matieres debordaient sur la colonne d'emargement.

        `FPDF.cell` dessine la bordure a la largeur demandee mais n'ecrete pas
        son contenu. Un professeur cumulant trois intitules longs voyait son
        texte se superposer a la case a signer -- visible seulement une fois
        le document imprime.
        """
        from fpdf import FPDF

        from apps.reports.views import STAFF_COLUMNS, _ajuster_a_la_cellule

        pdf = FPDF(format="A4")
        pdf.add_page()
        pdf.set_font("Helvetica", "", 9)

        largeur_matieres = dict(STAFF_COLUMNS)["Matières"]
        long_intitule = (
            "Education Physique et Sportive (EPS), "
            "Histoire-Geographie (Histoire-Geo), Langue vivante 2"
        )
        self.assertGreater(pdf.get_string_width(long_intitule), largeur_matieres)

        ajuste = _ajuster_a_la_cellule(pdf, long_intitule, largeur_matieres)

        self.assertLessEqual(pdf.get_string_width(ajuste), largeur_matieres)
        self.assertTrue(ajuste.endswith("..."))

    def test_a_short_value_is_left_untouched(self):
        from fpdf import FPDF

        from apps.reports.views import _ajuster_a_la_cellule

        pdf = FPDF(format="A4")
        pdf.add_page()
        pdf.set_font("Helvetica", "", 9)

        self.assertEqual(_ajuster_a_la_cellule(pdf, "Anglais", 62.0), "Anglais")
        self.assertEqual(_ajuster_a_la_cellule(pdf, "", 62.0), "")

    def test_the_columns_fit_the_page(self):
        """Une somme superieure a la largeur utile pousserait la derniere
        colonne hors de la feuille."""
        from apps.reports.views import ROSTER_COLUMNS, STAFF_COLUMNS

        for colonnes in (STAFF_COLUMNS, ROSTER_COLUMNS):
            self.assertLessEqual(sum(largeur for _, largeur in colonnes), 190.0)

    def test_it_requires_authentication(self):
        self.client.force_authenticate(None)
        response = self.client.get("/api/reports/staff-roster/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
