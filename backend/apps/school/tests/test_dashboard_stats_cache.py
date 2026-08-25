"""Le tableau de bord est cache, mais l'argent saisi doit s'y voir aussitot.

Ses sept agregats sont gardes une minute: l'application les redemande a chaque
retour sur l'ecran et a chaque tirage vers le bas, et vers une base distante
ces allers-retours dominaient le temps d'affichage.

Un cache muet est une regression silencieuse: le chiffre reste juste pendant
une minute, et personne ne remarque qu'il ne bouge plus. Ces tests fixent donc
les deux moities du contrat -- servir sans recalculer, et ceder la place des
qu'un paiement ou une depense est enregistre.
"""

from datetime import date
from decimal import Decimal

from django.core.cache import cache
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.dashboard_cache import stats_cache_key
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Expense,
    FeeType,
    Payment,
    Student,
    StudentFee,
)


class DashboardStatsCacheTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.autre = Etablissement.objects.create(name="Groupe Scolaire Sabalibougou")
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classroom = ClassRoom.objects.create(
            name="10eme CT", academic_year=cls.year, etablissement=cls.etablissement
        )
        cls.director = User.objects.create_user(
            username="directeur_tableau",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_tableau",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.student = Student.objects.create(
            user=eleve_user,
            classroom=cls.classroom,
            etablissement=cls.etablissement,
        )
        cls.fee = StudentFee.objects.create(
            student=cls.student,
            academic_year=cls.year,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("50000"),
            due_date=date(2025, 10, 5),
        )

    def setUp(self):
        # Le cache survit d'un test a l'autre: sans ce vidage, l'ordre
        # d'execution deciderait du resultat.
        cache.clear()
        self.client.force_authenticate(user=self.director)

    def _stats(self):
        response = self.client.get("/api/dashboard/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        return response.data

    def _paiement(self, montant):
        return Payment.objects.create(
            fee=self.fee,
            etablissement=self.etablissement,
            amount=Decimal(montant),
            method="especes",
        )

    def test_la_deuxieme_lecture_ne_repasse_pas_par_la_base(self):
        self._stats()

        # Une ecriture directe en base, invisible des signaux d'invalidation:
        # si la reponse la reflete, c'est que rien n'a ete mis en cache.
        Payment.objects.bulk_create(
            [
                Payment(
                    fee=self.fee,
                    etablissement=self.etablissement,
                    amount=Decimal("5000"),
                    method="especes",
                )
            ]
        )

        self.assertEqual(Decimal(self._stats()["monthly_revenue"]), Decimal("0"))

    def test_un_paiement_enregistre_apparait_sans_attendre(self):
        self.assertEqual(Decimal(self._stats()["monthly_revenue"]), Decimal("0"))

        self._paiement("15000")

        self.assertEqual(Decimal(self._stats()["monthly_revenue"]), Decimal("15000"))

    def test_une_depense_enregistree_apparait_sans_attendre(self):
        self.assertEqual(Decimal(self._stats()["monthly_expenses"]), Decimal("0"))

        Expense.objects.create(
            label="Craie",
            amount=Decimal("2500"),
            date=timezone.now().date(),
            category="Fournitures",
            etablissement=self.etablissement,
        )

        self.assertEqual(Decimal(self._stats()["monthly_expenses"]), Decimal("2500"))

    def test_l_annulation_d_un_paiement_se_voit_aussi(self):
        paiement = self._paiement("9000")
        self.assertEqual(Decimal(self._stats()["monthly_revenue"]), Decimal("9000"))

        paiement.is_cancelled = True
        paiement.save()

        self.assertEqual(Decimal(self._stats()["monthly_revenue"]), Decimal("0"))

    def test_chaque_etablissement_a_sa_propre_entree(self):
        self._stats()

        month_start = timezone.now().date().replace(day=1)
        self.assertIsNotNone(cache.get(stats_cache_key(self.etablissement.id, month_start)))
        # La portee voisine ne doit rien avoir herite de cette lecture: une cle
        # partagee servirait les totaux d'une ecole a l'autre.
        self.assertIsNone(cache.get(stats_cache_key(self.autre.id, month_start)))
