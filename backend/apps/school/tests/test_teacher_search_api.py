"""Chercher un enseignant, comme on cherche un eleve.

`?search=` etait accepte et ignore faute de `search_fields`: l'ecran croyait
filtrer et recevait tout l'effectif. Ces tests fixent ce qu'on doit pouvoir
taper, et ce que la recherche ne doit jamais faire -- franchir la frontiere
d'un etablissement, ou dupliquer une ligne.
"""

from datetime import date

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


class TeacherSearchTests(APITestCase):
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
        cls.quatrieme = ClassRoom.objects.create(
            name="4C", academic_year=cls.year, etablissement=cls.etablissement
        )

        cls.directeur = User.objects.create_user(
            username="directeur_ens",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

        cls.amadou = cls._make_teacher(
            "amadou", "Amadou", "DIALLO", "ENS-001", phone="76123456"
        )
        cls.fatou = cls._make_teacher(
            "fatou", "Fatou", "KEITA", "ENS-002", email="fatou.keita@ltob.ml"
        )

        maths = Subject.objects.create(
            name="Mathematiques", code="MATH6A", classroom=cls.sixieme
        )
        maths_5b = Subject.objects.create(
            name="Mathematiques", code="MATH5B", classroom=cls.cinquieme
        )
        maths_4c = Subject.objects.create(
            name="Mathematiques", code="MATH4C", classroom=cls.quatrieme
        )
        francais = Subject.objects.create(
            name="Francais", code="FR6A", classroom=cls.sixieme
        )

        # Amadou enseigne la meme matiere dans trois classes: c'est ce cas qui
        # duplique une ligne quand la jointure inverse n'est pas dedoublonnee.
        for matiere, classe in (
            (maths, cls.sixieme),
            (maths_5b, cls.cinquieme),
            (maths_4c, cls.quatrieme),
        ):
            TeacherAssignment.objects.create(
                teacher=cls.amadou, subject=matiere, classroom=classe
            )
        TeacherAssignment.objects.create(
            teacher=cls.fatou, subject=francais, classroom=cls.sixieme
        )

    @classmethod
    def _make_teacher(
        cls, suffixe, prenom, nom, code, *, phone="", email="", etablissement=None
    ):
        user = User.objects.create_user(
            username=f"ens_{suffixe}",
            password="Pass1234!",
            role=UserRole.TEACHER,
            first_name=prenom,
            last_name=nom,
            email=email,
            phone=phone,
            etablissement=etablissement or cls.etablissement,
        )
        return Teacher.objects.create(
            user=user,
            employee_code=code,
            hire_date=date(2024, 9, 1),
            etablissement=etablissement or cls.etablissement,
        )

    def _search(self, terme):
        response = self.client.get(
            "/api/teachers/",
            {"search": terme},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        payload = response.data
        rows = payload["results"] if isinstance(payload, dict) else payload
        return [row["id"] for row in rows]

    # --- Ce qu'on doit pouvoir taper -----------------------------------

    def test_the_search_accepts_what_one_has_at_hand(self):
        self.client.force_authenticate(self.directeur)

        for terme, attendu in [
            ("DIALLO", self.amadou.id),
            ("amadou", self.amadou.id),
            ("ENS-001", self.amadou.id),
            ("ens_amadou", self.amadou.id),
            ("76123456", self.amadou.id),
            ("fatou.keita@ltob.ml", self.fatou.id),
        ]:
            with self.subTest(terme=terme):
                self.assertEqual(self._search(terme), [attendu])

    def test_one_may_search_by_subject_or_classroom(self):
        """« Qui fait maths en 6A ? » est la question posee en salle des profs."""
        self.client.force_authenticate(self.directeur)

        self.assertEqual(self._search("Mathematiques"), [self.amadou.id])
        self.assertEqual(self._search("Francais"), [self.fatou.id])
        self.assertEqual(
            sorted(self._search("6A")), sorted([self.amadou.id, self.fatou.id])
        )

    # --- Ce que la recherche ne doit pas faire -------------------------

    def test_a_teacher_appears_once_per_result(self):
        """Regression: la jointure inverse rendait Amadou trois fois.

        Il enseigne la meme matiere dans trois classes; sans dedoublonnage,
        l'ecran afficherait trois lignes pour un seul enseignant, et un
        compteur d'effectif faux.
        """
        self.client.force_authenticate(self.directeur)

        resultats = self._search("Mathematiques")

        self.assertEqual(len(resultats), len(set(resultats)))
        self.assertEqual(resultats, [self.amadou.id])

    def test_the_search_stops_at_the_school_boundary(self):
        autre_etab = Etablissement.objects.create(name="Autre lycee")
        self._make_teacher(
            "intrus", "Ibrahim", "DIALLO", "ENS-999", etablissement=autre_etab
        )

        self.client.force_authenticate(self.directeur)
        resultats = self._search("DIALLO")

        # Meme nom de famille, autre etablissement: il ne doit pas remonter.
        self.assertEqual(resultats, [self.amadou.id])

    def test_an_empty_search_returns_the_whole_staff(self):
        self.client.force_authenticate(self.directeur)

        self.assertEqual(len(self._search("")), 2)

    def test_a_search_without_match_returns_nothing(self):
        self.client.force_authenticate(self.directeur)

        self.assertEqual(self._search("zzzzz"), [])

    def test_it_requires_authentication(self):
        self.client.force_authenticate(None)
        response = self.client.get("/api/teachers/", {"search": "DIALLO"})

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    # --- Ordre ---------------------------------------------------------

    def test_the_staff_is_listed_alphabetically(self):
        """Sans ordre stable, deux chargements ne donnent pas la meme liste."""
        self.client.force_authenticate(self.directeur)

        resultats = self._search("")

        # DIALLO avant KEITA.
        self.assertEqual(resultats, [self.amadou.id, self.fatou.id])
