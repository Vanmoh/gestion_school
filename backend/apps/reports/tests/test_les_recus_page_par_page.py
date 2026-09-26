"""L'ecran Rapports recevait tous les encaissements de l'ecole.

`ReportsContextView` serialisait la liste entiere a chaque ouverture, et
l'ecran la cherchait puis la paginait **en memoire**, dix lignes a la fois.
Sur une ecole a quinze mille recus, le serveur envoyait plusieurs megaoctets
pour en afficher dix -- et un recu absent de ce que l'ecran avait recu etait
introuvable, la barre de recherche n'y pouvant rien.

Les recus se demandent maintenant a `receipts/`, page par page, et la
recherche part avec.
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


class LesRecusPageParPageTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycee des recus", code="LREC"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 REC",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6eme A",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )

        cls.comptable = User.objects.create_user(
            username="cpt_recus",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
        )
        cls.enseignant = User.objects.create_user(
            username="ens_recus",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
        )

        cls.awa = cls._eleve("awa_recus", "LREC0001M", "Awa", "Traore")
        cls.moussa = cls._eleve("moussa_recus", "LREC0002M", "Moussa", "Diallo")

        # Vingt-cinq encaissements: de quoi deborder une page de vingt.
        for index in range(23):
            cls._encaissement(cls.awa, Decimal("5000"), f"REF-A{index:03d}")
        cls._encaissement(cls.moussa, Decimal("12500"), "REF-UNIQUE")
        cls._encaissement(cls.moussa, Decimal("7000"), "REF-AUTRE")

    @classmethod
    def _eleve(cls, username, matricule, prenom, nom):
        compte = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
            first_name=prenom,
            last_name=nom,
        )
        return Student.objects.create(
            user=compte,
            matricule=matricule,
            classroom=cls.classe,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _encaissement(cls, eleve, montant, reference):
        frais = StudentFee.objects.create(
            student=eleve,
            academic_year=cls.annee,
            fee_type="tuition",
            amount_due=montant,
            due_date=date(2025, 10, 1),
        )
        return Payment.objects.create(
            fee=frais,
            amount=montant,
            method="cash",
            reference=reference,
            received_by=cls.comptable,
            etablissement=cls.etablissement,
        )

    def _recus(self, requete="", compte=None):
        self.client.force_authenticate(compte or self.comptable)
        reponse = self.client.get(f"/api/reports/receipts/{requete}")
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data

    def test_la_premiere_page_ne_rend_que_vingt_lignes(self):
        page = self._recus()

        self.assertEqual(len(page["results"]), 20)
        self.assertEqual(page["count"], 25)
        self.assertEqual(page["pages"], 2)

    def test_la_seconde_page_rend_le_reste(self):
        page = self._recus("?page=2")

        self.assertEqual(len(page["results"]), 5)
        self.assertEqual(page["page"], 2)
        self.assertIsNone(page["next"])

    def test_une_page_au_dela_de_la_derniere_ne_casse_pas(self):
        """Un lien garde en favori, ou un clic de trop sur la fleche."""
        page = self._recus("?page=99")

        self.assertEqual(page["page"], 2)

    def test_la_recherche_par_nom_part_au_serveur(self):
        page = self._recus("?search=Diallo")

        self.assertEqual(page["count"], 2)

    def test_la_recherche_par_matricule(self):
        page = self._recus("?search=LREC0002M")

        self.assertEqual(page["count"], 2)

    def test_la_recherche_par_reference(self):
        page = self._recus("?search=REF-UNIQUE")

        self.assertEqual(page["count"], 1)

    def test_un_montant_se_cherche_aussi(self):
        """C'est ce qu'on a sous les yeux quand un recu arrive sans numero."""
        page = self._recus("?search=12500")

        self.assertEqual(page["count"], 1)
        self.assertEqual(page["results"][0]["reference"], "REF-UNIQUE")

    def test_un_montant_mal_ecrit_ne_fait_pas_tomber_la_requete(self):
        page = self._recus("?search=12 500,00")

        self.assertEqual(page["count"], 1)

    def test_une_recherche_sans_reponse_rend_une_page_vide(self):
        page = self._recus("?search=inexistant")

        self.assertEqual(page["count"], 0)
        self.assertEqual(page["results"], [])

    def test_le_recu_porte_de_quoi_l_identifier(self):
        ligne = self._recus("?search=REF-UNIQUE")["results"][0]

        self.assertEqual(ligne["student_full_name"], "Moussa Diallo")
        self.assertEqual(ligne["student_matricule"], "LREC0002M")
        self.assertEqual(ligne["amount"], 12500.0)

    def test_l_enseignant_n_y_voit_rien(self):
        """Les finances lui sont fermees, meme par la porte des rapports."""
        page = self._recus(compte=self.enseignant)

        self.assertEqual(page["count"], 0)

    def test_le_contexte_ne_serialise_plus_les_encaissements(self):
        """C'etait la cause: tout arrivait pour en afficher dix."""
        self.client.force_authenticate(self.comptable)

        reponse = self.client.get("/api/reports/context/")

        self.assertNotIn("payments", reponse.data)
        self.assertEqual(reponse.data["payments_count"], 25)
        self.assertEqual(reponse.data["payments_total"], 134500.0)
