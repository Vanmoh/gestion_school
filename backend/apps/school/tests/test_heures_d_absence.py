"""Les heures manquées, et non seulement les journées.

Une absence était tout ou rien: l'élève parti à la récréation comptait comme
celui qui n'est jamais venu. Au lycée, où l'on compte les heures et non les
journées, cela ne dit rien de ce qu'un élève a réellement manqué.

Le champ est nul par défaut, et c'est délibéré: `null` veut dire « journée
entière, non quantifiée » — ce que sont toutes les absences déjà saisies.
Zéro voudrait dire « aucune heure manquée », ce qui est faux.
"""

from datetime import date
from decimal import Decimal

from django.core.cache import cache
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Attendance,
    ClassRoom,
    Etablissement,
    Student,
)


class HeuresDAbsenceTests(APITestCase):
    def setUp(self):
        # Les compteurs du tableau de bord vivent une minute en cache, et le
        # cache survit d'un test a l'autre: sans ce vidage, l'ordre
        # d'execution deciderait du resultat.
        cache.clear()
        self.etablissement = Etablissement.objects.create(name="Lycee des Heures")
        aujourd_hui = timezone.now().date()
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(aujourd_hui.year, 1, 1),
            end_date=date(aujourd_hui.year, 12, 31),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.classe = ClassRoom.objects.create(
            name="Terminale", academic_year=self.annee, etablissement=self.etablissement
        )
        self.directeur = User.objects.create_user(
            username="directeur_heures",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_heures",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.eleve = Student.objects.create(
            user=eleve_user,
            matricule="H001",
            classroom=self.classe,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(self.directeur)

    def _absence(self, quand=None, heures=None):
        return Attendance.objects.create(
            student=self.eleve,
            academic_year=self.annee,
            date=quand or timezone.now().date(),
            is_absent=True,
            hours=heures,
        )

    # ----- le champ lui-même --------------------------------------------

    def test_une_absence_non_quantifiee_reste_possible(self):
        """Toutes les absences déjà saisies sont dans ce cas."""
        absence = self._absence()

        self.assertIsNone(absence.hours)

    def test_les_heures_se_renseignent(self):
        absence = self._absence(heures=Decimal("2.5"))

        absence.refresh_from_db()
        self.assertEqual(absence.hours, Decimal("2.50"))

    def test_un_nombre_d_heures_negatif_est_refuse(self):
        absence = self._absence()
        absence.hours = Decimal("-1")

        with self.assertRaises(DjangoValidationError):
            absence.full_clean()

    def test_plus_de_vingt_quatre_heures_est_refuse(self):
        absence = self._absence()
        absence.hours = Decimal("25")

        with self.assertRaises(DjangoValidationError):
            absence.full_clean()

    # ----- ce que le tableau de bord en fait -----------------------------

    def _stats(self):
        reponse = self.client.get("/api/dashboard/")
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        return reponse.data

    def test_les_heures_sont_additionnees(self):
        self._absence(heures=Decimal("2"))
        self._absence(quand=timezone.now().date().replace(day=1), heures=Decimal("4"))

        stats = self._stats()

        self.assertEqual(Decimal(str(stats["monthly_absence_hours"])), Decimal("6"))

    def test_le_nombre_d_absences_reste_la_mesure_principale(self):
        """Toutes les écoles ne quantifient pas: le compte de journées reste."""
        self._absence(heures=Decimal("2"))
        self._absence(quand=timezone.now().date().replace(day=1))

        stats = self._stats()

        self.assertEqual(stats["monthly_absences"], 2)
        self.assertEqual(Decimal(str(stats["monthly_absence_hours"])), Decimal("2"))

    def test_sans_aucune_heure_renseignee_le_total_vaut_zero(self):
        self._absence()

        stats = self._stats()

        self.assertEqual(stats["monthly_absences"], 1)
        self.assertEqual(Decimal(str(stats["monthly_absence_hours"])), Decimal("0"))

    def test_les_heures_voyagent_par_l_API(self):
        self._absence(heures=Decimal("3"))

        reponse = self.client.get("/api/attendances/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(Decimal(str(reponse.data["results"][0]["hours"])), Decimal("3"))

    def test_les_heures_se_saisissent_par_l_API(self):
        reponse = self.client.post(
            "/api/attendances/",
            {
                "student": self.eleve.id,
                "academic_year": self.annee.id,
                "date": timezone.now().date().isoformat(),
                "is_absent": True,
                "hours": "1.5",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Attendance.objects.get().hours, Decimal("1.50"))
