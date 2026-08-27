"""L'annee scolaire: une par ecole, une seule ouverte, sans chevauchement.

Le modele etait global -- une seule « 2025-2026 » pour les quatre ecoles,
au nom unique a l'echelle de la plateforme. Aucune ne pouvait avoir son
calendrier, ni cloturer avant les autres. Et rien n'empechait deux annees
actives: trois endroits du code resolvaient « l'annee courante » avec trois
tris differents, qui auraient alors designe des annees differentes.
"""

from datetime import date

from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement


class AcademicYearApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")

        self.directeur = User.objects.create_user(
            username="directeur_annee",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.directeur_voisin = User.objects.create_user(
            username="directeur_voisin_annee",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.autre,
        )

        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.annee_voisine = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=self.autre,
        )

    def _resultats(self, reponse):
        data = reponse.data
        if isinstance(data, dict) and "results" in data:
            return data["results"]
        return data

    # ----- une annee par ecole -----------------------------------------

    def test_two_schools_may_share_a_year_name_with_their_own_calendar(self):
        """« 2025-2026 » existe chez les deux, a des dates differentes.

        Le nom etait unique a l'echelle de la plateforme: la seconde ecole
        ne pouvait pas creer son annee.
        """
        self.assertEqual(AcademicYear.objects.filter(name="2025-2026").count(), 2)
        self.assertNotEqual(self.annee.start_date, self.annee_voisine.start_date)

    def test_a_school_only_sees_its_own_years(self):
        self.client.force_authenticate(self.directeur)
        trouvees = self._resultats(self.client.get("/api/academic-years/"))

        self.assertEqual([row["id"] for row in trouvees], [self.annee.id])
        self.assertEqual(trouvees[0]["etablissement_name"], "Lycee Central")

    def test_a_created_year_belongs_to_the_active_school(self):
        """L'etablissement est pose par la vue, jamais par l'appelant.

        Le laisser au client aurait permis d'ouvrir une annee chez la
        voisine.
        """
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/academic-years/",
            {
                "name": "2026-2027",
                "start_date": "2026-09-01",
                "end_date": "2027-06-30",
                "etablissement": self.autre.id,
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        creee = AcademicYear.objects.get(id=reponse.data["id"])
        self.assertEqual(creee.etablissement_id, self.etablissement.id)

    # ----- garde-fous de calendrier ------------------------------------

    def test_a_year_ending_before_it_starts_is_refused(self):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/academic-years/",
            {
                "name": "2026-2027",
                "start_date": "2027-06-30",
                "end_date": "2026-09-01",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("end_date", reponse.data)

    def test_overlapping_years_are_refused_inside_a_school(self):
        """Une absence datee de l'intersection n'aurait plus d'annee.

        Deux annees qui se chevauchent rendent indecidable le rattachement
        de tout ce qui porte une date.
        """
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/academic-years/",
            {
                "name": "2026-2027",
                "start_date": "2026-05-01",
                "end_date": "2027-04-30",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("start_date", reponse.data)

    def test_the_same_period_is_fine_in_another_school(self):
        """Le chevauchement se juge par ecole, pas globalement."""
        self.client.force_authenticate(self.directeur_voisin)
        reponse = self.client.post(
            "/api/academic-years/",
            {
                "name": "2024-2025",
                "start_date": "2024-09-01",
                "end_date": "2025-06-30",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)

    def test_the_database_refuses_two_active_years_in_one_school(self):
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                AcademicYear.objects.create(
                    name="2026-2027",
                    start_date=date(2026, 9, 1),
                    end_date=date(2027, 6, 30),
                    is_active=True,
                    etablissement=self.etablissement,
                )

    # ----- activation et cloture ---------------------------------------

    def test_activating_a_year_stands_down_the_previous_one(self):
        suivante = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 6, 30),
            etablissement=self.etablissement,
        )

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(f"/api/academic-years/{suivante.id}/activer/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        suivante.refresh_from_db()
        self.annee.refresh_from_db()
        self.assertTrue(suivante.is_active)
        self.assertFalse(self.annee.is_active)

    def test_closing_a_year_also_stands_it_down(self):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(f"/api/academic-years/{self.annee.id}/cloturer/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.annee.refresh_from_db()
        self.assertTrue(self.annee.is_closed)
        self.assertFalse(self.annee.is_active)

    def test_a_closed_year_cannot_become_the_working_year_again(self):
        self.annee.is_closed = True
        self.annee.is_active = False
        self.annee.save()

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(f"/api/academic-years/{self.annee.id}/activer/")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_a_reopened_year_may_be_activated_again(self):
        self.annee.is_closed = True
        self.annee.is_active = False
        self.annee.save()

        self.client.force_authenticate(self.directeur)
        self.client.post(f"/api/academic-years/{self.annee.id}/rouvrir/")
        reponse = self.client.post(f"/api/academic-years/{self.annee.id}/activer/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.annee.refresh_from_db()
        self.assertTrue(self.annee.is_active)

    # ----- resolution unique de l'annee courante ------------------------

    def test_courante_answers_per_school(self):
        """Le point unique de resolution.

        `filter(is_active=True).first()`, `.order_by("-id").first()` et
        `.order_by("-start_date", "-id").first()` coexistaient dans trois
        vues, sans portee d'etablissement.
        """
        self.assertEqual(AcademicYear.courante(self.etablissement), self.annee)
        self.assertEqual(AcademicYear.courante(self.autre), self.annee_voisine)

    def test_courante_is_none_when_a_school_has_no_open_year(self):
        vierge = Etablissement.objects.create(name="Ecole Neuve")
        self.assertIsNone(AcademicYear.courante(vierge))

    def test_classrooms_follow_the_year_of_their_own_school(self):
        classe = ClassRoom.objects.create(
            name="6e A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.assertEqual(classe.academic_year.etablissement_id, classe.etablissement_id)
