"""La liste d'appel doit sortir pour qui en a l'usage, et pour lui seul.

Le document nomme des mineurs et porte leur date de naissance: il ne doit
jamais franchir la frontiere d'un etablissement, ni parvenir aux familles.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class ClassRosterPdfTests(APITestCase):
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

        cls.directeur = cls._make_user("directeur_liste", UserRole.DIRECTOR)
        cls.enseignant = cls._make_user("enseignant_liste", UserRole.TEACHER)

        cls._make_student("aissata", cls.sixieme, gender="F")
        cls._make_student("boubacar", cls.sixieme, gender="M")
        cls._make_student("cheick", cls.sixieme, gender="M")
        cls._make_student("archive", cls.sixieme, gender="F", is_archived=True)
        cls._make_student("djeneba", cls.cinquieme, gender="F")

    @classmethod
    def _make_user(cls, username, role, etablissement=None):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=role,
            etablissement=etablissement or cls.etablissement,
        )

    @classmethod
    def _make_student(cls, suffixe, classroom, *, gender="", is_archived=False):
        user = User.objects.create_user(
            username=f"eleve_{suffixe}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=classroom.etablissement,
        )
        return Student.objects.create(
            user=user,
            classroom=classroom,
            etablissement=classroom.etablissement,
            gender=gender,
            birth_date=date(2012, 5, 14),
            is_archived=is_archived,
        )

    def _get(self, url, *, attendu=status.HTTP_200_OK):
        response = self.client.get(
            url, HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )
        self.assertEqual(response.status_code, attendu)
        return response

    # --- Production du document ---------------------------------------

    def test_a_class_roster_is_a_real_pdf(self):
        self.client.force_authenticate(self.directeur)
        response = self._get(f"/api/reports/class-roster/{self.sixieme.id}/")

        self.assertEqual(response["Content-Type"], "application/pdf")
        self.assertIn("liste_6A.pdf", response["Content-Disposition"])
        # %PDF- en tete: un corps vide ou une page d'erreur passerait sinon
        # pour un document valide aupres du client.
        self.assertTrue(response.content.startswith(b"%PDF-"))
        self.assertGreater(len(response.content), 1000)

    def test_the_whole_school_fits_in_one_document(self):
        self.client.force_authenticate(self.directeur)
        response = self._get("/api/reports/class-roster/")

        self.assertIn("listes_toutes_classes.pdf", response["Content-Disposition"])
        self.assertTrue(response.content.startswith(b"%PDF-"))

    def test_the_summary_page_comes_after_the_classes(self):
        """Deux classes donnent trois pages: les deux listes, puis le total."""
        from apps.reports.views import _build_class_roster_pdf

        pdf = _build_class_roster_pdf(
            [
                ("6A", list(Student.objects.filter(classroom=self.sixieme, is_archived=False))),
                ("5B", list(Student.objects.filter(classroom=self.cinquieme))),
            ],
            school={"name": "LTOB"},
            logo_path=None,
            year_label="2025-2026",
            with_summary=True,
        )

        self.assertEqual(len(pdf.pages), 3)

    def test_a_single_class_gets_no_summary(self):
        """Un recapitulatif d'une seule ligne ne ferait que repeter l'en-tete."""
        from apps.reports.views import _build_class_roster_pdf

        pdf = _build_class_roster_pdf(
            [("6A", list(Student.objects.filter(classroom=self.sixieme, is_archived=False)))],
            school={"name": "LTOB"},
            logo_path=None,
            year_label="2025-2026",
            with_summary=True,
        )

        self.assertEqual(len(pdf.pages), 1)

    def test_document_labels_survive_the_pdf_encoding(self):
        """Le PDF est encode en latin-1: un caractere hors jeu sort en "?"."""
        from apps.reports.views import ROSTER_COLUMNS, _pdf_text

        for titre, _ in ROSTER_COLUMNS:
            self.assertEqual(_pdf_text(titre), titre)

    def test_an_empty_class_still_produces_its_page(self):
        """Une classe absente du document se lirait comme un oubli."""
        vide = ClassRoom.objects.create(
            name="4C", academic_year=self.year, etablissement=self.etablissement
        )

        self.client.force_authenticate(self.directeur)
        response = self._get(f"/api/reports/class-roster/{vide.id}/")

        self.assertTrue(response.content.startswith(b"%PDF-"))

    # --- Effectifs -----------------------------------------------------

    def test_archived_students_are_left_out_by_default(self):
        from apps.reports.views import _roster_gender_counts

        actifs = list(
            Student.objects.filter(classroom=self.sixieme, is_archived=False)
        )
        self.assertEqual(len(actifs), 3)
        self.assertEqual(_roster_gender_counts(actifs), (2, 1))

    def test_a_missing_gender_counts_in_the_total_only(self):
        """Ranger d'office un genre inconnu fausserait les deux colonnes."""
        from apps.reports.views import _roster_gender_counts

        sans_genre = self._make_student("inconnu", self.cinquieme, gender="")
        eleves = list(Student.objects.filter(classroom=self.cinquieme, is_archived=False))

        garcons, filles = _roster_gender_counts(eleves)
        self.assertEqual(len(eleves), 2)
        self.assertEqual((garcons, filles), (0, 1))
        self.assertIn(sans_genre, eleves)

    def test_the_document_follows_the_three_states_of_the_screen(self):
        """Imprimer les actifs quand l'ecran montre les archives surprendrait
        l'utilisateur une fois le papier sorti."""
        self.client.force_authenticate(self.directeur)

        for statut in ("active", "archived", "all"):
            with self.subTest(status=statut):
                response = self._get(
                    f"/api/reports/class-roster/{self.sixieme.id}/?status={statut}"
                )
                self.assertTrue(response.content.startswith(b"%PDF-"))

    def test_an_unknown_status_is_refused_instead_of_guessed(self):
        self.client.force_authenticate(self.directeur)
        response = self._get(
            f"/api/reports/class-roster/{self.sixieme.id}/?status=n_importe_quoi",
            attendu=status.HTTP_400_BAD_REQUEST,
        )

        self.assertIn("status invalide", str(response.data))

    # --- Cloisonnement -------------------------------------------------

    def test_teachers_may_print_the_roll_call(self):
        """L'export sensible est reserve a l'administration; pas cette liste.

        Elle sert d'abord en classe: la refuser aux enseignants la rendrait
        inutile la ou elle est justement necessaire.
        """
        self.client.force_authenticate(self.enseignant)
        response = self._get(f"/api/reports/class-roster/{self.sixieme.id}/")

        self.assertTrue(response.content.startswith(b"%PDF-"))

    def test_families_are_refused(self):
        for role, username in ((UserRole.PARENT, "parent_liste"), (UserRole.STUDENT, "eleve_liste")):
            with self.subTest(role=role):
                user = self._make_user(username, role)
                self.client.force_authenticate(user)
                self._get(
                    f"/api/reports/class-roster/{self.sixieme.id}/",
                    attendu=status.HTTP_403_FORBIDDEN,
                )

    def test_a_class_of_another_school_is_out_of_reach(self):
        autre_etab = Etablissement.objects.create(name="Autre lycee")
        autre_annee = AcademicYear.objects.create(
            name="2025-2026 bis",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
        )
        autre_classe = ClassRoom.objects.create(
            name="3A", academic_year=autre_annee, etablissement=autre_etab
        )

        self.client.force_authenticate(self.directeur)
        self._get(
            f"/api/reports/class-roster/{autre_classe.id}/",
            attendu=status.HTTP_403_FORBIDDEN,
        )

    def test_the_full_document_stops_at_the_school_boundary(self):
        """Sans classe precisee, seules les classes de l'etablissement sortent."""
        autre_etab = Etablissement.objects.create(name="Autre lycee")
        autre_annee = AcademicYear.objects.create(
            name="2025-2026 ter",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
        )
        intruse = ClassRoom.objects.create(
            name="ZZZ Intruse", academic_year=autre_annee, etablissement=autre_etab
        )

        self.client.force_authenticate(self.directeur)
        response = self._get("/api/reports/class-roster/")

        self.assertTrue(response.content.startswith(b"%PDF-"))
        self.assertNotIn(intruse.name.encode(), response.content)

    def test_it_requires_authentication(self):
        self.client.force_authenticate(None)
        response = self.client.get(f"/api/reports/class-roster/{self.sixieme.id}/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
