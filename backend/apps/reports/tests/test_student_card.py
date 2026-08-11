"""La carte scolaire est un document officiel: rien n'y doit etre invente.

Elle affichait le telephone et l'etage d'un etablissement precis des que le
sien n'en avait pas — ce qui etait le cas de trois ecoles sur quatre. Elle
portait aussi deux numeros concurrents, dont la cle primaire en base, et un
QR absent la rendait invverifiable. Ces tests fixent ce qui ne doit pas
revenir.
"""

from datetime import date

from django.test import SimpleTestCase
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.card_verification import signature_valide, signer
from apps.reports.views import (
    CARD_FORMATS,
    _build_student_cards_pdf,
    _ecourte,
    _school_acronym,
    _school_identity_for_student,
)
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class AcronymeTests(SimpleTestCase):
    def test_it_uses_initials_instead_of_cutting_mid_word(self):
        """`name[:16]` donnait « COMPLEXE SCOLAIR »."""
        self.assertEqual(_school_acronym("Complexe Scolaire Oumar Bah"), "CSOB")

    def test_it_ignores_linking_words(self):
        self.assertEqual(_school_acronym("Groupe Scolaire les Hirondelles"), "GSH")

    def test_a_short_name_is_left_alone(self):
        """Abreger « LTOB » n'aurait aucun sens."""
        self.assertEqual(_school_acronym("LTOB"), "LTOB")
        self.assertEqual(_school_acronym("IFP-OBK"), "IFP-OBK")

    def test_two_initials_fall_back_to_the_full_name(self):
        """« LP » ne distingue rien."""
        self.assertEqual(_school_acronym("Lycee de la Paix"), "LYCEE DE LA PAIX")


class TroncatureTests(SimpleTestCase):
    def test_a_cut_value_is_marked(self):
        """Sans marque, « Mamadou Ouali » se lit comme un nom complet."""
        self.assertEqual(_ecourte("Mamadou Oualiyou Diallo", 17), "Mamadou Oualiy...")

    def test_a_short_value_is_untouched(self):
        self.assertEqual(_ecourte("Diarra", 17), "Diarra")


class SignatureCarteTests(SimpleTestCase):
    def test_a_signature_matches_only_its_student_and_year(self):
        signature = signer(42, "2025-2026")

        self.assertTrue(signature_valide(42, "2025-2026", signature))
        self.assertFalse(signature_valide(43, "2025-2026", signature))
        self.assertFalse(signature_valide(42, "2024-2025", signature))

    def test_an_empty_signature_is_refused(self):
        self.assertFalse(signature_valide(42, "2025-2026", ""))


class CarteScolaireTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        # Sans telephone ni adresse, comme trois des quatre ecoles reelles.
        cls.etablissement = Etablissement.objects.create(name="Complexe Scolaire Oumar Bah")
        cls.classroom = ClassRoom.objects.create(
            name="10eme A", academic_year=cls.year, etablissement=cls.etablissement
        )
        cls.directeur = User.objects.create_user(
            username="directeur_carte",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_carte",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=eleve_user,
            classroom=cls.classroom,
            etablissement=cls.etablissement,
            gender="F",
            birth_date=date(2010, 5, 4),
        )

    def setUp(self):
        self.client.force_authenticate(self.directeur)

    def test_a_school_without_a_phone_borrows_no_one_elses(self):
        """Le repli faisait imprimer le telephone du LTOB sur 171 cartes."""
        identite = _school_identity_for_student(self.eleve)

        self.assertEqual(identite["name"], "Complexe Scolaire Oumar Bah")
        self.assertEqual(identite["phone"], "")
        self.assertEqual(identite["level"], "")
        self.assertEqual(identite["short"], "CSOB")

    def test_the_card_is_produced_in_both_formats(self):
        for card_format in CARD_FORMATS:
            with self.subTest(card_format=card_format):
                response = self.client.get(
                    f"/api/reports/student-card/{self.eleve.id}/",
                    {"card_format": card_format},
                    HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
                )
                self.assertEqual(response.status_code, status.HTTP_200_OK)
                self.assertEqual(response["Content-Type"], "application/pdf")
                self.assertTrue(response.content.startswith(b"%PDF"))

    def test_an_unknown_format_is_refused_rather_than_silently_replaced(self):
        """Une planche imprimee au mauvais format ne se rattrape pas."""
        response = self.client.get(
            f"/api/reports/student-card/{self.eleve.id}/",
            {"card_format": "a3"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_wallet_sheet_holds_more_cards_than_the_a6_one(self):
        """Une planche A4 tient 8 cartes CR80 contre 2 au format A6."""
        eleves = [self.eleve] * 10
        pages = {}
        for card_format in ("a6", "cr80"):
            pdf = _build_student_cards_pdf(
                eleves,
                school=_school_identity_for_student(self.eleve),
                logo_path=None,
                layout_mode="a4",
                card_format=card_format,
            )
            pages[card_format] = pdf.pages_count

        self.assertLess(pages["cr80"], pages["a6"])


class VerificationCarteTests(APITestCase):
    """La page scannee ne doit reveler aucune identite.

    Une carte perdue et ramassee par un inconnu ne doit rien lui apprendre sur
    l'eleve: ni son nom, ni sa date de naissance, ni sa classe.
    """

    @classmethod
    def setUpTestData(cls):
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        user = User.objects.create_user(
            username="eleve_verif",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
            first_name="Alimata",
            last_name="Diarra",
        )
        cls.eleve = Student.objects.create(
            user=user,
            etablissement=cls.etablissement,
            gender="F",
            birth_date=date(2010, 5, 4),
        )

    def _verifier(self, annee, signature, student_id=None):
        cible = student_id if student_id is not None else self.eleve.id
        return self.client.get(f"/api/reports/carte/{cible}/{annee}/{signature}/")

    def test_a_valid_card_is_recognised_without_logging_in(self):
        """Celui qui controle au portail n'a pas de compte."""
        response = self._verifier("2025-2026", signer(self.eleve.id, "2025-2026"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("Carte valide", response.content.decode())

    def test_it_never_shows_the_student_identity(self):
        response = self._verifier("2025-2026", signer(self.eleve.id, "2025-2026"))
        page = response.content.decode()

        self.assertNotIn("Alimata", page)
        self.assertNotIn("Diarra", page)
        self.assertNotIn("04/05/2010", page)

    def test_a_forged_signature_is_rejected(self):
        response = self._verifier("2025-2026", "0" * 16)

        self.assertIn("Carte non reconnue", response.content.decode())

    def test_a_card_from_a_past_year_is_shown_as_expired(self):
        """Sans echeance, la carte de 2019 ressemblait a celle de cette annee."""
        response = self._verifier("2019-2020", signer(self.eleve.id, "2019-2020"))

        self.assertIn("Carte expiree", response.content.decode())

    def test_an_archived_student_card_is_revoked(self):
        Student.objects.filter(pk=self.eleve.pk).update(is_archived=True)

        response = self._verifier("2025-2026", signer(self.eleve.id, "2025-2026"))

        self.assertIn("Carte revoquee", response.content.decode())

    def test_an_unknown_student_reveals_nothing(self):
        """Les identifiants ne doivent pas s'enumerer."""
        response = self._verifier("2025-2026", signer(999999, "2025-2026"), student_id=999999)

        self.assertIn("Carte non reconnue", response.content.decode())
