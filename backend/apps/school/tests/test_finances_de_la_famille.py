"""Ce qu'une famille lit du module Finances, et ce qu'elle n'en lit pas.

La matrice ouvre « finance » au parent et a l'eleve en `L*`: **ses** frais,
**ses** paiements. La meme cle ouvrait pourtant deux choses qui ne les
regardent pas.

- **Les depenses de l'ecole.** Un eleve recevait « Reparation du groupe
  electrogene -- 180 000 » et le reste de la comptabilite. L'ecran masquait
  l'onglet, ce qui est precisement ce qui rendait l'ecart durable: rien ne se
  voyait, la donnee partait quand meme.
- **Les baremes de toutes les classes.** Dix lignes pour cinq classes, quand
  l'enfant n'en suit qu'une. Ce que paie la classe voisine ne le regarde pas.

Ce qui marchait deja et qu'il ne faut pas casser est teste aussi: les totaux de
`/payments/totaux/` etaient, eux, correctement restreints -- un eleve y lisait
ses 160 000 FCFA et non les 22 millions encaisses par l'ecole.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Expense,
    FeeSchedule,
    FeeType,
    ParentProfile,
    Payment,
    Student,
    StudentFee,
)


class SocleDeDeuxClasses(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des finances", code="LFIN"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.sienne = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        cls.voisine = ClassRoom.objects.create(
            name="11ème CG",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )

        cls.bareme_sien = cls._bareme(cls.sienne, 25000)
        cls.bareme_voisin = cls._bareme(cls.voisine, 30000)

        cls.parent = cls._parent()
        cls.eleve = cls._eleve("ali", cls.sienne)
        cls.voisin = cls._eleve("sekou", cls.voisine, parent=None)

        # Ce que l'ecole depense: quatre lignes qui ne regardent personne dehors.
        for rang, (libelle, montant) in enumerate(
            (
                ("Réparation du groupe électrogène", 180000),
                ("Carburant du mois", 95000),
            )
        ):
            Expense.objects.create(
                label=libelle,
                amount=Decimal(montant),
                date=date(2026, 1, 10) + timedelta(days=rang),
                academic_year=cls.annee,
                etablissement=cls.etablissement,
            )

        cls._frais(cls.eleve, 25000, regle=15000)
        cls._frais(cls.voisin, 30000, regle=30000)

    @classmethod
    def _bareme(cls, classe, montant):
        return FeeSchedule.objects.create(
            etablissement=cls.etablissement,
            academic_year=cls.annee,
            classroom=classe,
            fee_type=FeeType.REGISTRATION,
            label="Inscription",
            amount=Decimal(montant),
            first_due_date=date(2025, 9, 15),
            occurrences=1,
        )

    @classmethod
    def _parent(cls):
        compte = User.objects.create_user(
            username="lfin.parent",
            password="x",
            role=UserRole.PARENT,
            first_name="Papa",
            last_name="DIALLO",
            etablissement=cls.etablissement,
        )
        return ParentProfile.objects.create(
            user=compte, etablissement=cls.etablissement
        )

    @classmethod
    def _eleve(cls, prenom, classe, parent="defaut"):
        compte = User.objects.create_user(
            username=f"lfin.{prenom}",
            password="x",
            role=UserRole.STUDENT,
            first_name=prenom.capitalize(),
            last_name="DIALLO",
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=compte,
            matricule=f"LFIN{prenom[:3].upper()}",
            classroom=classe,
            parent=cls.parent if parent == "defaut" else parent,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _frais(cls, eleve, du, regle):
        frais = StudentFee.objects.create(
            student=eleve,
            academic_year=cls.annee,
            fee_type=FeeType.REGISTRATION,
            amount_due=Decimal(du),
            due_date=date(2025, 9, 15),
        )
        if regle:
            Payment.objects.create(
                fee=frais,
                amount=Decimal(regle),
                method="cash",
                etablissement=cls.etablissement,
            )
        return frais

    def _lire(self, compte, route):
        client = APIClient()
        client.force_authenticate(user=compte)
        reponse = client.get(
            route, HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        donnees = reponse.data
        if isinstance(donnees, dict) and "results" in donnees:
            return donnees["results"]
        return donnees


class LesDepensesDeLEcoleNeSortentPasTests(SocleDeDeuxClasses):
    def test_l_eleve_ne_voit_aucune_depense(self):
        self.assertEqual(self._lire(self.eleve.user, "/api/expenses/"), [])

    def test_le_parent_ne_voit_aucune_depense(self):
        self.assertEqual(self._lire(self.parent.user, "/api/expenses/"), [])

    def test_le_comptable_les_voit_toutes(self):
        """La fermeture ne devait pas deborder sur qui tient la caisse."""
        comptable = User.objects.create_user(
            username="lfin.cpt",
            password="x",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )

        self.assertEqual(len(self._lire(comptable, "/api/expenses/")), 2)


class LeBaremeDeSaClasseSeulementTests(SocleDeDeuxClasses):
    def test_l_eleve_ne_voit_que_le_bareme_de_sa_classe(self):
        baremes = self._lire(self.eleve.user, "/api/fee-schedules/")

        self.assertEqual([b["id"] for b in baremes], [self.bareme_sien.id])

    def test_le_parent_ne_voit_que_celui_de_son_enfant(self):
        baremes = self._lire(self.parent.user, "/api/fee-schedules/")

        self.assertEqual([b["id"] for b in baremes], [self.bareme_sien.id])

    def test_le_comptable_voit_les_deux(self):
        comptable = User.objects.create_user(
            username="lfin.cpt2",
            password="x",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )

        self.assertEqual(len(self._lire(comptable, "/api/fee-schedules/")), 2)


class CeQuiMarchaitDejaTests(SocleDeDeuxClasses):
    """Les garde-fous du travail deja fait: on ne repare pas en cassant."""

    def test_l_eleve_lit_ses_frais_et_pas_ceux_du_voisin(self):
        """Sur les identifiants, et non sur le compte.

        Un `post_save` facture l'eleve des son inscription: le decor en produit
        donc plus qu'il n'en cree a la main, et compter les lignes ferait
        echouer ce test au premier bareme ajoute. Ce qui compte est a qui elles
        appartiennent.
        """
        frais = self._lire(self.eleve.user, "/api/fees/")

        self.assertTrue(frais)
        self.assertEqual({f["student"] for f in frais}, {self.eleve.id})

    def test_le_parent_lit_les_frais_de_son_enfant(self):
        frais = self._lire(self.parent.user, "/api/fees/")

        self.assertEqual({f["student"] for f in frais}, {self.eleve.id})

    def test_les_totaux_sont_les_siens_et_non_ceux_de_l_ecole(self):
        """Un eleve y lisait ses 160 000 FCFA, pas les 22 millions de l'ecole."""
        client = APIClient()
        client.force_authenticate(user=self.eleve.user)

        reponse = client.get(
            "/api/payments/totaux/",
            # « tout » et non « annee »: la vue rend `False` sur une periode
            # inconnue, pour qu'une faute de frappe ne passe pas pour une
            # demande de tout l'historique.
            {"periode": "tout"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertEqual(Decimal(reponse.data["recettes"]), Decimal(15000))
