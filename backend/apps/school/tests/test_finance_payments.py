"""Les paiements des eleves: ce que l'API accepte et ce qu'elle refuse.

Le module est solidement construit -- depassement de solde refuse, doublons
detectes, reference exigee hors especes, annulation tracee -- mais rien ne le
retenait: sur une trentaine de fichiers de tests, aucun ne couvrait l'argent
de l'ecole. Ces tests ne changent rien au comportement; ils le figent.
"""

from datetime import date, timedelta
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    FeeType,
    Payment,
    Student,
    StudentFee,
)


class _FinanceMixin:
    @classmethod
    def _decor(cls, nom="Etab Finance"):
        cls.etablissement = Etablissement.objects.create(name=nom, code="EF")
        cls.annee = AcademicYear.objects.create(
            name=f"2025-2026 {nom[-4:]}",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.comptable = User.objects.create_user(
            username=f"cpt_{nom.lower().replace(' ', '_')}",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _eleve(cls, username, etablissement=None, classe=None):
        etablissement = etablissement or cls.etablissement
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=etablissement,
        )
        return Student.objects.create(
            user=user,
            classroom=classe or cls.classe,
            etablissement=etablissement,
            gender="F",
        )

    @classmethod
    def _frais(cls, eleve, montant="50000.00", annee=None):
        return StudentFee.objects.create(
            student=eleve,
            academic_year=annee or cls.annee,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal(montant),
            due_date=date(2025, 10, 5),
        )

    def _payer(self, frais, montant="10000.00", methode="Especes", **extra):
        charge = {"fee": frais.id, "amount": montant, "method": methode}
        charge.update(extra)
        return self.client.post(
            "/api/payments/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )


class SoldeEtVersementsTests(_FinanceMixin, APITestCase):
    """Le solde suit les versements, et rien ne le depasse."""

    @classmethod
    def setUpTestData(cls):
        cls._decor()
        cls.eleve = cls._eleve("eleve_solde")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)
        self.frais = self._frais(self.eleve, "50000.00")

    def test_un_versement_reduit_le_solde(self):
        reponse = self._payer(self.frais, "20000.00")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.frais.refresh_from_db()
        self.assertEqual(self.frais.amount_paid, Decimal("20000.00"))
        self.assertEqual(self.frais.balance, Decimal("30000.00"))

    def test_plusieurs_versements_s_additionnent(self):
        self._payer(self.frais, "20000.00")
        self._payer(self.frais, "15000.00")

        self.assertEqual(self.frais.amount_paid, Decimal("35000.00"))

    def test_un_versement_superieur_au_solde_est_refuse(self):
        reponse = self._payer(self.frais, "60000.00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(self.frais.amount_paid, Decimal("0.00"))

    def test_le_versement_qui_solde_exactement_passe(self):
        reponse = self._payer(self.frais, "50000.00")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(self.frais.balance, Decimal("0.00"))

    def test_le_versement_de_trop_est_refuse_apres_un_premier(self):
        self._payer(self.frais, "40000.00")

        reponse = self._payer(self.frais, "20000.00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_montant_nul_ou_negatif_est_refuse(self):
        for montant in ("0.00", "-5000.00"):
            with self.subTest(montant=montant):
                reponse = self._payer(self.frais, montant)
                self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)


class ReferenceEtDoublonsTests(_FinanceMixin, APITestCase):
    """Ce qui distingue un versement d'un autre."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Reference")
        cls.eleve = cls._eleve("eleve_reference")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)
        self.frais = self._frais(self.eleve, "100000.00")

    def test_un_paiement_non_especes_exige_sa_reference(self):
        reponse = self._payer(self.frais, "10000.00", methode="Mobile Money")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("reference", reponse.data)

    def test_une_reference_trop_courte_est_refusee(self):
        reponse = self._payer(
            self.frais, "10000.00", methode="Mobile Money", reference="AB"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_reference_valable_debloque_le_paiement(self):
        reponse = self._payer(
            self.frais, "10000.00", methode="Mobile Money", reference="MM-99881"
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_les_especes_se_passent_de_reference(self):
        reponse = self._payer(self.frais, "10000.00", methode="Especes")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_la_methode_est_normalisee(self):
        """« momo », « orange money », « wave » designent le meme canal."""
        reponse = self._payer(
            self.frais, "10000.00", methode="momo", reference="MM-12345"
        )

        self.assertEqual(reponse.data["method"], "Mobile Money")

    def test_le_meme_versement_saisi_deux_fois_est_signale(self):
        """Le double clic du guichet, attrape dans sa fenetre de trois minutes."""
        self._payer(self.frais, "10000.00")

        doublon = self._payer(self.frais, "10000.00")

        self.assertEqual(doublon.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("duplique", str(doublon.data).lower())

    def test_deux_montants_differents_ne_sont_pas_un_doublon(self):
        self._payer(self.frais, "10000.00")

        reponse = self._payer(self.frais, "12000.00")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)


class AnnulationTests(_FinanceMixin, APITestCase):
    """Un versement ne s'efface pas: il s'annule, et la trace reste."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Annulation")
        cls.eleve = cls._eleve("eleve_annulation")
        cls.direction = User.objects.create_user(
            username="dir_annulation",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)
        self.frais = self._frais(self.eleve, "50000.00")

    def _annuler(self, paiement_id, motif="Erreur de saisie"):
        return self.client.delete(
            f"/api/payments/{paiement_id}/",
            {"reason": motif},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_l_annulation_rend_le_montant_au_solde(self):
        paiement = self._payer(self.frais, "20000.00")
        self.assertEqual(self.frais.balance, Decimal("30000.00"))

        self._annuler(paiement.data["id"])

        self.assertEqual(self.frais.balance, Decimal("50000.00"))

    def test_le_paiement_annule_garde_sa_trace(self):
        paiement = self._payer(self.frais, "20000.00")

        self._annuler(paiement.data["id"], motif="Chèque sans provision")

        ligne = Payment.objects.get(id=paiement.data["id"])
        self.assertTrue(ligne.is_cancelled)
        self.assertEqual(ligne.cancel_reason, "Chèque sans provision")
        self.assertEqual(ligne.cancelled_by, self.comptable)
        self.assertIsNotNone(ligne.cancelled_at)

    def test_un_paiement_annule_sort_de_la_liste(self):
        paiement = self._payer(self.frais, "20000.00")
        self._annuler(paiement.data["id"])

        lignes = self.client.get(
            "/api/payments/", HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        ).data["results"]

        self.assertEqual([l["id"] for l in lignes], [])

    def test_annuler_deux_fois_ne_double_pas_le_remboursement(self):
        paiement = self._payer(self.frais, "20000.00")
        self._annuler(paiement.data["id"])

        self._annuler(paiement.data["id"])

        self.assertEqual(self.frais.balance, Decimal("50000.00"))

    def test_le_montant_annule_redevient_versable(self):
        paiement = self._payer(self.frais, "50000.00")
        self._annuler(paiement.data["id"])

        reprise = self._payer(self.frais, "50000.00", methode="Cheque", reference="CH-4455")

        self.assertEqual(reprise.status_code, status.HTTP_201_CREATED, reprise.data)


class CloisonnementFinanceTests(_FinanceMixin, APITestCase):
    """L'argent d'une ecole ne se voit pas depuis une autre."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Ici")
        cls.eleve = cls._eleve("eleve_ici")

        cls.voisine = Etablissement.objects.create(name="Ecole voisine finance", code="EV")
        cls.annee_voisine = AcademicYear.objects.create(
            name="2025-2026 voisine",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.voisine,
        )
        cls.classe_voisine = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee_voisine, etablissement=cls.voisine
        )
        cls.eleve_voisin = cls._eleve(
            "eleve_voisin", etablissement=cls.voisine, classe=cls.classe_voisine
        )
        cls.comptable_voisin = User.objects.create_user(
            username="cpt_voisin",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.voisine,
        )

    def test_un_comptable_ne_voit_que_les_frais_de_son_ecole(self):
        self._frais(self.eleve, "50000.00")
        StudentFee.objects.create(
            student=self.eleve_voisin,
            academic_year=self.annee_voisine,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("70000.00"),
            due_date=date(2025, 10, 5),
        )

        self.client.force_authenticate(self.comptable)
        lignes = self.client.get("/api/fees/").data["results"]

        eleves = {ligne["student"] for ligne in lignes}
        self.assertEqual(eleves, {self.eleve.id})

    def test_un_comptable_ne_paie_pas_pour_l_ecole_voisine(self):
        frais_voisin = StudentFee.objects.create(
            student=self.eleve_voisin,
            academic_year=self.annee_voisine,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("70000.00"),
            due_date=date(2025, 10, 5),
        )

        self.client.force_authenticate(self.comptable)
        reponse = self.client.post(
            "/api/payments/",
            {"fee": frais_voisin.id, "amount": "10000.00", "method": "Especes"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertIn(
            reponse.status_code,
            (status.HTTP_400_BAD_REQUEST, status.HTTP_403_FORBIDDEN, status.HTTP_404_NOT_FOUND),
        )


class AccesFinanceTests(_FinanceMixin, APITestCase):
    """Qui touche a l'argent: la matrice, rien d'autre."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Acces")
        cls.eleve = cls._eleve("eleve_acces")
        cls.comptes = {
            role: User.objects.create_user(
                username=f"finance_{role}",
                password="Pass1234!",
                role=role,
                etablissement=cls.etablissement,
            )
            for role in (
                UserRole.SUPER_ADMIN,
                UserRole.DIRECTOR,
                UserRole.PROMOTER,
                UserRole.TEACHER,
                UserRole.SUPERVISOR,
            )
        }

    def setUp(self):
        super().setUp()
        self.frais = self._frais(self.eleve, "50000.00")

    def test_l_enseignant_n_a_rien_a_faire_dans_les_finances(self):
        self.client.force_authenticate(self.comptes[UserRole.TEACHER])

        reponse = self.client.get("/api/payments/")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_le_surveillant_non_plus(self):
        self.client.force_authenticate(self.comptes[UserRole.SUPERVISOR])

        self.assertEqual(
            self.client.get("/api/payments/").status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_le_promoteur_lit_sans_encaisser(self):
        self.client.force_authenticate(self.comptes[UserRole.PROMOTER])

        lecture = self.client.get(
            "/api/payments/", HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )
        ecriture = self.client.post(
            "/api/payments/",
            {"fee": self.frais.id, "amount": "1000.00", "method": "Especes"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(lecture.status_code, status.HTTP_200_OK)
        self.assertEqual(ecriture.status_code, status.HTTP_403_FORBIDDEN)

    def test_la_direction_encaisse(self):
        self.client.force_authenticate(self.comptes[UserRole.DIRECTOR])

        reponse = self.client.post(
            "/api/payments/",
            {"fee": self.frais.id, "amount": "1000.00", "method": "Especes"},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_le_versement_retient_qui_l_a_encaisse(self):
        self.client.force_authenticate(self.comptable)

        reponse = self._payer(self.frais, "5000.00")

        self.assertEqual(
            Payment.objects.get(id=reponse.data["id"]).received_by, self.comptable
        )
