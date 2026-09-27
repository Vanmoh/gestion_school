"""On ne pointe que quelqu'un qui enseigne.

Un pointage dit si l'enseignant a assure ses cours ce jour-la. La question ne se
pose pas pour quelqu'un qui n'enseigne rien: il n'y a rien a assurer, rien a
manquer, rien a justifier. La base de developpement en portait pourtant neuf cent
vingt, pour cinquante-deux enseignants sans une matiere, et personne ne pouvait
le voir -- un registre d'absences ne dit pas qui enseigne quoi.

La regle est verifiee a deux endroits, et les deux comptent:

- **le signal `pre_save`**, parce que le serializer ne couvre que l'API. Les
  commandes de peuplement, l'admin Django et tout code futur ecrivent
  directement, et c'est exactement par la que les neuf cent vingt lignes sont
  arrivees;
- **le serializer**, pour que l'ecran reponde une phrase utile plutot qu'une
  erreur d'integrite.

Ce que la regle **n'exige pas** est aussi teste, parce qu'une regle trop large
casse un usage legitime et finit par etre desactivee: une declaration de
disponibilite ne demande aucune affectation -- la direction les collecte *pour*
arbitrer les affectations.
"""

from datetime import date, time
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.enseignement import enseigne_quelque_chose
from apps.school.models import (
    AcademicYear,
    AvailabilityCampaign,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherAttendance,
    TeacherAvailabilitySlot,
    TeacherScheduleSlot,
    TeacherTimeEntry,
)


class SocleDuPointage(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée du pointage", code="LPOI"
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
            code="MA-LPOI",
            coefficient=Decimal(4),
            classroom=cls.classe,
        )
        cls.en_poste = cls._enseignant("moussa")
        TeacherAssignment.objects.create(
            teacher=cls.en_poste, subject=cls.matiere, classroom=cls.classe
        )
        cls.sans_matiere = cls._enseignant("fatoumata")

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
            employee_code=f"LPOI-{prenom[:3]}",
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )


class LaRegleTientQuelQueSoitLeCheminTests(SocleDuPointage):
    """Le signal `pre_save`: celui qu'aucun code ne contourne."""

    def test_pointer_celui_qui_enseigne_fonctionne(self):
        pointage = TeacherAttendance.objects.create(
            teacher=self.en_poste,
            date=date(2026, 1, 12),
            academic_year=self.annee,
            is_absent=True,
            reason="Maladie",
        )

        self.assertIsNotNone(pointage.pk)

    def test_pointer_celui_qui_n_enseigne_rien_est_refuse(self):
        with self.assertRaises(ValidationError):
            TeacherAttendance.objects.create(
                teacher=self.sans_matiere,
                date=date(2026, 1, 12),
                academic_year=self.annee,
                is_absent=True,
            )

        self.assertEqual(TeacherAttendance.objects.count(), 0)

    def test_le_refus_nomme_l_enseignant_et_dit_quoi_faire(self):
        """Un refus qui se contente d'interdire fait perdre du temps."""
        with self.assertRaises(ValidationError) as refus:
            TeacherAttendance.objects.create(
                teacher=self.sans_matiere,
                date=date(2026, 1, 12),
                academic_year=self.annee,
            )

        message = str(refus.exception)
        self.assertIn("Fatoumata", message)
        self.assertIn("Affectez", message)

    def test_il_redevient_pointable_des_qu_on_lui_donne_une_matiere(self):
        autre = Subject.objects.create(
            name="Français",
            code="FR-LPOI",
            coefficient=Decimal(3),
            classroom=self.classe,
        )
        TeacherAssignment.objects.create(
            teacher=self.sans_matiere, subject=autre, classroom=self.classe
        )

        pointage = TeacherAttendance.objects.create(
            teacher=self.sans_matiere,
            date=date(2026, 1, 12),
            academic_year=self.annee,
        )

        self.assertIsNotNone(pointage.pk)


class L_emargement_suit_la_meme_regle_Tests(SocleDuPointage):
    """`TeacherTimeEntryCoverage` dit a quoi sert l'emargement: rapprocher une
    heure d'arrivee des cours assures. Sans matiere, il n'y a rien a couvrir.
    """

    def test_emarger_celui_qui_enseigne_fonctionne(self):
        emargement = TeacherTimeEntry.objects.create(
            teacher=self.en_poste,
            etablissement=self.etablissement,
            entry_date=date(2026, 1, 12),
            check_in_time=time(8, 5),
            check_out_time=time(17, 0),
            worked_hours=Decimal("8.00"),
            planned_minutes=480,
            covered_minutes=480,
        )

        self.assertIsNotNone(emargement.pk)

    def test_emarger_celui_qui_n_enseigne_rien_est_refuse(self):
        with self.assertRaises(ValidationError):
            TeacherTimeEntry.objects.create(
                teacher=self.sans_matiere,
                etablissement=self.etablissement,
                entry_date=date(2026, 1, 12),
                check_in_time=time(8, 5),
                worked_hours=Decimal("0.00"),
                planned_minutes=0,
                covered_minutes=0,
            )

        self.assertEqual(TeacherTimeEntry.objects.count(), 0)


class LeCreneauNAPasBesoinDeGardeTests(SocleDuPointage):
    """La regle y tient **par construction**, et cela vaut mieux qu'un controle.

    `TeacherScheduleSlot` ne porte pas de champ `teacher`: il pend a
    `assignment`. Un creneau sans affectation ne peut donc pas exister, et une
    affectation nomme exactement une matiere et une classe. C'est pour cela
    qu'aucun signal ne surveille ce modele.
    """

    def test_le_creneau_ne_connait_l_enseignant_que_par_l_affectation(self):
        champs = {f.name for f in TeacherScheduleSlot._meta.fields}

        self.assertIn("assignment", champs)
        self.assertNotIn("teacher", champs)

    def test_un_creneau_exige_une_affectation(self):
        from django.db import IntegrityError, transaction

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                TeacherScheduleSlot.objects.create(
                    assignment=None,
                    day_of_week="MON",
                    start_time=time(8, 0),
                    end_time=time(9, 0),
                )


class LApiRepondUnePhraseUtileTests(SocleDuPointage):
    def setUp(self):
        self.client = APIClient()
        # Le censeur, et non le directeur: l'emargement des enseignants est son
        # ecran, et la matrice des droits le dit -- un directeur recoit 403.
        censeur = User.objects.create_user(
            username="censeur.lpoi",
            password="x",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(user=censeur)

    def test_l_api_refuse_avec_400_et_non_une_erreur_serveur(self):
        reponse = self.client.post(
            "/api/teacher-attendances/",
            {
                "teacher": self.sans_matiere.id,
                "date": "2026-01-12",
                "academic_year": self.annee.id,
                "is_absent": True,
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Fatoumata", str(reponse.data))


class CeQueLaRegleNExigePasTests(SocleDuPointage):
    """Une regle trop large casse un usage legitime, et finit desactivee."""

    def test_une_disponibilite_ne_demande_aucune_affectation(self):
        """La direction collecte les disponibilites **pour** affecter.

        Un enseignant qui vient d'arriver doit pouvoir declarer les siennes:
        exiger une matiere ici inverserait l'ordre des choses.
        """
        campagne = AvailabilityCampaign.objects.create(
            etablissement=self.etablissement,
            academic_year=self.annee,
            status="open",
            label="Collecte de rentrée",
            opens_on=date(2025, 9, 1),
            closes_on=date(2025, 9, 20),
        )

        creneau = TeacherAvailabilitySlot.objects.create(
            teacher=self.sans_matiere,
            campaign=campagne,
            etablissement=self.etablissement,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
            kind="preferred",
        )

        self.assertIsNotNone(creneau.pk)


class LaRegleSeLitEnUnAppelTests(SocleDuPointage):
    def test_enseigne_quelque_chose_dit_vrai(self):
        self.assertTrue(enseigne_quelque_chose(self.en_poste))
        self.assertFalse(enseigne_quelque_chose(self.sans_matiere))

    def test_elle_repond_faux_sans_enseignant(self):
        self.assertFalse(enseigne_quelque_chose(None))

    def test_elle_repond_faux_pour_un_enseignant_non_enregistre(self):
        """Sans `pk`, il n'a pas d'affectation: la question n'a pas de sens."""
        self.assertFalse(enseigne_quelque_chose(Teacher()))
