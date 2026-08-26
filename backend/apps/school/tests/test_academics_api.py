"""Le socle academique: annees, classes, matieres.

Tout le reste en depend -- les notes, l'emploi du temps, la passation -- et
il n'avait aucun test d'API. Ces tests verrouillent les trois choses qui
cassent en silence: le perimetre etablissement, les droits, et les filtres
de liste qui etaient acceptes puis ignores.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Subject


class AcademicsApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")

        self.directeur = User.objects.create_user(
            username="directeur_acad",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.enseignant = User.objects.create_user(
            username="enseignant_acad",
            password="enseignant12345",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.comptable = User.objects.create_user(
            username="comptable_acad",
            password="comptable12345",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )

        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.sixieme = ClassRoom.objects.create(
            name="6A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.cinquieme = ClassRoom.objects.create(
            name="5B", academic_year=self.annee, etablissement=self.etablissement
        )
        self.classe_voisine = ClassRoom.objects.create(
            name="6A", academic_year=self.annee, etablissement=self.autre
        )

        self.maths = Subject.objects.create(
            name="Mathematiques",
            code="MATH",
            coefficient=Decimal("4"),
            classroom=self.sixieme,
        )
        self.sport = Subject.objects.create(
            name="Education physique",
            code="EPS",
            coefficient=Decimal("1"),
            classroom=self.cinquieme,
        )

    def _resultats(self, reponse):
        data = reponse.data
        if isinstance(data, dict) and "results" in data:
            return data["results"]
        return data

    # ----- perimetre ---------------------------------------------------

    def test_classrooms_are_scoped_to_the_users_school(self):
        self.client.force_authenticate(self.directeur)
        noms = {row["name"] for row in self._resultats(self.client.get("/api/classrooms/"))}

        # Les deux ecoles ont une « 6A »: sans cloisonnement, le directeur
        # verrait la classe de la voisine sous le meme nom que la sienne.
        self.assertEqual(noms, {"6A", "5B"})
        ids = {row["id"] for row in self._resultats(self.client.get("/api/classrooms/"))}
        self.assertNotIn(self.classe_voisine.id, ids)

    # ----- recherche et tri --------------------------------------------

    def test_searching_classrooms_filters_instead_of_returning_everything(self):
        """`?search=` etait accepte puis ignore.

        L'ecran croyait filtrer et recevait la liste entiere, qu'il refiltrait
        lui-meme -- le meme piege que TeacherViewSet documentait deja.
        """
        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(self.client.get("/api/classrooms/", {"search": "5B"}))

        self.assertEqual([row["name"] for row in trouves], ["5B"])

    def test_searching_subjects_matches_name_and_code(self):
        self.client.force_authenticate(self.directeur)

        par_nom = self._resultats(self.client.get("/api/subjects/", {"search": "physique"}))
        self.assertEqual([row["name"] for row in par_nom], ["Education physique"])

        # Le code est ce que le personnel tape: « MATH » plutot que le
        # libelle complet.
        par_code = self._resultats(self.client.get("/api/subjects/", {"search": "MATH"}))
        self.assertEqual([row["name"] for row in par_code], ["Mathematiques"])

    def test_ordering_subjects_by_coefficient(self):
        self.client.force_authenticate(self.directeur)
        tries = self._resultats(
            self.client.get("/api/subjects/", {"ordering": "-coefficient"})
        )

        self.assertEqual(
            [row["name"] for row in tries],
            ["Mathematiques", "Education physique"],
        )

    def test_filtering_classrooms_by_academic_year(self):
        annee_suivante = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 6, 30),
        )
        ClassRoom.objects.create(
            name="4C", academic_year=annee_suivante, etablissement=self.etablissement
        )

        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/classrooms/", {"academic_year": annee_suivante.id})
        )

        self.assertEqual([row["name"] for row in trouves], ["4C"])

    def test_searching_academic_years(self):
        AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 6, 30),
        )

        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/academic-years/", {"search": "2026-2027"})
        )

        self.assertEqual([row["name"] for row in trouves], ["2026-2027"])

    # ----- droits ------------------------------------------------------

    def test_a_teacher_reads_the_referential_but_does_not_change_it(self):
        """La matrice donne « L » a l'enseignant sur l'academique.

        Il consulte les classes et les matieres pour saisir ses notes; le
        referentiel lui-meme releve de la direction.
        """
        self.client.force_authenticate(self.enseignant)

        self.assertEqual(
            self.client.get("/api/classrooms/").status_code, status.HTTP_200_OK
        )
        creation = self.client.post(
            "/api/classrooms/",
            {"name": "3D", "academic_year": self.annee.id},
            format="json",
        )
        self.assertEqual(creation.status_code, status.HTTP_403_FORBIDDEN)

    def test_an_accountant_has_no_access_to_the_referential(self):
        self.client.force_authenticate(self.comptable)
        self.assertEqual(
            self.client.get("/api/subjects/").status_code, status.HTTP_403_FORBIDDEN
        )

    def test_a_director_creates_a_classroom_in_their_own_school(self):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/classrooms/",
            {"name": "3D", "academic_year": self.annee.id},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        creee = ClassRoom.objects.get(id=reponse.data["id"])
        # L'etablissement n'est pas dans la charge utile: le laisser au
        # client aurait permis de creer une classe chez la voisine.
        self.assertEqual(creee.etablissement_id, self.etablissement.id)
