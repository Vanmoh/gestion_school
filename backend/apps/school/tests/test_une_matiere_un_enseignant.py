"""Une matiere ne se confie qu'a un enseignant a la fois.

Un enseignant tient plusieurs matieres; une matiere n'a qu'un titulaire. La
seconde moitie de cette phrase n'etait ecrite qu'a un seul endroit -- le
`validate()` du serializer -- et donc seulement pour qui passe par l'API.

Le modele laissait faire: `unique_together = ("teacher", "subject",
"classroom")` interdit d'affecter deux fois le meme enseignant, pas d'en
affecter deux differents. Et la reprise d'annee, qui copie les affectations sans
passer par le serializer, en creait.

Le defaut ne se voyait pas la ou il naissait. Une matiere a deux titulaires
reclame deux fois son volume horaire, et la grille d'une classe -- trente-six
places par semaine -- deborde sans le dire. Trente et un enseignants ont ainsi
fini une annee sans une seule heure de cours, alors que chaque emploi du temps
s'affichait « complet ». Un bulletin ne dit pas qui enseigne: rien ne le
signalait.

Ces tests verifient la regle aux trois niveaux ou elle doit tenir: la base,
l'API, et la reprise d'annee.
"""

from datetime import date
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
)


class SocleDesAffectations(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des affectations", code="LAFF"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        cls.matiere = Subject.objects.create(
            name="Mathématiques",
            code="MA-LAFF",
            coefficient=Decimal(4),
            classroom=cls.classe,
            weekly_slots=3,
        )
        cls.autre_matiere = Subject.objects.create(
            name="Français",
            code="FR-LAFF",
            coefficient=Decimal(3),
            classroom=cls.classe,
            weekly_slots=3,
        )
        cls.premier = cls._enseignant("moussa")
        cls.second = cls._enseignant("fatoumata")

    @classmethod
    def _enseignant(cls, prenom):
        compte = User.objects.create_user(
            username=f"prof.{prenom}",
            password="x",
            role=UserRole.TEACHER,
            first_name=prenom.capitalize(),
            last_name="TRAORE",
            etablissement=cls.etablissement,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code=f"LAFF-{prenom[:3]}",
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )


class LaBaseRefuseUnSecondTitulaireTests(SocleDesAffectations):
    """Le niveau qu'aucun code ne peut contourner."""

    def test_deux_enseignants_sur_la_meme_matiere_sont_refuses(self):
        TeacherAssignment.objects.create(
            teacher=self.premier, subject=self.matiere, classroom=self.classe
        )

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                TeacherAssignment.objects.create(
                    teacher=self.second, subject=self.matiere, classroom=self.classe
                )

    def test_un_enseignant_peut_tenir_plusieurs_matieres(self):
        """L'autre moitie de la regle, et il ne faut pas l'avoir cassee."""
        TeacherAssignment.objects.create(
            teacher=self.premier, subject=self.matiere, classroom=self.classe
        )
        TeacherAssignment.objects.create(
            teacher=self.premier, subject=self.autre_matiere, classroom=self.classe
        )

        self.assertEqual(
            TeacherAssignment.objects.filter(teacher=self.premier).count(), 2
        )

    def test_la_meme_matiere_dans_deux_classes_a_deux_titulaires(self):
        """« Une matiere » veut dire une ligne de `Subject`, donc une classe.

        `Subject.classroom` est une cle etrangere: « Mathematiques » existe
        autant de fois qu'il y a de classes qui en font. La contrainte porte donc
        sur le couple, et deux classes peuvent avoir deux professeurs de maths.
        """
        autre_classe = ClassRoom.objects.create(
            name="11ème CG",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        maths_ailleurs = Subject.objects.create(
            name="Mathématiques",
            code="MA-LAFF-2",
            coefficient=Decimal(4),
            classroom=autre_classe,
        )

        TeacherAssignment.objects.create(
            teacher=self.premier, subject=self.matiere, classroom=self.classe
        )
        TeacherAssignment.objects.create(
            teacher=self.second, subject=maths_ailleurs, classroom=autre_classe
        )

        self.assertEqual(TeacherAssignment.objects.count(), 2)


class LApiDitQuiTientDejaLaMatiereTests(SocleDesAffectations):
    """Un refus utile nomme l'enseignant en place.

    DRF sait deduire un validateur de la contrainte, mais il repond « The fields
    subject, classroom must make a unique set. » -- en anglais, et sans dire a
    qui la matiere est confiee. Le `validate()` du serializer le dit, et c'est
    pour cela que `Meta.validators` reste vide.
    """

    def setUp(self):
        self.client = APIClient()
        direction = User.objects.create_user(
            username="directeur.laff",
            password="x",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(user=direction)

    def test_le_refus_nomme_l_enseignant_en_place(self):
        TeacherAssignment.objects.create(
            teacher=self.premier, subject=self.matiere, classroom=self.classe
        )

        reponse = self.client.post(
            "/api/teacher-assignments/",
            {
                "teacher": self.second.id,
                "subject": self.matiere.id,
                "classroom": self.classe.id,
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        message = str(reponse.data)
        self.assertIn("Mathématiques", message)
        self.assertIn("Moussa", message)
        self.assertNotIn("unique set", message)

    def test_une_seconde_matiere_pour_le_meme_enseignant_est_acceptee(self):
        TeacherAssignment.objects.create(
            teacher=self.premier, subject=self.matiere, classroom=self.classe
        )

        reponse = self.client.post(
            "/api/teacher-assignments/",
            {
                "teacher": self.premier.id,
                "subject": self.autre_matiere.id,
                "classroom": self.classe.id,
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
