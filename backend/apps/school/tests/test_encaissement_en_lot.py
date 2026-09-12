"""Un seul versement qui regle plusieurs frais.

L'ecran proposait l'encaissement en lot depuis longtemps, mais en creant les
paiements un par un depuis le client. Hors especes -- quatre methodes sur six
-- le lot etait refuse des le deuxieme frais: sa reference, celle du transfert
qui reglait l'ensemble, etait tenue pour un doublon. Et quand un refus tombait
au milieu, les paiements deja passes restaient sans que rien ne dise lesquels.
"""

from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from datetime import date

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ParentProfile,
    Payment,
)
from apps.school.tests.test_finance_payments import _FinanceMixin


class ReferencePartageeTests(_FinanceMixin, APITestCase):
    """La reference designe une transaction, pas un frais."""

    @classmethod
    def setUpTestData(cls):
        cls._decor("Etab Reference")
        cls.eleve = cls._eleve("eleve_reference")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)

    def test_un_virement_unique_regle_trois_echeances(self):
        # Le cas ordinaire: un parent paie trois mensualites d'un seul envoi
        # Mobile Money. Les trois portent le numero de ce transfert.
        premier = self._frais(self.eleve, "25000.00")
        deuxieme = self._frais(self.eleve, "25000.00")
        troisieme = self._frais(self.eleve, "25000.00")

        for frais in (premier, deuxieme, troisieme):
            reponse = self._payer(
                frais, "25000.00", "Mobile Money", reference="MM7788"
            )
            self.assertEqual(
                reponse.status_code, status.HTTP_201_CREATED, reponse.data
            )

        self.assertEqual(Payment.objects.filter(reference="MM7788").count(), 3)

    def test_une_fratrie_partage_le_versement_du_foyer(self):
        # Un parent, deux enfants, un seul transfert: le foyer est l'unite,
        # pas l'eleve.
        compte = User.objects.create_user(
            username="parent_fratrie",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        foyer = ParentProfile.objects.create(user=compte)
        aine = self._eleve("eleve_aine")
        cadet = self._eleve("eleve_cadet")
        for enfant in (aine, cadet):
            enfant.parent = foyer
            enfant.save(update_fields=["parent"])

        premier = self._payer(
            self._frais(aine, "30000.00"), "30000.00", "Virement", reference="VIR2026"
        )
        second = self._payer(
            self._frais(cadet, "30000.00"), "30000.00", "Virement", reference="VIR2026"
        )

        self.assertEqual(premier.status_code, status.HTTP_201_CREATED, premier.data)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED, second.data)

    def test_le_meme_versement_ne_se_saisit_pas_deux_fois_sur_un_frais(self):
        # La garde d'origine, qu'il ne fallait pas perdre: deux references
        # identiques sur un meme frais, c'est la meme somme saisie deux fois.
        # Le garde-fou des trois minutes ne l'attrape pas si les montants
        # different.
        frais = self._frais(self.eleve, "50000.00")

        premier = self._payer(frais, "30000.00", "Mobile Money", reference="MM9001")
        second = self._payer(frais, "10000.00", "Mobile Money", reference="MM9001")

        self.assertEqual(premier.status_code, status.HTTP_201_CREATED, premier.data)
        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("reference", second.data)

    def test_deux_familles_ne_partagent_pas_une_reference(self):
        # La garde qu'on veut conserver: la meme reference sur deux foyers
        # differents est une erreur de saisie, pas un versement groupe.
        autre = self._eleve("eleve_etranger")

        premier = self._payer(
            self._frais(self.eleve, "10000.00"), "10000.00", "Cheque", reference="CHQ01"
        )
        second = self._payer(
            self._frais(autre, "10000.00"), "10000.00", "Cheque", reference="CHQ01"
        )

        self.assertEqual(premier.status_code, status.HTTP_201_CREATED, premier.data)
        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("famille", str(second.data).lower())


class EncaissementEnLotTests(_FinanceMixin, APITestCase):
    """Tout part ensemble, ou rien ne part."""

    @classmethod
    def setUpTestData(cls):
        cls._decor("Etab Lot")
        cls.eleve = cls._eleve("eleve_lot")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)
        self.premier = self._frais(self.eleve, "20000.00")
        self.deuxieme = self._frais(self.eleve, "30000.00")

    def _encaisser(self, **charge):
        return self.client.post(
            "/api/payments/encaisser-en-lot/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_le_lot_solde_chaque_frais_par_defaut(self):
        reponse = self._encaisser(
            frais=[self.premier.id, self.deuxieme.id],
            method="Mobile Money",
            reference="MM4242",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(reponse.data["crees"], 2)
        self.assertEqual(Decimal(reponse.data["total"]), Decimal("50000.00"))
        self.premier.refresh_from_db()
        self.deuxieme.refresh_from_db()
        self.assertEqual(self.premier.balance, Decimal("0.00"))
        self.assertEqual(self.deuxieme.balance, Decimal("0.00"))

    def test_un_montant_impose_ne_depasse_jamais_le_solde(self):
        # 25 000 par frais sur un frais qui n'en doit que 20 000: le
        # versement est ramene au solde, il ne cree pas un trop-percu.
        reponse = self._encaisser(
            frais=[self.premier.id, self.deuxieme.id],
            method="Especes",
            montant_par_frais="25000",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(Decimal(reponse.data["total"]), Decimal("45000.00"))
        self.premier.refresh_from_db()
        self.assertEqual(self.premier.balance, Decimal("0.00"))

    def test_un_refus_ne_laisse_aucun_paiement_derriere_lui(self):
        # C'est la raison d'etre de la route: le client creait les paiements
        # un par un et un refus au milieu laissait les precedents en base.
        reponse = self._encaisser(
            frais=[self.premier.id, self.deuxieme.id],
            method="Mobile Money",
            reference="",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Payment.objects.count(), 0)

    def test_un_frais_d_une_autre_ecole_fait_echouer_le_lot(self):
        voisine = Etablissement.objects.create(name="Ecole voisine lot", code="EVL")
        annee_voisine = AcademicYear.objects.create(
            name="2025-2026 voisine lot",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=voisine,
        )
        classe_voisine = ClassRoom.objects.create(
            name="6eme A", academic_year=annee_voisine, etablissement=voisine
        )
        etrangere = self._eleve(
            "eleve_ailleurs", etablissement=voisine, classe=classe_voisine
        )
        intrus = self._frais(etrangere, "10000.00", annee=annee_voisine)

        reponse = self._encaisser(
            frais=[self.premier.id, intrus.id], method="Especes"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Payment.objects.count(), 0)

    def test_un_frais_cite_deux_fois_n_est_encaisse_qu_une_fois(self):
        reponse = self._encaisser(
            frais=[self.premier.id, self.premier.id], method="Especes"
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(reponse.data["crees"], 1)
        self.assertEqual(Decimal(reponse.data["total"]), Decimal("20000.00"))

    def test_un_frais_deja_solde_est_ignore_sans_faire_echouer(self):
        self._payer(self.premier, "20000.00")

        reponse = self._encaisser(
            frais=[self.premier.id, self.deuxieme.id], method="Especes"
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(reponse.data["crees"], 1)
        self.assertEqual(Decimal(reponse.data["total"]), Decimal("30000.00"))

    def test_un_lot_sans_rien_a_encaisser_est_refuse(self):
        self._payer(self.premier, "20000.00")
        self._payer(self.deuxieme, "30000.00")

        reponse = self._encaisser(
            frais=[self.premier.id, self.deuxieme.id], method="Especes"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_liste_vide_est_refusee(self):
        self.assertEqual(
            self._encaisser(frais=[], method="Especes").status_code,
            status.HTTP_400_BAD_REQUEST,
        )

    def test_un_montant_impose_negatif_est_refuse(self):
        reponse = self._encaisser(
            frais=[self.premier.id], method="Especes", montant_par_frais="-500"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Payment.objects.count(), 0)

    def test_l_enseignant_ne_peut_pas_encaisser(self):
        enseignant = User.objects.create_user(
            username="ens_lot",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(enseignant)

        reponse = self._encaisser(frais=[self.premier.id], method="Especes")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(Payment.objects.count(), 0)
