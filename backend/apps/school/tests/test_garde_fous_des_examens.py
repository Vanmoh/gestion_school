"""Ce qui vaut pour la note de classe vaut pour la note de composition.

Quatre garde-fous protegeaient `Grade` et laissaient passer `ExamResult`: le
verrou de trimestre, l'annee cloturee, le perimetre de l'enseignant et la
decision de publier. Chacun se defend seul, et ensemble ils disent la meme
chose -- une note d'examen est une note, avec les memes consequences sur le
bulletin et sur le rang.
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
    ExamPlanning,
    ExamResult,
    ExamSession,
    GradeValidation,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
)


class SocleGardeFous(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycee des garde-fous", code="LGAR"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 GAR",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.sixieme = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.cinquieme = ClassRoom.objects.create(
            name="5ème B", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.maths = Subject.objects.create(
            name="Mathématiques", code="MATH", coefficient=Decimal("4")
        )

        cls.directeur = User.objects.create_user(
            username="dir_garde",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        cls.compte_enseignant = User.objects.create_user(
            username="prof_garde",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
        )
        cls.enseignant = Teacher.objects.create(
            user=cls.compte_enseignant,
            employee_code="ENS-GAR",
            hire_date=date(2025, 9, 1),
            etablissement=cls.etablissement,
        )
        # Il enseigne les maths en 6e, et rien en 5e.
        TeacherAssignment.objects.create(
            teacher=cls.enseignant, classroom=cls.sixieme, subject=cls.maths
        )

        cls.session = ExamSession.objects.create(
            title="Composition du premier trimestre",
            term="T1",
            academic_year=cls.annee,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 6),
        )
        cls.epreuve_6a = ExamPlanning.objects.create(
            session=cls.session,
            classroom=cls.sixieme,
            subject=cls.maths,
            exam_date=date(2025, 12, 2),
            start_time=time(8, 0),
            end_time=time(10, 0),
        )
        cls.epreuve_5b = ExamPlanning.objects.create(
            session=cls.session,
            classroom=cls.cinquieme,
            subject=cls.maths,
            exam_date=date(2025, 12, 3),
            start_time=time(8, 0),
            end_time=time(10, 0),
        )
        cls.eleve_6a = cls._eleve("eleve_6a_garde", "LGAR6A0001M", cls.sixieme)
        cls.eleve_5b = cls._eleve("eleve_5b_garde", "LGAR5B0001F", cls.cinquieme)

    @classmethod
    def _eleve(cls, username, matricule, classe):
        compte = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=compte,
            matricule=matricule,
            classroom=classe,
            etablissement=cls.etablissement,
        )

    def _entetes(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}

    def _saisir(self, compte, eleve, epreuve, score="14.00"):
        self.client.force_authenticate(compte)
        return self.client.post(
            "/api/exam-results/",
            {
                "session": self.session.id,
                "student": eleve.id,
                "subject": self.maths.id,
                "planning": epreuve.id,
                "score": score,
            },
            format="json",
            **self._entetes(),
        )


class VerrouDuTrimestreTests(SocleGardeFous):
    """Apres la cloture, la moyenne et le rang se contrediraient."""

    def _cloturer(self, classe):
        GradeValidation.objects.update_or_create(
            classroom=classe,
            academic_year=self.annee,
            term="T1",
            defaults={"is_validated": True},
        )

    def test_une_note_ne_se_saisit_plus_sur_un_trimestre_clos(self):
        """Le rang est fige a la cloture; la moyenne, elle, se recalcule.

        Une note saisie apres coup faisait donc dire deux choses au meme
        bulletin.
        """
        self._cloturer(self.sixieme)

        reponse = self._saisir(self.directeur, self.eleve_6a, self.epreuve_6a)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("validée", str(reponse.data))

    def test_une_note_ne_se_corrige_plus_non_plus(self):
        note = ExamResult.objects.create(
            session=self.session,
            student=self.eleve_6a,
            subject=self.maths,
            score=Decimal("9.00"),
            planning=self.epreuve_6a,
        )
        self._cloturer(self.sixieme)
        self.client.force_authenticate(self.directeur)

        reponse = self.client.patch(
            f"/api/exam-results/{note.id}/",
            {"score": "18.00"},
            format="json",
            **self._entetes(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        note.refresh_from_db()
        self.assertEqual(note.score, Decimal("9.00"))

    def test_la_cloture_d_une_classe_ne_bloque_pas_l_autre(self):
        """Le verrou est par classe, comme la validation qui le pose."""
        self._cloturer(self.sixieme)

        reponse = self._saisir(self.directeur, self.eleve_5b, self.epreuve_5b)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_la_classe_retenue_est_celle_de_l_epreuve(self):
        """Et non celle de la fiche, qui a pu changer depuis.

        Une note se rattache a l'epreuve ou elle a ete obtenue; c'est cette
        classe-la dont la cloture la concerne.
        """
        self.eleve_6a.classroom = self.cinquieme
        self.eleve_6a.save(update_fields=["classroom"])
        self._cloturer(self.sixieme)

        reponse = self._saisir(self.directeur, self.eleve_6a, self.epreuve_6a)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)


class PerimetreDeLEnseignantTests(SocleGardeFous):
    """La matrice l'annonce en `E*` depuis toujours, et rien ne l'appliquait."""

    def test_il_note_la_classe_ou_il_enseigne(self):
        reponse = self._saisir(
            self.compte_enseignant, self.eleve_6a, self.epreuve_6a
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_il_ne_note_pas_une_classe_qui_n_est_pas_la_sienne(self):
        """Il ecrivait toutes les notes d'examen de l'etablissement.

        C'est le rattachement a l'epreuve qui rend le controle possible: une
        note savait enfin dans quelle classe elle a ete obtenue.
        """
        reponse = self._saisir(
            self.compte_enseignant, self.eleve_5b, self.epreuve_5b
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("subject", reponse.data)

    def test_la_direction_n_est_pas_bornee(self):
        reponse = self._saisir(self.directeur, self.eleve_5b, self.epreuve_5b)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)


class QuiPublieTests(SocleGardeFous):
    """Ouvrir aux familles n'est pas une consequence de pouvoir corriger."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        ExamResult.objects.create(
            session=cls.session,
            student=cls.eleve_6a,
            subject=cls.maths,
            score=Decimal("15.00"),
            planning=cls.epreuve_6a,
        )

    def _publier(self, compte, route):
        self.client.force_authenticate(compte)
        return self.client.post(route, **self._entetes())

    def test_l_enseignant_ne_publie_pas_une_epreuve(self):
        """`exams` en ecriture suffisait: publier n'est qu'un POST.

        Un enseignant pouvait donc ouvrir les resultats de tout
        l'etablissement, et les refermer.
        """
        reponse = self._publier(
            self.compte_enseignant,
            f"/api/exam-plannings/{self.epreuve_6a.id}/publier/",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_l_enseignant_ne_publie_pas_une_session(self):
        reponse = self._publier(
            self.compte_enseignant,
            f"/api/exam-sessions/{self.session.id}/publier/",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_l_enseignant_ne_referme_pas_ce_qu_il_n_a_pas_ouvert(self):
        self.session.publier_les_resultats(user=self.directeur)

        reponse = self._publier(
            self.compte_enseignant,
            f"/api/exam-sessions/{self.session.id}/depublier/",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_la_direction_publie(self):
        reponse = self._publier(
            self.directeur, f"/api/exam-plannings/{self.epreuve_6a.id}/publier/"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)

    def test_le_censeur_publie_aussi(self):
        """Il arbitre la pedagogie: c'est son geste autant que celui du
        directeur."""
        censeur = User.objects.create_user(
            username="censeur_garde",
            password="Pass1234!",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )

        reponse = self._publier(
            censeur, f"/api/exam-plannings/{self.epreuve_6a.id}/publier/"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)


class AnneeCloseTests(SocleGardeFous):
    """La protection couvrait la session et pas ses trois voisines."""

    def test_une_note_ne_se_saisit_pas_sur_une_annee_cloturee(self):
        self.annee.is_closed = True
        self.annee.save(update_fields=["is_closed"])
        self.addCleanup(
            lambda: AcademicYear.objects.filter(pk=self.annee.pk).update(
                is_closed=False
            )
        )

        reponse = self._saisir(
            self.compte_enseignant, self.eleve_6a, self.epreuve_6a
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_la_direction_corrige_encore_une_annee_close_et_c_est_trace(self):
        """Une note reprise apres cloture n'est pas un geste ordinaire.

        Le mixin la reserve au niveau administration et la journalise, comme
        pour les notes de classe.
        """
        self.annee.is_closed = True
        self.annee.save(update_fields=["is_closed"])
        self.addCleanup(
            lambda: AcademicYear.objects.filter(pk=self.annee.pk).update(
                is_closed=False
            )
        )

        reponse = self._saisir(self.directeur, self.eleve_6a, self.epreuve_6a)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
