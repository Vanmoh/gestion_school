"""L'écran Rapports comptait tout, sous un bandeau qui nommait une école.

Sur une capture prise en super-admin, IFP-OBK sélectionné et 2025-2026
active, l'en-tête annonçait « 11 662 reçus délivrables » et « 187 520 000
FCFA encaissés ». Mesuré en base: ce sont les **quatre** établissements
réunis. IFP-OBK seul en compte 4 165, pour 66 965 000 FCFA — le chiffre exact
que le tableau de bord affiche au même instant, dans le même écran.

Deux causes distinctes, et c'est pourquoi les élèves, eux, étaient presque
justes:

1. `_allowed_payments_queryset` rendait `queryset` entier pour un super-admin,
   **avant** de résoudre l'école choisie. Le filtre des élèves, lui, la
   résolvait.
2. Rien dans le module ne lisait `X-Academic-Year-Id`, que le client pose
   pourtant sur chaque requête. D'où « 611 élèves au dossier » là où
   2025-2026 en compte 450: les deux années d'IFP-OBK additionnées.

Et la liste des années de choix servait les cinq années des quatre écoles,
qui s'appellent toutes « 2025-2026 »: on n'y distinguait pas la sienne.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Payment,
    Student,
    StudentFee,
)


class LaPorteeDuModuleRapportsTests(APITestCase):
    """Deux écoles, et deux années dans la première: de quoi tout confondre."""

    @classmethod
    def setUpTestData(cls):
        cls.ici = Etablissement.objects.create(name="Lycee d'ici", code="LICI")
        cls.ailleurs = Etablissement.objects.create(
            name="Lycee d'ailleurs", code="LAIL"
        )

        cls.cette_annee = cls._annee(cls.ici, "2025-2026 ICI", 2025, active=True)
        cls.annee_passee = cls._annee(cls.ici, "2024-2025 ICI", 2024, active=False)
        cls.annee_voisine = cls._annee(
            cls.ailleurs, "2025-2026 AIL", 2025, active=True
        )

        cls.classe_courante = cls._classe(cls.ici, cls.cette_annee, "6eme A")
        cls.classe_passee = cls._classe(cls.ici, cls.annee_passee, "6eme A (n-1)")
        cls.classe_voisine = cls._classe(cls.ailleurs, cls.annee_voisine, "6eme V")

        cls.super_admin = User.objects.create_user(
            username="sa_portee_rapports",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
        )
        cls.comptable = User.objects.create_user(
            username="cpt_portee_rapports",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.ici,
        )

        # Deux élèves cette année, un l'an dernier, un dans l'école voisine.
        cls.awa = cls._eleve(cls.classe_courante, cls.ici, "awa_p", "LICI0001F", "Awa", "Coulibaly")
        cls.moussa = cls._eleve(cls.classe_courante, cls.ici, "mou_p", "LICI0002M", "Moussa", "Diallo")
        cls.ancien = cls._eleve(cls.classe_passee, cls.ici, "anc_p", "LICI0003M", "Ancien", "Keita")
        cls.voisin = cls._eleve(cls.classe_voisine, cls.ailleurs, "voi_p", "LAIL0001M", "Voisin", "Sylla")

        # 3 encaissements cette année ici, 2 l'an dernier ici, 4 à côté.
        for montant in (Decimal("5000"), Decimal("7000"), Decimal("9000")):
            cls._encaissement(cls.awa, cls.cette_annee, montant, cls.ici)
        for montant in (Decimal("1000"), Decimal("2000")):
            cls._encaissement(cls.ancien, cls.annee_passee, montant, cls.ici)
        for montant in (Decimal("100"), Decimal("200"), Decimal("300"), Decimal("400")):
            cls._encaissement(cls.voisin, cls.annee_voisine, montant, cls.ailleurs)

    # --- Le décor -----------------------------------------------------------

    @classmethod
    def _annee(cls, etablissement, nom, debut, *, active):
        return AcademicYear.objects.create(
            name=nom,
            start_date=date(debut, 9, 1),
            end_date=date(debut + 1, 7, 31),
            etablissement=etablissement,
            is_active=active,
        )

    @classmethod
    def _classe(cls, etablissement, annee, nom):
        return ClassRoom.objects.create(
            name=nom, academic_year=annee, etablissement=etablissement
        )

    @classmethod
    def _eleve(cls, classe, etablissement, username, matricule, prenom, nom):
        compte = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=etablissement,
            first_name=prenom,
            last_name=nom,
        )
        return Student.objects.create(
            user=compte,
            matricule=matricule,
            classroom=classe,
            etablissement=etablissement,
        )

    @classmethod
    def _encaissement(cls, eleve, annee, montant, etablissement):
        frais = StudentFee.objects.create(
            student=eleve,
            academic_year=annee,
            fee_type="tuition",
            amount_due=montant,
            due_date=date(annee.start_date.year, 10, 1),
        )
        return Payment.objects.create(
            fee=frais,
            amount=montant,
            method="cash",
            reference=f"REF-{eleve.matricule}-{montant}",
            received_by=cls.comptable,
            etablissement=etablissement,
        )

    def _contexte(self, compte, etablissement=None, annee=None):
        self.client.force_authenticate(compte)
        entetes = {}
        if etablissement is not None:
            entetes["HTTP_X_ETABLISSEMENT_ID"] = str(etablissement.id)
        if annee is not None:
            entetes["HTTP_X_ACADEMIC_YEAR_ID"] = str(annee.id)
        reponse = self.client.get("/api/reports/context/", **entetes)
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data

    # --- L'école ------------------------------------------------------------

    def test_le_super_admin_ne_compte_que_l_ecole_qu_il_a_choisie(self):
        """Le défaut de la capture, dans sa forme la plus simple.

        Neuf encaissements existent en tout; cinq sont d'ici. L'écran en
        annonçait neuf sous un bandeau qui disait « ici ».
        """
        contexte = self._contexte(self.super_admin, etablissement=self.ici)

        self.assertEqual(contexte["payments_count"], 3)
        self.assertEqual(contexte["payments_total"], 21000.0)

    def test_sans_ecole_choisie_le_super_admin_les_voit_toutes(self):
        """La correction ne doit pas lui retirer sa vue d'ensemble."""
        contexte = self._contexte(self.super_admin)

        self.assertEqual(contexte["payments_count"], 9)
        self.assertEqual(contexte["payments_total"], 25000.0)

    def test_un_comptable_ne_voit_pas_l_ecole_voisine(self):
        contexte = self._contexte(self.comptable)

        self.assertEqual(contexte["payments_count"], 3)

    # --- L'année ------------------------------------------------------------

    def test_les_encaissements_sont_ceux_de_l_annee_affichee(self):
        """Cinq encaissements ici, dont trois cette année."""
        contexte = self._contexte(
            self.super_admin, etablissement=self.ici, annee=self.cette_annee
        )

        self.assertEqual(contexte["payments_count"], 3)
        self.assertEqual(contexte["payments_total"], 21000.0)

    def test_une_annee_passee_rend_ses_propres_chiffres(self):
        contexte = self._contexte(
            self.super_admin, etablissement=self.ici, annee=self.annee_passee
        )

        self.assertEqual(contexte["payments_count"], 2)
        self.assertEqual(contexte["payments_total"], 3000.0)

    def test_les_eleves_sont_ceux_de_l_annee_affichee(self):
        """Trois élèves ici en tout, deux inscrits cette année."""
        contexte = self._contexte(
            self.super_admin, etablissement=self.ici, annee=self.cette_annee
        )

        matricules = {e["matricule"] for e in contexte["students"]}
        self.assertEqual(matricules, {"LICI0001F", "LICI0002M"})

    def test_sans_annee_demandee_c_est_l_annee_active_de_l_ecole(self):
        """Le client ne pose pas toujours l'en-tête; le repli doit tenir."""
        contexte = self._contexte(self.super_admin, etablissement=self.ici)

        self.assertEqual(contexte["academic_year_name"], "2025-2026 ICI")
        self.assertEqual(len(contexte["students"]), 2)

    def test_une_annee_d_une_autre_ecole_est_ignoree(self):
        """Un en-tête traîné d'une autre école ne doit pas vider l'écran.

        Sans cette garde, on filtrerait les élèves d'ici sur l'année de
        l'école voisine: zéro ligne, et rien pour le dire.
        """
        contexte = self._contexte(
            self.super_admin, etablissement=self.ici, annee=self.annee_voisine
        )

        self.assertEqual(contexte["academic_year_name"], "2025-2026 ICI")
        self.assertEqual(len(contexte["students"]), 2)

    # --- Ce que l'écran annonce --------------------------------------------

    def test_le_contexte_nomme_la_portee_qu_il_couvre(self):
        contexte = self._contexte(self.super_admin, etablissement=self.ici)

        self.assertEqual(contexte["academic_year_name"], "2025-2026 ICI")
        self.assertEqual(contexte["etablissement_name"], "Lycee d'ici")

    def test_les_annees_proposees_sont_celles_de_cette_ecole(self):
        """Elles s'appellent toutes « 2025-2026 » dans la vraie base."""
        contexte = self._contexte(self.super_admin, etablissement=self.ici)

        noms = {a["name"] for a in contexte["academic_years"]}
        self.assertEqual(noms, {"2025-2026 ICI", "2024-2025 ICI"})

    # --- La liste des reçus -------------------------------------------------

    def test_la_page_des_recus_suit_la_meme_portee(self):
        """Le compteur et la liste doivent compter la même chose.

        « 11 662 encaissements — page 1 sur 584 » annonçait l'un pendant que
        l'autre feuilletait autre chose.
        """
        self.client.force_authenticate(self.super_admin)
        reponse = self.client.get(
            "/api/reports/receipts/",
            HTTP_X_ETABLISSEMENT_ID=str(self.ici.id),
            HTTP_X_ACADEMIC_YEAR_ID=str(self.cette_annee.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["count"], 3)

    def test_le_compteur_et_la_liste_s_accordent(self):
        contexte = self._contexte(self.super_admin, etablissement=self.ici)

        self.client.force_authenticate(self.super_admin)
        page = self.client.get(
            "/api/reports/receipts/", HTTP_X_ETABLISSEMENT_ID=str(self.ici.id)
        )

        self.assertEqual(contexte["payments_count"], page.data["count"])
