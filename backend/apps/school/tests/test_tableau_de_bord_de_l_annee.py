"""Le tableau de bord compte l'annee qu'il nomme, et dit ou en est l'argent.

`/dashboard/` ne consultait aucune annee scolaire. Sur IFP-OBK, qui en a deux
ouvertes, il rendait donc les memes chiffres qu'on demande l'annee active,
aucune annee, ou l'annee suivante: **611 eleves** pour 450 inscrits et
**30 classes** pour 15.

Personne ne l'avait vu, et c'est comprehensible: l'ecran ne nommait aucune
annee. Un chiffre sans periode ne se met pas en doute.

Le recouvrement, lui, manquait entierement -- alors que c'est le chiffre d'une
ecole malienne. A sa place, un « Benefice net » qui etait en realite le montant
encaisse: le calcul ne soustrait que les charges doublement validees, et cette
ecole en avait zero sur 4 124 000 F engages.

Ces tests montent deux annees dans une ecole. Sur une base a une seule annee
aucun d'eux ne verrait quoi que ce soit -- ce qui est exactement pourquoi le
defaut a vecu.
"""

from datetime import date
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
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


class SocleDeDeuxAnnees(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée du tableau de bord", code="LTB"
        )
        cls.cette_annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.annee_suivante = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 7, 31),
            etablissement=cls.etablissement,
            is_active=False,
        )
        cls.classe = cls._classe(cls.cette_annee, "10ème CT", 3)
        cls.classe_suivante = cls._classe(cls.annee_suivante, "11ème CT", 1)

        cls.direction = User.objects.create_user(
            username="ltb.dir",
            password="x",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _classe(cls, annee, nom, nombre_eleves):
        classe = ClassRoom.objects.create(
            name=nom, academic_year=annee, etablissement=cls.etablissement
        )
        for rang in range(nombre_eleves):
            compte = User.objects.create_user(
                username=f"ltb.{annee.name}.{rang}",
                password="x",
                role=UserRole.STUDENT,
                etablissement=cls.etablissement,
            )
            Student.objects.create(
                user=compte,
                matricule=f"LTB{annee.name[:4]}{rang}",
                classroom=classe,
                etablissement=cls.etablissement,
            )
        return classe

    def setUp(self):
        # Le cache survit d'un test a l'autre: sans ce vidage, l'ordre
        # d'execution deciderait du resultat.
        cache.clear()
        self.client = APIClient()
        self.client.force_authenticate(user=self.direction)

    def _bord(self, annee=None, route="/api/dashboard/"):
        entetes = {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}
        if annee is not None:
            entetes["HTTP_X_ACADEMIC_YEAR_ID"] = str(annee.id)
        reponse = self.client.get(route, **entetes)
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data


class LesCompteursSuiventLAnneeTests(SocleDeDeuxAnnees):
    def test_l_effectif_et_les_classes_suivent_l_annee(self):
        """611 pour 450: le comptage faux qu'un directeur lisait a l'accueil."""
        courante = self._bord(self.cette_annee)
        suivante = self._bord(self.annee_suivante)

        self.assertEqual((courante["students"], courante["classrooms"]), (3, 1))
        self.assertEqual((suivante["students"], suivante["classrooms"]), (1, 1))

    def test_l_annee_est_nommee_dans_la_reponse(self):
        """C'est son absence qui a laisse le chiffre faux passer inapercu."""
        rendu = self._bord(self.cette_annee)

        self.assertEqual(rendu["academic_year"]["name"], "2025-2026")
        self.assertEqual(rendu["academic_year"]["id"], self.cette_annee.id)

    def test_sans_en_tete_l_annee_active_s_applique(self):
        """L'ecran n'envoie pas toujours l'annee: le defaut doit etre juste."""
        self.assertEqual(self._bord()["students"], 3)

    def test_l_annee_d_une_autre_ecole_est_ignoree(self):
        """Passer l'identifiant d'une annee voisine n'ouvre pas ses chiffres."""
        voisine = Etablissement.objects.create(name="École voisine", code="EVO")
        chez_la_voisine = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=voisine,
            is_active=True,
        )

        rendu = self._bord(chez_la_voisine)

        # On retombe sur l'annee active de sa propre ecole.
        self.assertEqual(rendu["academic_year"]["id"], self.cette_annee.id)
        self.assertEqual(rendu["students"], 3)

    def test_le_cache_ne_melange_pas_deux_annees(self):
        """Une minute de cache ne doit pas rendre les chiffres de l'autre annee.

        La cle ne portait que l'etablissement et le mois. Lire l'annee active
        puis basculer sur la suivante servait donc la premiere reponse,
        etiquetee de la premiere annee -- pendant soixante secondes, sans que
        rien a l'ecran ne le dise.
        """
        premiere = self._bord(self.cette_annee)
        seconde = self._bord(self.annee_suivante)

        self.assertEqual(premiere["students"], 3)
        self.assertEqual(seconde["students"], 1)
        self.assertEqual(seconde["academic_year"]["name"], "2026-2027")


class LeRecouvrementEstMontreTests(SocleDeDeuxAnnees):
    """Le chiffre d'une ecole malienne, qui manquait entierement."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.eleves = list(
            Student.objects.filter(classroom=cls.classe).order_by("id")
        )
        for rang, eleve in enumerate(cls.eleves):
            frais = StudentFee.objects.create(
                student=eleve,
                academic_year=cls.cette_annee,
                fee_type=FeeType.MONTHLY,
                amount_due=Decimal("10000"),
                due_date=date(2025, 10, 5),
            )
            # Deux eleves soldes, un qui doit encore la moitie.
            Payment.objects.create(
                fee=frais,
                etablissement=cls.etablissement,
                amount=Decimal("10000") if rang < 2 else Decimal("5000"),
                method="especes",
            )

    def test_le_du_le_regle_le_reste_et_le_taux(self):
        rendu = self._bord(self.cette_annee)

        self.assertEqual(Decimal(rendu["fees_due"]), Decimal("30000"))
        self.assertEqual(Decimal(rendu["fees_collected"]), Decimal("25000"))
        self.assertEqual(Decimal(rendu["fees_outstanding"]), Decimal("5000"))
        self.assertEqual(rendu["collection_rate"], 83.3)

    def test_les_eleves_non_soldes_sont_comptes(self):
        """Un nombre qui appelle une action, et non un decompte."""
        self.assertEqual(self._bord(self.cette_annee)["students_unpaid"], 1)

    def test_un_frais_a_plusieurs_versements_n_est_pas_compte_deux_fois(self):
        """Le piege de la jointure, et la raison des deux requetes separees.

        Un seul `annotate(Sum("amount_due"), Sum("payments__amount"))`
        multiplierait `amount_due` par le nombre de paiements de la ligne:
        trois versements sur un frais de 10 000 F feraient 30 000 F de du.
        """
        frais = StudentFee.objects.filter(student=self.eleves[0]).first()
        Payment.objects.filter(fee=frais).delete()
        for _ in range(3):
            Payment.objects.create(
                fee=frais,
                etablissement=self.etablissement,
                amount=Decimal("2000"),
                method="especes",
            )

        rendu = self._bord(self.cette_annee)

        self.assertEqual(Decimal(rendu["fees_due"]), Decimal("30000"))
        self.assertEqual(Decimal(rendu["fees_collected"]), Decimal("21000"))

    def test_l_annee_sans_frais_rend_zero_et_non_le_taux_de_l_autre(self):
        rendu = self._bord(self.annee_suivante)

        self.assertEqual(Decimal(rendu["fees_due"]), Decimal("0"))
        self.assertEqual(rendu["collection_rate"], 0.0)

    def test_les_charges_en_attente_portent_sur_l_annee_entiere(self):
        """Et non sur le seul mois courant.

        Une depense de mars non validee bloque autant qu'une de septembre, et
        c'est le total qui se decide. Sur IFP-OBK: 2 lignes ce mois-ci contre
        36 sur l'annee.
        """
        for jour in (date(2025, 10, 3), date(2026, 3, 12)):
            Expense.objects.create(
                label="Craie et registres",
                amount=Decimal("25000"),
                date=jour,
                category="FOURNITURES",
                etablissement=self.etablissement,
                academic_year=self.cette_annee,
            )

        rendu = self._bord(self.cette_annee)

        self.assertEqual(rendu["year_expenses_pending_count"], 2)
        self.assertEqual(
            Decimal(rendu["year_expenses_pending"]), Decimal("50000")
        )


class LEcheancierTests(SocleDeDeuxAnnees):
    """Une seule courbe, fondee sur l'echeance et non sur l'heure de saisie.

    La courbe precedente s'appuyait sur `created_at` des paiements: `Payment`
    ne porte aucune date de paiement. Un recu ecrit le 30 et saisi le 2 tombait
    dans le mois suivant, et un import en masse faisait tenir une annee entiere
    dans un seul mois -- c'est ce que la base reelle donne a voir, 66 960 000 F
    sur septembre et zero partout ailleurs.
    """

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        eleve = Student.objects.filter(classroom=cls.classe).first()
        # Deux echeances: octobre soldee, novembre a moitie.
        octobre = StudentFee.objects.create(
            student=eleve,
            academic_year=cls.cette_annee,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("10000"),
            due_date=date(2025, 10, 5),
        )
        novembre = StudentFee.objects.create(
            student=eleve,
            academic_year=cls.cette_annee,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("10000"),
            due_date=date(2025, 11, 5),
        )
        Payment.objects.create(
            fee=octobre,
            etablissement=cls.etablissement,
            amount=Decimal("10000"),
            method="especes",
        )
        Payment.objects.create(
            fee=novembre,
            etablissement=cls.etablissement,
            amount=Decimal("4000"),
            method="especes",
        )

    def _serie(self, annee):
        return self._bord(annee, route="/api/dashboard/echeancier/")

    def test_le_mois_vient_de_l_echeance_et_non_de_la_saisie(self):
        """Les deux paiements sont saisis aujourd'hui, les echeances non.

        Une serie basee sur `created_at` mettrait les 14 000 F sur le mois
        courant. Basee sur l'echeance, elle les repartit sur octobre et
        novembre -- ce qui repond a la question posee: « sommes-nous a jour sur
        l'echeancier? »
        """
        mois = {
            ligne["libelle"]: ligne for ligne in self._serie(self.cette_annee)["mois"]
        }

        self.assertEqual(sorted(mois), ["10/2025", "11/2025"])
        self.assertEqual(Decimal(mois["10/2025"]["encaisse"]), Decimal("10000"))
        self.assertEqual(Decimal(mois["11/2025"]["encaisse"]), Decimal("4000"))
        self.assertEqual(Decimal(mois["11/2025"]["manque"]), Decimal("6000"))

    def test_seuls_les_mois_porteurs_d_echeance_sortent(self):
        """Un bareme qui s'arrete en juin n'affiche pas deux colonnes vides.

        Personne ne sait interpreter une colonne a zero: est-ce que rien
        n'etait du, ou que rien n'est rentre?
        """
        self.assertEqual(len(self._serie(self.cette_annee)["mois"]), 2)

    def test_l_annee_suivante_a_sa_propre_serie(self):
        self.assertEqual(self._serie(self.annee_suivante)["mois"], [])

    def test_les_totaux_recoupent_la_serie(self):
        rendu = self._serie(self.cette_annee)

        self.assertEqual(Decimal(rendu["du"]), Decimal("20000"))
        self.assertEqual(Decimal(rendu["encaisse"]), Decimal("14000"))
