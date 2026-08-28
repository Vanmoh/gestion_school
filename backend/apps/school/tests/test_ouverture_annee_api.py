"""Ouvrir une annee en reprenant la structure de la precedente.

Preparer une rentree demandait de ressaisir a la main les classes, leurs
matieres, les affectations d'enseignants et tout l'emploi du temps -- pres
de quatre cents lignes pour une structure qui change peu d'une annee sur
l'autre.
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
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
)


class OuvertureAnneeTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")
        self.directeur = User.objects.create_user(
            username="directeur_ouverture",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.censeur = User.objects.create_user(
            username="censeur_ouverture",
            password="censeur12345",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )

        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )

        self.sixieme = ClassRoom.objects.create(
            name="6e A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.cinquieme = ClassRoom.objects.create(
            name="5e A", academic_year=self.annee, etablissement=self.etablissement
        )

        self.maths = Subject.objects.create(
            name="Maths", code="MATH", coefficient=Decimal("4"),
            classroom=self.sixieme,
        )
        self.sport = Subject.objects.create(
            name="Sport", code="EPS", coefficient=Decimal("1"),
            classroom=self.cinquieme,
        )

        enseignant_user = User.objects.create_user(
            username="enseignant_ouverture",
            password="enseignant12345",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.enseignant = Teacher.objects.create(
            user=enseignant_user, employee_code="ENS-OUV",
            hire_date=date(2020, 9, 1), salary_base=1000,
            etablissement=self.etablissement,
        )
        self.affectation = TeacherAssignment.objects.create(
            teacher=self.enseignant, subject=self.maths, classroom=self.sixieme
        )
        self.creneau = TeacherScheduleSlot.objects.create(
            assignment=self.affectation, day_of_week="MON",
            start_time=time(8, 0), end_time=time(10, 0), room="Salle 12",
        )

        # Un eleve: la reprise ne doit pas le deplacer.
        eleve_user = User.objects.create_user(
            username="eleve_ouverture",
            password="eleve12345",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.eleve = Student.objects.create(
            user=eleve_user, matricule="M001",
            classroom=self.sixieme, etablissement=self.etablissement,
        )

        self.client.force_authenticate(self.directeur)

    def _charge(self, **extra):
        charge = {
            "name": "2026-2027",
            "start_date": "2026-09-01",
            "end_date": "2027-06-30",
        }
        charge.update(extra)
        return charge

    def _ouvrir(self, **extra):
        return self.client.post(
            "/api/academic-years/ouvrir/",
            self._charge(**extra),
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    # ----- la reprise -----------------------------------------------------

    def test_opening_a_year_carries_the_whole_structure(self):
        reponse = self._ouvrir()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        reprise = reponse.data["reprise"]
        self.assertEqual(reprise["classes"], 2)
        self.assertEqual(reprise["matieres"], 2)
        self.assertEqual(reprise["affectations"], 1)
        self.assertEqual(reprise["creneaux"], 1)

        nouvelle = AcademicYear.objects.get(id=reponse.data["id"])
        self.assertEqual(nouvelle.etablissement_id, self.etablissement.id)

        classes = ClassRoom.objects.filter(academic_year=nouvelle)
        self.assertEqual({c.name for c in classes}, {"6e A", "5e A"})

        # Le creneau repris pointe la nouvelle classe, pas l'ancienne.
        creneau = TeacherScheduleSlot.objects.get(
            assignment__classroom__academic_year=nouvelle
        )
        self.assertEqual(creneau.room, "Salle 12")
        self.assertEqual(creneau.day_of_week, "MON")

    def test_students_are_never_moved(self):
        """Leur passage releve de la passation, qui decide au cas par cas."""
        self._ouvrir()

        self.eleve.refresh_from_db()
        self.assertEqual(self.eleve.classroom_id, self.sixieme.id)
        self.assertEqual(
            Student.objects.filter(classroom__academic_year__name="2026-2027").count(),
            0,
        )

    def test_each_level_may_be_left_out(self):
        reponse = self._ouvrir(
            dupliquer_affectations=False, dupliquer_emploi_du_temps=False
        )

        reprise = reponse.data["reprise"]
        self.assertEqual(reprise["classes"], 2)
        self.assertEqual(reprise["matieres"], 2)
        self.assertEqual(reprise["affectations"], 0)
        self.assertEqual(reprise["creneaux"], 0)

    def test_leaving_out_the_classrooms_closes_everything_below(self):
        """Une matiere tient a sa classe, une affectation a sa matiere.

        Sans classes reprises, les niveaux suivants n'ont plus de support:
        ils sont ignores plutot que rattaches a l'ancienne annee.
        """
        reponse = self._ouvrir(dupliquer_classes=False)

        reprise = reponse.data["reprise"]
        self.assertEqual(
            [reprise["classes"], reprise["matieres"], reprise["affectations"]],
            [0, 0, 0],
        )
        self.assertFalse(
            ClassRoom.objects.filter(academic_year__name="2026-2027").exists()
        )

    def test_two_successive_years_each_get_their_own_structure(self):
        """Ouvrir 2026-2027 puis 2027-2028 ne melange pas leurs classes.

        La reprise recopie, elle ne deplace pas: chaque annee garde les
        siennes, et l'annee source reste intacte.
        """
        premiere = self._ouvrir()
        self.assertEqual(premiere.status_code, status.HTTP_201_CREATED)

        seconde = self.client.post(
            "/api/academic-years/ouvrir/",
            {
                "name": "2027-2028",
                "start_date": "2027-09-01",
                "end_date": "2028-06-30",
                "source_academic_year": premiere.data["id"],
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(seconde.status_code, status.HTTP_201_CREATED, seconde.data)

        for nom in ("2025-2026", "2026-2027", "2027-2028"):
            self.assertEqual(
                ClassRoom.objects.filter(academic_year__name=nom).count(),
                2,
                msg=f"annee {nom}",
            )

    # ----- options --------------------------------------------------------

    def test_the_new_year_may_become_the_working_one(self):
        reponse = self._ouvrir(activer=True)

        nouvelle = AcademicYear.objects.get(id=reponse.data["id"])
        self.annee.refresh_from_db()
        self.assertTrue(nouvelle.is_active)
        self.assertFalse(self.annee.is_active)

    def test_the_previous_year_may_be_closed_in_the_same_move(self):
        self._ouvrir(activer=True, cloturer_source=True)

        self.annee.refresh_from_db()
        self.assertTrue(self.annee.is_closed)
        self.assertFalse(self.annee.is_active)

    def test_by_default_nothing_changes_for_the_current_year(self):
        """Ouvrir n'est pas basculer: la rentree se prepare a l'avance."""
        self._ouvrir()

        self.annee.refresh_from_db()
        self.assertTrue(self.annee.is_active)
        self.assertFalse(self.annee.is_closed)

    # ----- garde-fous -----------------------------------------------------

    def test_a_censor_may_not_open_a_year(self):
        """Meme exigence que la passation: c'est l'operation de rentree."""
        self.client.force_authenticate(self.censeur)
        reponse = self._ouvrir()

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(AcademicYear.objects.filter(name="2026-2027").exists())

    def test_an_overlapping_period_is_refused_and_leaves_nothing_behind(self):
        reponse = self._ouvrir(start_date="2026-05-01", end_date="2027-04-30")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(AcademicYear.objects.filter(name="2026-2027").exists())
        self.assertFalse(
            ClassRoom.objects.filter(academic_year__name="2026-2027").exists()
        )

    def test_a_source_year_of_another_school_is_refused(self):
        voisine = Etablissement.objects.create(name="Lycee Voisin")
        annee_voisine = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            etablissement=voisine,
        )

        reponse = self._ouvrir(source_academic_year=annee_voisine.id)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("source_academic_year", reponse.data)
