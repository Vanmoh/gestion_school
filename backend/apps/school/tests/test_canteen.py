"""La cantine: l'abonnement pilote enfin le service.

`CanteenSubscription` portait une periode, un statut et une limite
quotidienne que rien ne consultait. La fiche existait, elle ne decidait de
rien: on servait trois fois un eleve limite a un repas, un eleve dont
l'abonnement etait termine, ou un eleve qui n'en avait jamais eu.
"""

from datetime import date, timedelta
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    CanteenMenu,
    CanteenService,
    CanteenSubscription,
    CanteenSubscriptionStatus,
    ClassRoom,
    Etablissement,
    Student,
)


class _CantineMixin:
    @classmethod
    def _decor(cls, nom="Etab Cantine"):
        cls.etablissement = Etablissement.objects.create(name=nom, code="EC")
        cls.annee = AcademicYear.objects.create(
            name=f"2025-2026 {nom[-3:]}",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.menu = CanteenMenu.objects.create(
            etablissement=cls.etablissement,
            menu_date=date(2025, 10, 6),
            name="Riz sauce arachide",
            unit_price=Decimal("500.00"),
        )
        cls.intendant = User.objects.create_user(
            username=f"int_{nom.lower().replace(' ', '_')}",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _eleve(cls, username):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=user,
            classroom=cls.classe,
            etablissement=cls.etablissement,
            gender="M",
        )

    @classmethod
    def _abonner(cls, eleve, limite=1, statut=CanteenSubscriptionStatus.ACTIVE,
                 debut=date(2025, 9, 1), fin=None):
        return CanteenSubscription.objects.create(
            student=eleve,
            academic_year=cls.annee,
            start_date=debut,
            end_date=fin,
            daily_limit=limite,
            status=statut,
        )

    def _servir(self, eleve, quantite=1, jour=date(2025, 10, 6)):
        return self.client.post(
            "/api/canteen-services/",
            {
                "student": eleve.id,
                "menu": self.menu.id,
                "served_on": jour.isoformat(),
                "quantity": quantite,
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )


class AbonnementRequisTests(_CantineMixin, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._decor()
        cls.abonne = cls._eleve("eleve_abonne")
        cls.sans_abonnement = cls._eleve("eleve_sans")
        cls._abonner(cls.abonne, limite=1)

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.intendant)

    def test_un_eleve_abonne_est_servi(self):
        reponse = self._servir(self.abonne)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_un_eleve_sans_abonnement_ne_l_est_pas(self):
        reponse = self._servir(self.sans_abonnement)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("student", reponse.data)

    def test_un_abonnement_termine_ne_sert_plus(self):
        eleve = self._eleve("eleve_termine")
        self._abonner(eleve, statut=CanteenSubscriptionStatus.ENDED)

        reponse = self._servir(eleve)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_abonnement_suspendu_ne_sert_pas_non_plus(self):
        eleve = self._eleve("eleve_suspendu")
        self._abonner(eleve, statut=CanteenSubscriptionStatus.SUSPENDED)

        reponse = self._servir(eleve)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_abonnement_qui_commence_plus_tard_ne_couvre_pas_aujourd_hui(self):
        """La periode compte autant que le statut."""
        eleve = self._eleve("eleve_futur")
        self._abonner(eleve, debut=date(2026, 1, 5))

        reponse = self._servir(eleve, jour=date(2025, 10, 6))

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_abonnement_expire_ne_couvre_plus(self):
        eleve = self._eleve("eleve_expire")
        self._abonner(eleve, debut=date(2025, 9, 1), fin=date(2025, 9, 30))

        reponse = self._servir(eleve, jour=date(2025, 10, 6))

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_abonnement_sans_fin_couvre_toute_l_annee(self):
        eleve = self._eleve("eleve_ouvert")
        self._abonner(eleve, debut=date(2025, 9, 1), fin=None)

        reponse = self._servir(eleve, jour=date(2026, 5, 12))

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)


class LimiteQuotidienneTests(_CantineMixin, APITestCase):
    """`daily_limit` etait collecte et jamais applique."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Limite")
        cls.eleve = cls._eleve("eleve_limite")
        cls._abonner(cls.eleve, limite=1)

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.intendant)

    def test_le_premier_repas_du_jour_passe(self):
        self.assertEqual(
            self._servir(self.eleve).status_code, status.HTTP_201_CREATED
        )

    def test_le_second_repas_du_meme_jour_est_refuse(self):
        self._servir(self.eleve)

        reponse = self._servir(self.eleve)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("quantity", reponse.data)

    def test_le_refus_dit_ce_qui_reste(self):
        self._servir(self.eleve)

        reponse = self._servir(self.eleve)

        self.assertIn("0 restant", str(reponse.data))

    def test_le_lendemain_repart_a_zero(self):
        self._servir(self.eleve, jour=date(2025, 10, 6))

        reponse = self._servir(self.eleve, jour=date(2025, 10, 7))

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_une_quantite_qui_depasse_d_un_coup_est_refusee(self):
        reponse = self._servir(self.eleve, quantite=3)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_limite_a_deux_autorise_deux_repas(self):
        eleve = self._eleve("eleve_deux")
        self._abonner(eleve, limite=2)

        premier = self._servir(eleve)
        second = self._servir(eleve)
        troisieme = self._servir(eleve)

        self.assertEqual(premier.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertEqual(troisieme.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_limite_nulle_ne_borne_rien(self):
        """Zero se lit « pas de plafond », pas « aucun repas »."""
        eleve = self._eleve("eleve_illimite")
        self._abonner(eleve, limite=0)

        premier = self._servir(eleve)
        second = self._servir(eleve)

        self.assertEqual(premier.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED, second.data)

    def test_corriger_un_service_ne_se_compte_pas_deux_fois(self):
        eleve = self._eleve("eleve_correction")
        self._abonner(eleve, limite=2)
        service = self._servir(eleve, quantite=1)

        correction = self.client.patch(
            f"/api/canteen-services/{service.data['id']}/",
            {"quantity": 2},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(correction.status_code, status.HTTP_200_OK, correction.data)
        self.assertEqual(
            CanteenService.objects.get(id=service.data["id"]).quantity, 2
        )


class SuiviDesRepasTests(_CantineMixin, APITestCase):
    """Le repas non paye reste un suivi, pas une ligne de comptabilite."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Suivi")
        cls.eleve = cls._eleve("eleve_suivi")
        cls._abonner(cls.eleve, limite=2)

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.intendant)

    def test_un_repas_est_non_paye_par_defaut(self):
        reponse = self._servir(self.eleve)

        self.assertFalse(reponse.data["is_paid"])

    def test_le_repas_ne_cree_aucun_frais(self):
        """Decision d'ecole: la cantine se suit, elle ne se facture pas ici."""
        from apps.school.models import StudentFee

        self._servir(self.eleve)

        self.assertEqual(StudentFee.objects.filter(student=self.eleve).count(), 0)

    def test_les_repas_se_filtrent_par_paiement(self):
        self._servir(self.eleve)

        impayes = self.client.get(
            "/api/canteen-services/",
            {"is_paid": "false"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(len(impayes.data["results"]), 1)
