"""Ce que l'ecole doit a chaque enseignant, sur l'intervalle qu'on choisit.

L'ecran de paie n'affichait que des paies deja generees, mois par mois. Pour
savoir ce qui etait du avant de generer, il fallait ouvrir l'emargement,
compter les heures a la main, puis aller chercher le taux horaire ailleurs.
"""

from datetime import date, time
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Etablissement,
    Teacher,
    TeacherTimeEntry,
)


class SyntheseDesHeuresTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Heures", code="EH2")
        AcademicYear.objects.create(
            name="2025-2026 EH2",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.comptable = User.objects.create_user(
            username="compta_heures",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
        )

        cls.awa = cls._enseignant("awa_heures", "Awa", "Traore", "ENS-01", 2500)
        cls.moussa = cls._enseignant("moussa_heures", "Moussa", "Diarra", "ENS-02", 3000)

        # Awa: 6 heures en mars, plus 4 heures hors de l'intervalle teste.
        cls._pointage(cls.awa, date(2026, 3, 2), time(8, 0), time(11, 0), 3)
        cls._pointage(cls.awa, date(2026, 3, 9), time(8, 0), time(11, 0), 3)
        cls._pointage(cls.awa, date(2026, 4, 6), time(8, 0), time(12, 0), 4)
        # Moussa: 5 heures en mars.
        cls._pointage(cls.moussa, date(2026, 3, 3), time(9, 0), time(14, 0), 5)

    @classmethod
    def _enseignant(cls, username, prenom, nom, code, taux):
        compte = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
            first_name=prenom,
            last_name=nom,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code=code,
            hire_date=date(2025, 9, 1),
            hourly_rate=Decimal(taux),
            etablissement=cls.etablissement,
        )

    @classmethod
    def _pointage(cls, enseignant, jour, arrivee, depart, heures):
        return TeacherTimeEntry.objects.create(
            teacher=enseignant,
            etablissement=cls.etablissement,
            entry_date=jour,
            check_in_time=arrivee,
            check_out_time=depart,
            worked_hours=Decimal(heures),
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)

    def _synthese(self, **parametres):
        reponse = self.client.get(
            "/api/teacher-time-entries/synthese/",
            parametres,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        return reponse.data

    def _ligne(self, charge, matricule):
        for ligne in charge["enseignants"]:
            if ligne["matricule"] == matricule:
                return ligne
        self.fail(f"{matricule} absent de la synthese")

    def test_chaque_enseignant_porte_ses_heures_et_ce_qui_lui_est_du(self):
        charge = self._synthese(debut="2026-03-01", fin="2026-03-31")

        awa = self._ligne(charge, "ENS-01")
        self.assertEqual(Decimal(awa["heures"]), Decimal("6.00"))
        self.assertEqual(Decimal(awa["taux_horaire"]), Decimal("2500.00"))
        self.assertEqual(Decimal(awa["montant_du"]), Decimal("15000.00"))
        self.assertEqual(awa["pointages"], 2)
        self.assertEqual(awa["nom"], "Awa Traore")

    def test_le_total_general_additionne_les_enseignants(self):
        # 6 h × 2 500 + 5 h × 3 000 = 30 000.
        charge = self._synthese(debut="2026-03-01", fin="2026-03-31")

        self.assertEqual(Decimal(charge["total_heures"]), Decimal("11.00"))
        self.assertEqual(Decimal(charge["total_montant"]), Decimal("30000.00"))

    def test_l_intervalle_ecarte_ce_qui_est_en_dehors(self):
        """Les 4 heures d'avril ne comptent pas dans la paie de mars."""
        charge = self._synthese(debut="2026-03-01", fin="2026-03-31")

        self.assertEqual(Decimal(self._ligne(charge, "ENS-01")["heures"]), Decimal("6.00"))

        charge_avril = self._synthese(debut="2026-04-01", fin="2026-04-30")
        self.assertEqual(
            Decimal(self._ligne(charge_avril, "ENS-01")["heures"]), Decimal("4.00")
        )

    def test_un_seul_enseignant_quand_on_le_demande(self):
        charge = self._synthese(
            debut="2026-03-01", fin="2026-03-31", teacher=self.moussa.id
        )

        self.assertEqual(len(charge["enseignants"]), 1)
        self.assertEqual(charge["enseignants"][0]["matricule"], "ENS-02")
        self.assertEqual(Decimal(charge["total_montant"]), Decimal("15000.00"))

    def test_un_intervalle_a_l_envers_se_remet_a_l_endroit(self):
        # Deux champs de date, et l'un des deux finit par passer avant l'autre.
        charge = self._synthese(debut="2026-03-31", fin="2026-03-01")

        self.assertEqual(charge["debut"], "2026-03-01")
        self.assertEqual(charge["fin"], "2026-03-31")

    def test_sans_intervalle_le_mois_courant(self):
        charge = self._synthese()

        self.assertTrue(charge["debut"].endswith("-01"))
        self.assertGreaterEqual(charge["fin"], charge["debut"])

    def test_le_detail_se_lit_sur_l_intervalle(self):
        """Le clic sur un enseignant demande ses pointages, jour par jour."""
        reponse = self.client.get(
            "/api/teacher-time-entries/",
            {
                "teacher": self.awa.id,
                "entry_date__gte": "2026-03-01",
                "entry_date__lte": "2026-03-31",
            },
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        donnees = reponse.data
        lignes = donnees["results"] if isinstance(donnees, dict) else donnees
        self.assertEqual(len(lignes), 2)
        for ligne in lignes:
            self.assertIn("entry_date", ligne)
            self.assertIn("check_in_time", ligne)
            self.assertIn("worked_hours", ligne)

    def test_un_enseignant_ne_voit_que_ses_propres_heures(self):
        # Le cloisonnement du module d'emargement s'applique ici aussi.
        self.client.force_authenticate(self.awa.user)

        charge = self._synthese(debut="2026-03-01", fin="2026-03-31")

        matricules = {ligne["matricule"] for ligne in charge["enseignants"]}
        self.assertEqual(matricules, {"ENS-01"})
