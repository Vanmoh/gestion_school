"""Sessions, plannings, surveillance et resultats d'examen.

Le module n'avait aucun test dedie: les resultats n'apparaissaient que par
ricochet dans ceux des bulletins. Ces tests couvrent ce qui lui est propre
-- qui voit quoi, et les filtres de liste qui etaient acceptes puis ignores.
"""

from datetime import date, time
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    ExamResult,
    ExamSession,
    ParentProfile,
    Student,
    Subject,
)


class ExamsApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")

        self.directeur = User.objects.create_user(
            username="directeur_exam",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.surveillant = User.objects.create_user(
            username="surveillant_exam",
            password="surveillant12345",
            role=UserRole.SUPERVISOR,
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
        self.maths = Subject.objects.create(
            name="Mathematiques", code="MATH", coefficient=Decimal("4")
        )
        self.sport = Subject.objects.create(
            name="Education physique", code="EPS", coefficient=Decimal("1")
        )

        self.composition = ExamSession.objects.create(
            title="Composition du premier trimestre",
            term="T1",
            academic_year=self.annee,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 6),
        )
        self.rattrapage = ExamSession.objects.create(
            title="Rattrapage",
            term="T2",
            academic_year=self.annee,
            start_date=date(2026, 3, 2),
            end_date=date(2026, 3, 4),
        )

        self.planning_maths = ExamPlanning.objects.create(
            session=self.composition,
            classroom=self.sixieme,
            subject=self.maths,
            exam_date=date(2025, 12, 1),
            start_time=time(8, 0),
            end_time=time(10, 0),
        )
        self.planning_sport = ExamPlanning.objects.create(
            session=self.composition,
            classroom=self.sixieme,
            subject=self.sport,
            exam_date=date(2025, 12, 3),
            start_time=time(10, 0),
            end_time=time(11, 0),
        )

        # Un eleve, son parent, et un camarade sans lien: c'est ce qui permet
        # de verifier que chacun ne voit que ce qui le concerne.
        parent_user = User.objects.create_user(
            username="parent_exam",
            password="parent12345",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        self.parent_profile = ParentProfile.objects.create(
            user=parent_user, etablissement=self.etablissement
        )
        self.parent_user = parent_user

        self.eleve = self._eleve("M001", "Awa", parent=self.parent_profile)
        self.camarade = self._eleve("M002", "Bala")

        self.resultat_eleve = ExamResult.objects.create(
            session=self.composition,
            student=self.eleve,
            subject=self.maths,
            score=Decimal("15.50"),
        )
        self.resultat_camarade = ExamResult.objects.create(
            session=self.composition,
            student=self.camarade,
            subject=self.maths,
            score=Decimal("9.00"),
        )

    def _eleve(self, matricule, prenom, parent=None):
        user = User.objects.create_user(
            username=f"eleve_{matricule}",
            password="eleve12345",
            role=UserRole.STUDENT,
            first_name=prenom,
            last_name="Test",
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=user,
            matricule=matricule,
            classroom=self.sixieme,
            etablissement=self.etablissement,
            parent=parent,
        )

    def _resultats(self, reponse):
        data = reponse.data
        if isinstance(data, dict) and "results" in data:
            return data["results"]
        return data

    # ----- filtres et recherche ----------------------------------------

    def test_searching_sessions_by_title(self):
        """`?search=` etait accepte puis ignore sur tout le module."""
        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/exam-sessions/", {"search": "Rattrapage"})
        )

        self.assertEqual([row["title"] for row in trouves], ["Rattrapage"])

    def test_filtering_sessions_by_term(self):
        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/exam-sessions/", {"term": "T2"})
        )

        self.assertEqual([row["title"] for row in trouves], ["Rattrapage"])

    def test_filtering_plannings_by_session_and_ordering_by_date(self):
        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get(
                "/api/exam-plannings/",
                {"session": self.composition.id, "ordering": "exam_date"},
            )
        )

        self.assertEqual(
            [row["id"] for row in trouves],
            [self.planning_maths.id, self.planning_sport.id],
        )

    def test_searching_plannings_by_subject_name(self):
        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/exam-plannings/", {"search": "physique"})
        )

        self.assertEqual([row["id"] for row in trouves], [self.planning_sport.id])

    def test_searching_results_by_student_matricule(self):
        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/exam-results/", {"search": "M002"})
        )

        self.assertEqual([row["id"] for row in trouves], [self.resultat_camarade.id])

    def test_ordering_results_by_score(self):
        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/exam-results/", {"ordering": "-score"})
        )

        self.assertEqual(
            [row["id"] for row in trouves],
            [self.resultat_eleve.id, self.resultat_camarade.id],
        )

    def test_searching_invigilations_by_supervisor_name(self):
        autre_surveillant = User.objects.create_user(
            username="surveillant_bis",
            password="surveillant12345",
            role=UserRole.SUPERVISOR,
            first_name="Fatou",
            last_name="Kone",
            etablissement=self.etablissement,
        )
        ExamInvigilation.objects.create(
            planning=self.planning_maths, supervisor=self.surveillant
        )
        attendue = ExamInvigilation.objects.create(
            planning=self.planning_sport, supervisor=autre_surveillant
        )

        self.client.force_authenticate(self.directeur)
        trouves = self._resultats(
            self.client.get("/api/exam-invigilations/", {"search": "Kone"})
        )

        self.assertEqual([row["id"] for row in trouves], [attendue.id])

    # ----- perimetre par role ------------------------------------------

    def test_a_student_only_sees_their_own_results(self):
        self.client.force_authenticate(self.eleve.user)
        trouves = self._resultats(self.client.get("/api/exam-results/"))

        self.assertEqual([row["id"] for row in trouves], [self.resultat_eleve.id])

    def test_a_parent_only_sees_their_children_results(self):
        self.client.force_authenticate(self.parent_user)
        trouves = self._resultats(self.client.get("/api/exam-results/"))

        self.assertEqual([row["id"] for row in trouves], [self.resultat_eleve.id])

    def test_a_student_cannot_record_a_result(self):
        """La matrice donne « L* » a l'eleve: il lit sa note, il ne l'ecrit pas."""
        self.client.force_authenticate(self.eleve.user)
        reponse = self.client.post(
            "/api/exam-results/",
            {
                "session": self.composition.id,
                "student": self.eleve.id,
                "subject": self.maths.id,
                "score": "20",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_supervisor_reads_the_plannings_but_does_not_write_them(self):
        """« L » pour le surveillant: il applique le planning, il ne le fait pas."""
        self.client.force_authenticate(self.surveillant)

        self.assertEqual(
            self.client.get("/api/exam-plannings/").status_code, status.HTTP_200_OK
        )
        creation = self.client.post(
            "/api/exam-plannings/",
            {
                "session": self.composition.id,
                "classroom": self.sixieme.id,
                "subject": self.maths.id,
                "exam_date": "2025-12-05",
                "start_time": "08:00",
                "end_time": "10:00",
            },
            format="json",
        )
        self.assertEqual(creation.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_director_records_a_result(self):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/exam-results/",
            {
                "session": self.rattrapage.id,
                "student": self.eleve.id,
                "subject": self.sport.id,
                "score": "13",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        self.assertEqual(
            ExamResult.objects.get(id=reponse.data["id"]).score, Decimal("13.00")
        )
