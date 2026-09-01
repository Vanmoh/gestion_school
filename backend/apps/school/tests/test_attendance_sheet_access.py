"""Qui accede a la feuille d'appel, et qui la cloture.

Ces regles vivaient dans trois Set codes en dur au sommet de
AttendanceViewSet, recopies dans le frontend, et contredisaient la matrice de
access.py -- laquelle refusait l'emargement au comptable et l'ecriture au
promoteur alors que la fiche les acceptait tous deux. La matrice fait
desormais foi; ce fichier verrouille le comportement qu'elle doit reproduire.
"""

from datetime import date, timedelta

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Attendance,
    ClassRoom,
    Etablissement,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
)

SHEET = "/api/attendances/class-sheet/"
VALIDATE = "/api/attendances/class-sheet-validate/"
JOURNAL = "/api/attendances/sheet-journal/"
CLASSROOMS = "/api/attendances/sheet_classrooms/"


class AttendanceSheetAccessTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.jour = date.today() - timedelta(days=1)

        eleve_user = User.objects.create_user(
            username="eleve_acces",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=eleve_user, classroom=cls.classe, etablissement=cls.etablissement
        )
        Attendance.objects.create(student=cls.eleve, date=cls.jour, is_absent=True)

        cls.comptes = {
            role: User.objects.create_user(
                username=f"acces_{role}",
                password="Pass1234!",
                role=role,
                etablissement=cls.etablissement,
            )
            for role in (
                UserRole.SUPER_ADMIN,
                UserRole.PROMOTER,
                UserRole.DIRECTOR,
                UserRole.CENSOR,
                UserRole.ACCOUNTANT,
                UserRole.SUPERVISOR,
                UserRole.PARENT,
            )
        }

        cls.enseignant_user = User.objects.create_user(
            username="acces_enseignant",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
        )
        enseignant = Teacher.objects.create(
            user=cls.enseignant_user,
            employee_code="ENS-A1",
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )
        matiere = Subject.objects.create(name="Maths", code="M1", classroom=cls.classe)
        TeacherAssignment.objects.create(
            teacher=enseignant, subject=matiere, classroom=cls.classe
        )

    def _en_tant_que(self, user):
        self.client.force_authenticate(user)

    def _entetes(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}

    def _lire_fiche(self, user):
        self._en_tant_que(user)
        return self.client.get(
            SHEET,
            {"classroom": self.classe.id, "date": self.jour.isoformat()},
            **self._entetes(),
        )

    def _ecrire_fiche(self, user):
        self._en_tant_que(user)
        return self.client.post(
            SHEET,
            {
                "classroom": self.classe.id,
                "date": self.jour.isoformat(),
                "items": [
                    {"student": self.eleve.id, "is_absent": True, "is_late": False, "reason": "x"}
                ],
            },
            format="json",
            **self._entetes(),
        )

    def _valider(self, user, lock=True):
        self._en_tant_que(user)
        return self.client.post(
            VALIDATE,
            {"classroom": self.classe.id, "date": self.jour.isoformat(), "lock": lock},
            format="json",
            **self._entetes(),
        )

    # --- Lecture -------------------------------------------------------

    def test_the_accountant_no_longer_reads_the_sheet(self):
        """La facturation ne s'appuie pas sur les absences.

        Il la lisait, faute qu'on ait demande pourquoi. Savoir quel eleve
        manquait mardi ne regarde pas la comptabilite.
        """
        self.assertEqual(
            self._lire_fiche(self.comptes[UserRole.ACCOUNTANT]).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_the_accountant_does_not_write_it(self):
        self.assertEqual(
            self._ecrire_fiche(self.comptes[UserRole.ACCOUNTANT]).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_the_promoter_reads_but_does_not_fill(self):
        """Il ne fait pas l'appel.

        Sa colonne d'ecriture venait d'une ancienne liste de roles remontee
        telle quelle dans la matrice, sans que personne ait verifie qu'elle
        decrivait le travail reel. Il garde la lecture: c'est son ecole.
        """
        self.assertEqual(
            self._lire_fiche(self.comptes[UserRole.PROMOTER]).status_code,
            status.HTTP_200_OK,
        )
        self.assertEqual(
            self._ecrire_fiche(self.comptes[UserRole.PROMOTER]).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_the_promoter_does_not_lock_either(self):
        self.assertEqual(
            self._valider(self.comptes[UserRole.PROMOTER]).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    # --- Ecriture ------------------------------------------------------

    def test_who_fills_the_sheet(self):
        for role in (
            UserRole.SUPER_ADMIN,
            UserRole.DIRECTOR,
            UserRole.CENSOR,
            UserRole.SUPERVISOR,
        ):
            with self.subTest(role=role):
                self.assertEqual(
                    self._ecrire_fiche(self.comptes[role]).status_code,
                    status.HTTP_200_OK,
                )

    def test_the_teacher_fills_his_own_classes(self):
        self.assertEqual(
            self._ecrire_fiche(self.enseignant_user).status_code, status.HTTP_200_OK
        )

    # --- Cloture -------------------------------------------------------

    def test_who_locks_the_sheet(self):
        for role in (
            UserRole.SUPER_ADMIN,
            UserRole.DIRECTOR,
            UserRole.CENSOR,
            UserRole.SUPERVISOR,
        ):
            with self.subTest(role=role):
                self.assertEqual(
                    self._valider(self.comptes[role]).status_code, status.HTTP_200_OK
                )
                self._valider(self.comptes[role], lock=False)

    def test_the_teacher_does_not_lock(self):
        """Verrouiller engage la classe entiere, pas seulement sa saisie."""
        reponse = self._valider(self.enseignant_user)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    # --- Familles ------------------------------------------------------

    def test_families_never_see_a_class_document(self):
        """Le parent lit l'assiduite de son enfant, pas la fiche de la classe."""
        parent = self.comptes[UserRole.PARENT]
        for url in (SHEET, JOURNAL, CLASSROOMS):
            with self.subTest(url=url):
                self._en_tant_que(parent)
                reponse = self.client.get(
                    url,
                    {"classroom": self.classe.id, "date": self.jour.isoformat()},
                    **self._entetes(),
                )
                self.assertIn(
                    reponse.status_code,
                    (status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN),
                )


class ConduiteTests(APITestCase):
    """La note de conduite, saisie depuis l'emargement.

    Elle ne s'ecrivait qu'en effet de bord de la creation d'une absence, via
    un formulaire qui faisait doublon avec la feuille d'appel et echouait des
    que la fiche du jour etait enregistree.
    """

    URL = "/api/attendances/conduite/"

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        user = User.objects.create_user(
            username="eleve_conduite",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=user, classroom=cls.classe, etablissement=cls.etablissement
        )
        cls.comptes = {
            role: User.objects.create_user(
                username=f"conduite_{role}",
                password="Pass1234!",
                role=role,
                etablissement=cls.etablissement,
            )
            for role in (
                UserRole.SUPERVISOR,
                UserRole.CENSOR,
                UserRole.SUPER_ADMIN,
                UserRole.DIRECTOR,
                UserRole.ACCOUNTANT,
            )
        }

    def _noter(self, user, valeur):
        self.client.force_authenticate(user)
        return self.client.post(
            self.URL,
            {"student": self.eleve.id, "conduite": valeur},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_the_supervisor_grades_conduct(self):
        reponse = self._noter(self.comptes[UserRole.SUPERVISOR], "15.5")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.eleve.refresh_from_db()
        self.assertEqual(str(self.eleve.conduite), "15.50")

    def test_the_censor_and_super_admin_too(self):
        for role in (UserRole.CENSOR, UserRole.SUPER_ADMIN):
            with self.subTest(role=role):
                self.assertEqual(
                    self._noter(self.comptes[role], "12").status_code,
                    status.HTTP_200_OK,
                )

    def test_the_director_does_not_grade_conduct(self):
        """La regle vit dans StudentSerializer, elle n'est pas recopiee ici."""
        reponse = self._noter(self.comptes[UserRole.DIRECTOR], "10")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_accountant_is_stopped_by_the_matrix(self):
        reponse = self._noter(self.comptes[UserRole.ACCOUNTANT], "10")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_a_grade_out_of_twenty(self):
        reponse = self._noter(self.comptes[UserRole.SUPERVISOR], "21")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_missing_student_is_named_as_such(self):
        """Le champ absent se nomme: la reponse disait « classroom requis »."""
        self.client.force_authenticate(self.comptes[UserRole.SUPERVISOR])
        reponse = self.client.post(
            self.URL,
            {"conduite": "14"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("student", reponse.data)

    def test_no_attendance_row_is_created(self):
        """C'etait tout le probleme: noter la conduite creait une absence."""
        self._noter(self.comptes[UserRole.SUPERVISOR], "16")

        self.assertFalse(Attendance.objects.filter(student=self.eleve).exists())
