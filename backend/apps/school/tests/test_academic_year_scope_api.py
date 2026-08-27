"""La bascule d'annee: ce que l'ecran demande, ce que le serveur rend.

Chaque page gerait son annee dans son coin -- « Notes », « Examens » et
« Academique » avaient chacune son selecteur, et rien ne les accordait.
L'annee voyage desormais dans un en-tete, comme l'etablissement.

Une annee cloturee reste consultable. L'ecriture y est reservee a la
direction, et tracee: un bulletin deja remis ne se corrige pas en silence.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.common.models import ActivityLog
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Grade,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
)


class AcademicYearScopeTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")

        self.directeur = User.objects.create_user(
            username="directeur_scope",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.censeur = User.objects.create_user(
            username="censeur_scope",
            password="censeur12345",
            role=UserRole.CENSOR,
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
        self.annee_voisine = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.autre,
        )

        self.classe_passee = ClassRoom.objects.create(
            name="6e A", academic_year=self.annee_passee, etablissement=self.etablissement
        )
        self.classe_courante = ClassRoom.objects.create(
            name="5e A", academic_year=self.annee_courante, etablissement=self.etablissement
        )

        # La matiere est rattachee a la classe: la vue des notes verifie
        # aussi ce lien-la.
        self.maths = Subject.objects.create(
            name="Maths", coefficient=Decimal("4"), classroom=self.classe_passee
        )
        self.maths_courante = Subject.objects.create(
            name="Maths", code="MATH-C", coefficient=Decimal("4"),
            classroom=self.classe_courante,
        )

        # Une note exige que la matiere soit affectee a la classe: c'est
        # l'affectation d'enseignant qui l'etablit.
        enseignant_user = User.objects.create_user(
            username="enseignant_scope",
            password="enseignant12345",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        enseignant = Teacher.objects.create(
            user=enseignant_user,
            employee_code="ENS-SCOPE",
            hire_date=date(2020, 9, 1),
            salary_base=1000,
            etablissement=self.etablissement,
        )
        for classe, matiere in (
            (self.classe_passee, self.maths),
            (self.classe_courante, self.maths_courante),
        ):
            TeacherAssignment.objects.create(
                teacher=enseignant, subject=matiere, classroom=classe
            )
        eleve_user = User.objects.create_user(
            username="eleve_scope",
            password="eleve12345",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.eleve = Student.objects.create(
            user=eleve_user,
            matricule="M001",
            classroom=self.classe_courante,
            etablissement=self.etablissement,
        )
        # Un eleve de la classe de l'an dernier: la vue des notes verifie que
        # l'eleve appartient a la classe visee, et un eleve promu n'est plus
        # dans celle ou sa note a ete saisie.
        ancien_user = User.objects.create_user(
            username="eleve_ancien_scope",
            password="eleve12345",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.ancien_eleve = Student.objects.create(
            user=ancien_user,
            matricule="M002",
            classroom=self.classe_passee,
            etablissement=self.etablissement,
        )
        self.note_passee = Grade.objects.create(
            student=self.ancien_eleve, subject=self.maths, classroom=self.classe_passee,
            academic_year=self.annee_passee, term="T1", value=Decimal("12"),
        )
        self.note_courante = Grade.objects.create(
            student=self.eleve, subject=self.maths_courante,
            classroom=self.classe_courante,
            academic_year=self.annee_courante, term="T1", value=Decimal("15"),
        )

    def _resultats(self, reponse):
        data = reponse.data
        if isinstance(data, dict) and "results" in data:
            return data["results"]
        return data

    def _get(self, chemin, annee=None):
        entetes = {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}
        if annee is not None:
            entetes["HTTP_X_ACADEMIC_YEAR_ID"] = str(annee.id)
        return self.client.get(chemin, **entetes)

    # ----- la bascule ---------------------------------------------------

    def test_without_a_year_header_nothing_changes(self):
        """Sans en-tete, la vue rend ce qu'elle rendait avant.

        C'est ce qui permet a la bascule d'arriver ecran par ecran sans
        casser ceux qui ne la demandent pas encore.
        """
        self.client.force_authenticate(self.directeur)
        classes = self._resultats(self._get("/api/classrooms/"))
        self.assertEqual(len(classes), 2)

    def test_a_year_header_narrows_the_classrooms(self):
        self.client.force_authenticate(self.directeur)

        courantes = self._resultats(self._get("/api/classrooms/", self.annee_courante))
        self.assertEqual([row["name"] for row in courantes], ["5e A"])

        passees = self._resultats(self._get("/api/classrooms/", self.annee_passee))
        self.assertEqual([row["name"] for row in passees], ["6e A"])

    def test_a_year_header_narrows_the_grades(self):
        self.client.force_authenticate(self.directeur)

        notes = self._resultats(self._get("/api/grades/", self.annee_passee))
        self.assertEqual([row["id"] for row in notes], [self.note_passee.id])

    def test_a_year_of_another_school_is_ignored(self):
        """Une annee etrangere ne doit pas ouvrir les donnees d'a cote.

        Le controle d'appartenance vit dans la vue: sans lui, il aurait
        suffi de passer l'identifiant de l'annee voisine en en-tete.
        """
        self.client.force_authenticate(self.directeur)
        classes = self._resultats(self._get("/api/classrooms/", self.annee_voisine))

        # L'en-tete est ecarte: on retombe sur la vue non filtree de sa
        # propre ecole, et non sur les classes de la voisine.
        self.assertEqual({row["name"] for row in classes}, {"6e A", "5e A"})

    def test_the_detail_route_follows_the_same_year(self):
        self.client.force_authenticate(self.directeur)

        reponse = self._get(
            f"/api/classrooms/{self.classe_passee.id}/", self.annee_courante
        )
        self.assertEqual(reponse.status_code, status.HTTP_404_NOT_FOUND)

    # ----- annee cloturee ------------------------------------------------

    def test_a_closed_year_stays_readable(self):
        self.annee_passee.is_closed = True
        self.annee_passee.save()

        self.client.force_authenticate(self.directeur)
        notes = self._resultats(self._get("/api/grades/", self.annee_passee))
        self.assertEqual([row["id"] for row in notes], [self.note_passee.id])

    def test_a_censor_cannot_write_on_a_closed_year(self):
        """« E » sur les notes ne suffit pas apres cloture."""
        self.annee_passee.is_closed = True
        self.annee_passee.save()

        self.client.force_authenticate(self.censeur)
        reponse = self.client.patch(
            f"/api/grades/{self.note_passee.id}/",
            {"value": "18"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.note_passee.refresh_from_db()
        self.assertEqual(self.note_passee.value, Decimal("12.00"))

    def test_the_management_may_correct_a_closed_year_and_it_is_traced(self):
        self.annee_passee.is_closed = True
        self.annee_passee.save()

        self.client.force_authenticate(self.directeur)
        reponse = self.client.patch(
            f"/api/grades/{self.note_passee.id}/",
            {"value": "18"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.note_passee.refresh_from_db()
        self.assertEqual(self.note_passee.value, Decimal("18.00"))

        trace = ActivityLog.objects.filter(
            action="Ecriture sur une annee scolaire cloturee"
        ).first()
        self.assertIsNotNone(trace)
        self.assertEqual(trace.user_id, self.directeur.id)
        self.assertIn(self.annee_passee.name, trace.target)

    def test_an_open_year_is_written_without_a_trace(self):
        """Le tracage ne concerne que l'apres-cloture.

        Journaliser chaque saisie ordinaire aurait noye les corrections
        d'apres-coup au milieu du travail courant.
        """
        self.client.force_authenticate(self.directeur)
        self.client.patch(
            f"/api/grades/{self.note_courante.id}/",
            {"value": "16"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertFalse(
            ActivityLog.objects.filter(
                action="Ecriture sur une annee scolaire cloturee"
            ).exists()
        )

    def test_creating_inside_a_closed_year_is_refused_for_a_censor(self):
        self.annee_passee.is_closed = True
        self.annee_passee.save()

        self.client.force_authenticate(self.censeur)
        reponse = self.client.post(
            "/api/grades/",
            {
                "student": self.ancien_eleve.id,
                "subject": self.maths.id,
                "classroom": self.classe_passee.id,
                "academic_year": self.annee_passee.id,
                "term": "T2",
                "value": "14",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
