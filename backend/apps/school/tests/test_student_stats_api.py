"""Les effectifs affiches doivent decrire l'ecole, pas la page consultee.

Le client comptait sur la page recue: a 15 lignes par page, un etablissement
de 800 eleves affichait "15 actifs". Ces totaux viennent donc du serveur, et
ne doivent varier ni avec la pagination ni avec les filtres du tableau.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class StudentStatsTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        # L'annee appartient a son etablissement: les stats resolvent
        # desormais « l'annee courante » par ecole, et une annee sans
        # etablissement n'est celle de personne.
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classroom = ClassRoom.objects.create(
            name="10eme CT", academic_year=cls.year, etablissement=cls.etablissement
        )

        cls.admin = User.objects.create_user(
            username="admin_stats",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

        def eleve(suffixe, *, archive=False, inscrit=None, genre=None):
            user = User.objects.create_user(
                username=f"eleve_{suffixe}",
                password="Pass1234!",
                role=UserRole.STUDENT,
                etablissement=cls.etablissement,
            )
            champs = {}
            if inscrit is not None:
                champs["enrollment_date"] = inscrit
            return Student.objects.create(
                user=user,
                classroom=cls.classroom,
                etablissement=cls.etablissement,
                is_archived=archive,
                gender=genre,
                **champs,
            )

        # 3 actifs dont 2 inscrits cette annee, 1 archive.
        eleve("a", inscrit=date(2025, 9, 15), genre="M")
        eleve("b", inscrit=date(2025, 10, 1))
        eleve("c", inscrit=date(2024, 9, 1), genre="F")
        eleve("d", archive=True, inscrit=date(2025, 9, 20))

    def setUp(self):
        self.client.force_authenticate(self.admin)

    def _stats(self, **params):
        response = self.client.get(
            "/api/students/stats/",
            params,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data

    def test_it_counts_the_whole_school(self):
        data = self._stats()

        self.assertEqual(data["total"], 4)
        self.assertEqual(data["active"], 3)
        self.assertEqual(data["archived"], 1)

    def test_new_enrolments_follow_the_active_academic_year(self):
        """L'eleve inscrit en 2024 n'est pas un nouveau de 2025-2026."""
        self.assertEqual(self._stats()["new_this_year"], 2)
        self.assertEqual(self._stats()["academic_year"], "2025-2026")

    def test_missing_gender_counts_null_as_well_as_empty(self):
        """Le champ tolere les deux; n'en compter qu'un sous-estimerait."""
        self.assertEqual(self._stats()["gender_missing"], 1)

        Student.objects.filter(gender__isnull=True).update(gender="")
        self.assertEqual(self._stats()["gender_missing"], 1)

    def test_the_totals_ignore_pagination(self):
        page = self.client.get(
            "/api/students/",
            {"page_size": 1},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(len(page.data["results"]), 1)
        self.assertEqual(self._stats()["total"], 4)

    def test_the_totals_ignore_the_table_filters(self):
        """L'en-tete decrit l'etablissement, le tableau ce qu'on regarde."""
        self.assertEqual(self._stats(is_archived="true")["active"], 3)

    def test_another_school_is_never_counted(self):
        autre = Etablissement.objects.create(name="Autre lycee")
        autre_annee = AcademicYear.objects.create(
            name="2025-2026 bis",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
        )
        autre_classe = ClassRoom.objects.create(
            name="6eme", academic_year=autre_annee, etablissement=autre
        )
        intrus = User.objects.create_user(
            username="eleve_intrus", password="Pass1234!", role=UserRole.STUDENT
        )
        Student.objects.create(
            user=intrus, classroom=autre_classe, etablissement=autre
        )

        self.assertEqual(self._stats()["total"], 4)

    def test_it_requires_authentication(self):
        self.client.force_authenticate(None)
        response = self.client.get("/api/students/stats/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
