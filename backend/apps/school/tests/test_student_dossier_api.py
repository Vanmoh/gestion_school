"""Le dossier eleve consolide doit tout dire, mais seulement a qui y a droit.

L'ecran "Recherche eleve" affiche en une fois ce que l'etablissement sait d'un
eleve. Deux risques encadrent cette commodite: livrer a un profil des donnees
qu'il n'a pas le droit de lire, et laisser le cout de la requete grandir avec
le nombre de notes ou de paiements.
"""

from datetime import date, timedelta

from django.test.utils import CaptureQueriesContext
from django.db import connection
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Attendance,
    Book,
    Borrow,
    CanteenMenu,
    CanteenService,
    CanteenSubscription,
    ClassRoom,
    DisciplineIncident,
    Etablissement,
    ExamResult,
    ExamSession,
    Grade,
    ParentProfile,
    Payment,
    PromotionDecision,
    PromotionRun,
    Student,
    StudentAcademicHistory,
    StudentFee,
    Subject,
)

TOUTES_LES_SECTIONS = {
    "history",
    "promotion",
    "grades",
    "attendance",
    "discipline",
    "fees",
    "payments",
    "exams",
    "library",
    "canteen_subscriptions",
    "canteen_services",
}


class StudentDossierTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classroom = ClassRoom.objects.create(
            name="10eme CT", academic_year=cls.year, etablissement=cls.etablissement
        )

        cls.directeur = User.objects.create_user(
            username="directeur_dossier",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        cls.comptable = User.objects.create_user(
            username="comptable_dossier",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
        )

        cls.eleve = cls._make_student("cible")
        cls.autre_eleve = cls._make_student("autre")

        # Un point de donnee par section, pour que "granted" ne puisse pas
        # passer un test en restant vide.
        StudentAcademicHistory.objects.create(
            student=cls.eleve, academic_year=cls.year, classroom=cls.classroom,
            average=12, rank=4,
        )
        run = PromotionRun.objects.create(
            etablissement=cls.etablissement, source_academic_year=cls.year
        )
        PromotionDecision.objects.create(
            run=run, student=cls.eleve, source_classroom=cls.classroom,
            decision="promoted",
        )
        cls.subject = Subject.objects.create(
            name="Mathematiques", code="MATH", classroom=cls.classroom
        )
        Grade.objects.create(
            student=cls.eleve, subject=cls.subject, classroom=cls.classroom,
            academic_year=cls.year, term="T1", value=14,
        )
        Attendance.objects.create(student=cls.eleve, date=date(2025, 10, 1), is_absent=True)
        Attendance.objects.create(student=cls.eleve, date=date(2025, 10, 2), is_late=True)
        DisciplineIncident.objects.create(
            student=cls.eleve, incident_date=date(2025, 10, 3),
            category="Retard", description="Trois retards.",
        )
        cls.fee = StudentFee.objects.create(
            student=cls.eleve, academic_year=cls.year, fee_type="registration",
            amount_due=100000, due_date=date(2025, 10, 15),
        )
        Payment.objects.create(fee=cls.fee, amount=40000, method="cash")
        session = ExamSession.objects.create(
            title="Composition T1", academic_year=cls.year,
            start_date=date(2025, 12, 1), end_date=date(2025, 12, 10),
        )
        ExamResult.objects.create(
            session=session, student=cls.eleve, subject=cls.subject, score=15
        )
        book = Book.objects.create(
            title="Le petit prince", author="Saint-Exupery", isbn="978-1",
            quantity_total=3, quantity_available=2, etablissement=cls.etablissement,
        )
        Borrow.objects.create(
            student=cls.eleve, book=book,
            borrowed_at=date(2025, 10, 5), due_date=date(2025, 10, 20),
        )
        CanteenSubscription.objects.create(
            student=cls.eleve, academic_year=cls.year, start_date=date(2025, 9, 1)
        )
        menu = CanteenMenu.objects.create(
            menu_date=date(2025, 10, 6), name="Riz sauce", unit_price=500,
            etablissement=cls.etablissement,
        )
        CanteenService.objects.create(
            student=cls.eleve, menu=menu, served_on=date(2025, 10, 6)
        )

    @classmethod
    def _make_student(cls, suffixe, *, parent=None):
        user = User.objects.create_user(
            username=f"eleve_{suffixe}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=user,
            classroom=cls.classroom,
            etablissement=cls.etablissement,
            parent=parent,
        )

    def _dossier(self, eleve=None, *, attendu=status.HTTP_200_OK):
        response = self.client.get(
            f"/api/students/{(eleve or self.eleve).id}/dossier/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(response.status_code, attendu)
        return response.data

    @staticmethod
    def _section(payload, key):
        for section in payload["sections"]:
            if section["key"] == key:
                return section
        raise AssertionError(f"section absente du dossier: {key}")

    # --- Contenu ------------------------------------------------------

    def test_the_dossier_gathers_every_section_in_one_call(self):
        """Onze listes en un appel: c'est la raison d'etre de l'endpoint."""
        self.client.force_authenticate(self.directeur)
        payload = self._dossier()

        self.assertEqual(
            {section["key"] for section in payload["sections"]}, TOUTES_LES_SECTIONS
        )
        for section in payload["sections"]:
            self.assertTrue(section["granted"], section["key"])
            self.assertEqual(section["count"], len(section["items"]), section["key"])
            self.assertGreaterEqual(section["count"], 1, section["key"])

    def test_the_identity_travels_beside_the_sections(self):
        self.client.force_authenticate(self.directeur)
        payload = self._dossier()

        self.assertEqual(payload["student"]["matricule"], self.eleve.matricule)
        self.assertEqual(payload["student"]["classroom_name"], "10eme CT")

    def test_each_item_carries_readable_labels(self):
        """Plusieurs serializers partages ne rendent que des identifiants.

        GradeSerializer expose `subject: 7`; sans libelle, l'ecran afficherait
        "Matiere 7". Les libelles sont ajoutes par le dossier lui-meme.
        """
        self.client.force_authenticate(self.directeur)
        payload = self._dossier()

        note = self._section(payload, "grades")["items"][0]
        self.assertEqual(note["labels"]["matiere"], "Mathematiques")
        self.assertEqual(note["labels"]["classe"], "10eme CT")
        self.assertEqual(note["labels"]["annee"], "2025-2026")

        emprunt = self._section(payload, "library")["items"][0]
        self.assertEqual(emprunt["labels"]["livre"], "Le petit prince")

        examen = self._section(payload, "exams")["items"][0]
        self.assertEqual(examen["labels"]["matiere"], "Mathematiques")
        self.assertEqual(examen["labels"]["session"], "Composition T1")

        frais = self._section(payload, "fees")["items"][0]
        self.assertEqual(frais["labels"]["type"], "Frais inscription")

        repas = self._section(payload, "canteen_services")["items"][0]
        self.assertEqual(repas["labels"]["menu"], "Riz sauce")

    def test_summaries_describe_the_section_not_the_page(self):
        self.client.force_authenticate(self.directeur)
        payload = self._dossier()

        self.assertEqual(self._section(payload, "attendance")["summary"]["absences"], 1)
        self.assertEqual(self._section(payload, "attendance")["summary"]["retards"], 1)
        self.assertEqual(self._section(payload, "discipline")["summary"]["ouverts"], 1)

    # --- Cloisonnement ------------------------------------------------

    def test_a_section_out_of_reach_carries_no_data(self):
        """Le comptable voit les finances, pas les notes ni la discipline.

        La section refusee reste presente mais sans "items": omise, l'ecran
        afficherait "aucun incident" la ou il faut lire "acces refuse".
        """
        self.client.force_authenticate(self.comptable)
        payload = self._dossier()

        for interdite in ("grades", "discipline", "promotion", "exams", "library"):
            section = self._section(payload, interdite)
            self.assertFalse(section["granted"], interdite)
            self.assertNotIn("items", section, interdite)
            self.assertNotIn("count", section, interdite)

        for autorisee in ("fees", "payments", "canteen_services"):
            self.assertTrue(self._section(payload, autorisee)["granted"], autorisee)

    def test_the_dossier_is_closed_to_parents_and_students(self):
        """Le refus tombe sur la matrice, avant meme de chercher l'eleve.

        Le module "students" est ferme aux parents et aux eleves: ils n'ont
        acces ni au dossier de leur propre enfant ni a celui d'un autre. Le
        refus est donc un 403 uniforme, jamais un 404 qui revelerait au
        passage quels identifiants existent.
        """
        parent_user = User.objects.create_user(
            username="parent_dossier",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        parent = ParentProfile.objects.create(
            user=parent_user, etablissement=self.etablissement
        )
        sien = self._make_student("enfant_du_parent", parent=parent)

        self.client.force_authenticate(parent_user)
        self._dossier(self.eleve, attendu=status.HTTP_403_FORBIDDEN)
        self._dossier(sien, attendu=status.HTTP_403_FORBIDDEN)

        self.client.force_authenticate(self.autre_eleve.user)
        self._dossier(self.eleve, attendu=status.HTTP_403_FORBIDDEN)
        self._dossier(self.autre_eleve, attendu=status.HTTP_403_FORBIDDEN)

    def test_it_requires_authentication(self):
        self.client.force_authenticate(None)
        response = self.client.get(f"/api/students/{self.eleve.id}/dossier/")

        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    # --- Cout et exactitude -------------------------------------------

    def test_the_query_count_does_not_grow_with_the_data(self):
        """Garde-fou N+1: le dossier doit couter pareil a 5 et a 120 notes."""
        self.client.force_authenticate(self.directeur)

        with CaptureQueriesContext(connection) as maigre:
            self._dossier()

        autres_matieres = [
            Subject.objects.create(
                name=f"Matiere {index}", code=f"M{index}", classroom=self.classroom
            )
            for index in range(60)
        ]
        Grade.objects.bulk_create(
            Grade(
                student=self.eleve, subject=matiere, classroom=self.classroom,
                academic_year=self.year, term="T2", value=12,
            )
            for matiere in autres_matieres
        )
        Payment.objects.bulk_create(
            Payment(fee=self.fee, amount=1000, method="cash") for _ in range(60)
        )

        with CaptureQueriesContext(connection) as charge:
            self._dossier()

        self.assertEqual(len(charge), len(maigre))

    def test_the_count_stays_exact_when_the_list_is_truncated(self):
        """Tronquer la liste ne doit pas tronquer la verite."""
        self.client.force_authenticate(self.directeur)
        matieres = [
            Subject.objects.create(
                name=f"Matiere {index}", code=f"T{index}", classroom=self.classroom
            )
            for index in range(60)
        ]
        Grade.objects.bulk_create(
            Grade(
                student=self.eleve, subject=matiere, classroom=self.classroom,
                academic_year=self.year, term="T3", value=12,
            )
            for matiere in matieres
        )

        notes = self._section(self._dossier(), "grades")

        self.assertEqual(notes["count"], 61)
        self.assertEqual(len(notes["items"]), 50)
        self.assertTrue(notes["has_more"])

    def test_the_fee_total_is_not_multiplied_by_its_payments(self):
        """Regression: agreger sur la requete annotee comptait le du N fois.

        La section frais annote chaque ligne du montant deja paye, ce qui joint
        les paiements. Sommer amount_due sur cette meme requete rendait un du
        de 100 000 F pour 3 paiements en 300 000 F.
        """
        self.client.force_authenticate(self.directeur)
        Payment.objects.create(fee=self.fee, amount=10000, method="cash")
        Payment.objects.create(fee=self.fee, amount=10000, method="cash")

        frais = self._section(self._dossier(), "fees")

        self.assertEqual(frais["count"], 1)
        self.assertEqual(float(frais["summary"]["total_du"]), 100000.0)
        self.assertEqual(float(frais["items"][0]["amount_paid"]), 60000.0)

    def test_a_cancelled_payment_leaves_the_cash_total_alone(self):
        self.client.force_authenticate(self.directeur)
        annule = Payment.objects.create(fee=self.fee, amount=25000, method="cash")
        annule.cancel(user=self.directeur, reason="Erreur de saisie")

        paiements = self._section(self._dossier(), "payments")

        self.assertEqual(paiements["count"], 2)
        self.assertEqual(float(paiements["summary"]["total_encaisse"]), 40000.0)

    def test_an_empty_section_is_granted_but_empty(self):
        """Sans donnee, la section reste ouverte: l'absence est une reponse."""
        self.client.force_authenticate(self.directeur)
        payload = self._dossier(self.autre_eleve)

        notes = self._section(payload, "grades")
        self.assertTrue(notes["granted"])
        self.assertEqual(notes["count"], 0)
        self.assertEqual(notes["items"], [])
        self.assertFalse(notes["has_more"])

    def test_a_student_from_another_school_is_out_of_reach(self):
        autre_etab = Etablissement.objects.create(name="Autre lycee")
        autre_annee = AcademicYear.objects.create(
            name="2025-2026 bis", start_date=date(2025, 9, 1), end_date=date(2026, 7, 31)
        )
        autre_classe = ClassRoom.objects.create(
            name="6eme", academic_year=autre_annee, etablissement=autre_etab
        )
        intrus_user = User.objects.create_user(
            username="eleve_intrus", password="Pass1234!", role=UserRole.STUDENT
        )
        intrus = Student.objects.create(
            user=intrus_user, classroom=autre_classe, etablissement=autre_etab
        )

        self.client.force_authenticate(self.directeur)
        self._dossier(intrus, attendu=status.HTTP_404_NOT_FOUND)
