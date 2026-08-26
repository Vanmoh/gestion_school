"""Le fonds papier: exemplaires, prets, retours et retards.

Trois defauts de fond vivaient dans cet onglet sans qu'aucun test ne les
retienne:

- rien ne permettait de rendre un livre -- `returned_at` n'etait ecrit nulle
  part et un pret durait indefiniment;
- `quantity_available` etait saisi a la main et ne bougeait jamais, si bien
  qu'un ouvrage prete restait annonce disponible;
- l'ISBN etait unique pour toute la plateforme, ce qui empechait la deuxieme
  ecole d'enregistrer le manuel que la premiere possedait deja.
"""

from datetime import timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Book,
    Borrow,
    ClassRoom,
    Etablissement,
    Student,
)


class _FondsPapierMixin:
    """Une ecole, une classe, un eleve et un ouvrage: le decor minimal."""

    @classmethod
    def _annee(cls):
        aujourd_hui = timezone.localdate()
        return AcademicYear.objects.create(
            name="2025-2026",
            start_date=aujourd_hui - timedelta(days=60),
            end_date=aujourd_hui + timedelta(days=240),
            is_active=True,
        )

    @classmethod
    def _ecole(cls, nom, penalite=0):
        return Etablissement.objects.create(
            name=nom, library_penalty_per_day=penalite
        )

    @classmethod
    def _eleve(cls, suffixe, etablissement, classe):
        user = User.objects.create_user(
            username=f"eleve_{suffixe}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=etablissement,
        )
        return Student.objects.create(
            user=user, classroom=classe, etablissement=etablissement
        )

    @classmethod
    def _classe(cls, etablissement, annee):
        return ClassRoom.objects.create(
            name="6eme A", etablissement=etablissement, academic_year=annee
        )

    def _emprunter(self, eleve, livre, jours=7, depuis=0):
        emprunt = timezone.localdate() - timedelta(days=depuis)
        return self.client.post(
            "/api/borrows/",
            {
                "student": eleve.id,
                "book": livre.id,
                "borrowed_at": emprunt.isoformat(),
                "due_date": (emprunt + timedelta(days=jours)).isoformat(),
            },
            format="json",
        )


class BookCatalogueTests(_FondsPapierMixin, APITestCase):
    """Le catalogue: ISBN, disponibilite derivee, recherche."""

    @classmethod
    def setUpTestData(cls):
        cls.annee = cls._annee()
        cls.ecole = cls._ecole("LTOB")
        cls.voisine = cls._ecole("Lycee Askia")
        cls.directeur = User.objects.create_user(
            username="dir_ltob",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.ecole,
        )
        cls.directeur_voisin = User.objects.create_user(
            username="dir_askia",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.voisine,
        )

    def _creer_livre(
        self,
        titre="Algebre 1",
        isbn="978-2-1234-5680-3",
        total=3,
        auteur="A. Diallo",
    ):
        return self.client.post(
            "/api/books/",
            {
                "title": titre,
                "author": auteur,
                "isbn": isbn,
                "quantity_total": total,
            },
            format="json",
        )

    def test_un_ouvrage_cree_est_entierement_en_rayon(self):
        self.client.force_authenticate(self.directeur)

        reponse = self._creer_livre(total=4)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(reponse.data["quantity_available"], 4)
        self.assertEqual(reponse.data["quantity_borrowed"], 0)

    def test_la_disponibilite_annoncee_par_le_client_est_ignoree(self):
        """Elle est derivee: la saisir a la main est ce qui la faisait mentir."""
        self.client.force_authenticate(self.directeur)

        reponse = self.client.post(
            "/api/books/",
            {
                "title": "Geometrie",
                "author": "M. Keita",
                "isbn": "978-2-1234-5681-0",
                "quantity_total": 2,
                "quantity_available": 99,
            },
            format="json",
        )

        self.assertEqual(reponse.data["quantity_available"], 2)

    def test_deux_ecoles_possedent_le_meme_isbn(self):
        """La contrainte etait globale: la seconde ecole ne pouvait pas saisir."""
        self.client.force_authenticate(self.directeur)
        premier = self._creer_livre()
        self.assertEqual(premier.status_code, status.HTTP_201_CREATED)

        self.client.force_authenticate(self.directeur_voisin)
        second = self._creer_livre()

        self.assertEqual(second.status_code, status.HTTP_201_CREATED, second.data)

    def test_le_meme_isbn_deux_fois_dans_la_meme_ecole_est_refuse(self):
        self.client.force_authenticate(self.directeur)
        self._creer_livre()

        doublon = self._creer_livre(titre="Algebre 1 (2e ed.)")

        self.assertEqual(doublon.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("isbn", doublon.data)

    def test_le_catalogue_se_cherche_par_titre_auteur_et_isbn(self):
        self.client.force_authenticate(self.directeur)
        self._creer_livre(titre="Algebre 1", isbn="978-2-1234-5680-3")
        self._creer_livre(
            titre="Histoire du Mali", isbn="978-2-1234-5682-7", auteur="F. Sissoko"
        )

        for terme, attendu in (
            ("algebre", "Algebre 1"),
            ("diallo", "Algebre 1"),
            ("5682", "Histoire du Mali"),
        ):
            with self.subTest(terme=terme):
                reponse = self.client.get("/api/books/", {"search": terme})
                titres = [ligne["title"] for ligne in reponse.data["results"]]
                self.assertIn(attendu, titres)
                self.assertEqual(len(titres), 1, titres)

    def test_les_complements_de_fiche_sont_enregistres_et_cherchables(self):
        """Matiere, editeur, annee et cote: facultatifs, mais retrouvables."""
        self.client.force_authenticate(self.directeur)

        creation = self.client.post(
            "/api/books/",
            {
                "title": "Mecanique",
                "author": "S. Coulibaly",
                "isbn": "978-2-1234-5684-1",
                "quantity_total": 2,
                "subject": "Physique",
                "publisher": "Donniya",
                "published_year": 2019,
                "shelf_location": "B3",
            },
            format="json",
        )
        self.assertEqual(creation.status_code, status.HTTP_201_CREATED, creation.data)

        for terme in ("Physique", "Donniya", "B3"):
            with self.subTest(terme=terme):
                trouves = self.client.get("/api/books/", {"search": terme}).data
                self.assertEqual(
                    [ligne["title"] for ligne in trouves["results"]], ["Mecanique"]
                )

    def test_une_fiche_sans_complements_reste_acceptee(self):
        """L'existant n'en porte aucun: les exiger bloquerait toute correction."""
        self.client.force_authenticate(self.directeur)

        reponse = self._creer_livre()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        self.assertEqual(reponse.data["publisher"], "")
        self.assertIsNone(reponse.data["published_year"])

    def test_le_filtre_de_disponibilite_separe_le_rayon_du_sorti(self):
        self.client.force_authenticate(self.directeur)
        classe = self._classe(self.ecole, self.annee)
        eleve = self._eleve("dispo", self.ecole, classe)
        unique = self._creer_livre(titre="Exemplaire unique", total=1)
        self._creer_livre(titre="Bien fourni", isbn="978-2-1234-5683-4", total=5)
        self._emprunter(eleve, Book.objects.get(id=unique.data["id"]))

        sortis = self.client.get("/api/books/", {"availability": "out"})
        rayon = self.client.get("/api/books/", {"availability": "available"})

        self.assertEqual(
            [ligne["title"] for ligne in sortis.data["results"]], ["Exemplaire unique"]
        )
        self.assertEqual(
            [ligne["title"] for ligne in rayon.data["results"]], ["Bien fourni"]
        )

    def test_le_total_ne_descend_pas_sous_les_exemplaires_sortis(self):
        self.client.force_authenticate(self.directeur)
        classe = self._classe(self.ecole, self.annee)
        eleve = self._eleve("total", self.ecole, classe)
        livre = Book.objects.get(id=self._creer_livre(total=2).data["id"])
        self._emprunter(eleve, livre)

        reponse = self.client.patch(
            f"/api/books/{livre.id}/", {"quantity_total": 0}, format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("quantity_total", reponse.data)

    def test_augmenter_le_fonds_remet_les_exemplaires_en_rayon(self):
        self.client.force_authenticate(self.directeur)
        classe = self._classe(self.ecole, self.annee)
        eleve = self._eleve("hausse", self.ecole, classe)
        livre = Book.objects.get(id=self._creer_livre(total=1).data["id"])
        self._emprunter(eleve, livre)

        reponse = self.client.patch(
            f"/api/books/{livre.id}/", {"quantity_total": 4}, format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        # Quatre au fonds, un chez un eleve.
        self.assertEqual(reponse.data["quantity_available"], 3)


class BorrowLifecycleTests(_FondsPapierMixin, APITestCase):
    """Le pret, le retour et ce qu'ils font au compteur d'exemplaires."""

    @classmethod
    def setUpTestData(cls):
        cls.annee = cls._annee()
        cls.ecole = cls._ecole("LTOB", penalite=Decimal("250.00"))
        cls.classe = cls._classe(cls.ecole, cls.annee)
        cls.eleve = cls._eleve("emprunt", cls.ecole, cls.classe)
        cls.autre_eleve = cls._eleve("second", cls.ecole, cls.classe)
        cls.directeur = User.objects.create_user(
            username="dir_prets",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.ecole,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.directeur)
        self.livre = Book.objects.create(
            title="Algebre 1",
            author="A. Diallo",
            isbn="978-2-1234-5680-3",
            quantity_total=1,
            quantity_available=1,
            etablissement=self.ecole,
        )

    def _rendre(self, emprunt_id, **charge):
        return self.client.post(
            f"/api/borrows/{emprunt_id}/return/", charge, format="json"
        )

    def test_un_pret_sort_l_exemplaire_du_rayon(self):
        reponse = self._emprunter(self.eleve, self.livre)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.livre.refresh_from_db()
        self.assertEqual(self.livre.quantity_available, 0)

    def test_le_dernier_exemplaire_ne_se_prete_pas_deux_fois(self):
        self._emprunter(self.eleve, self.livre)

        second = self._emprunter(self.autre_eleve, self.livre)

        self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("exemplaire", str(second.data["book"]).lower())

    def test_un_ouvrage_sans_exemplaire_ne_se_prete_pas(self):
        self.livre.quantity_total = 0
        self.livre.save(update_fields=["quantity_total"])

        reponse = self._emprunter(self.eleve, self.livre)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_le_retour_remet_l_exemplaire_en_rayon(self):
        emprunt = self._emprunter(self.eleve, self.livre)

        reponse = self._rendre(emprunt.data["id"])

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertTrue(reponse.data["is_returned"])
        self.assertEqual(reponse.data["returned_at"], timezone.localdate().isoformat())
        self.livre.refresh_from_db()
        self.assertEqual(self.livre.quantity_available, 1)

    def test_un_exemplaire_rendu_se_reprete(self):
        emprunt = self._emprunter(self.eleve, self.livre)
        self._rendre(emprunt.data["id"])

        second = self._emprunter(self.autre_eleve, self.livre)

        self.assertEqual(second.status_code, status.HTTP_201_CREATED, second.data)

    def test_un_emprunt_deja_rendu_ne_se_rend_pas_deux_fois(self):
        emprunt = self._emprunter(self.eleve, self.livre)
        self._rendre(emprunt.data["id"])

        rejoue = self._rendre(emprunt.data["id"])

        self.assertEqual(rejoue.status_code, status.HTTP_400_BAD_REQUEST)
        # Le compteur ne remonte pas au-dela du fonds a chaque rappel.
        self.livre.refresh_from_db()
        self.assertEqual(self.livre.quantity_available, 1)

    def test_le_retour_accepte_une_date_anterieure(self):
        """Un livre rendu vendredi, saisi lundi: c'est vendredi qui compte."""
        emprunt = self._emprunter(self.eleve, self.livre, depuis=10)
        vendredi = (timezone.localdate() - timedelta(days=3)).isoformat()

        reponse = self._rendre(emprunt.data["id"], returned_at=vendredi)

        self.assertEqual(reponse.data["returned_at"], vendredi)

    def test_un_retour_avant_l_emprunt_est_refuse(self):
        emprunt = self._emprunter(self.eleve, self.livre)
        avant = (timezone.localdate() - timedelta(days=5)).isoformat()

        reponse = self._rendre(emprunt.data["id"], returned_at=avant)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_echeance_anterieure_a_l_emprunt_est_refusee(self):
        aujourd_hui = timezone.localdate()
        reponse = self.client.post(
            "/api/borrows/",
            {
                "student": self.eleve.id,
                "book": self.livre.id,
                "borrowed_at": aujourd_hui.isoformat(),
                "due_date": (aujourd_hui - timedelta(days=1)).isoformat(),
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_supprimer_un_emprunt_remet_l_exemplaire_en_rayon(self):
        emprunt = self._emprunter(self.eleve, self.livre)

        self.client.delete(f"/api/borrows/{emprunt.data['id']}/")

        self.livre.refresh_from_db()
        self.assertEqual(self.livre.quantity_available, 1)


class BorrowPenaltyTests(_FondsPapierMixin, APITestCase):
    """La penalite: calculee au retour, au tarif de l'ecole."""

    @classmethod
    def setUpTestData(cls):
        cls.annee = cls._annee()
        cls.ecole = cls._ecole("LTOB", penalite=Decimal("250.00"))
        cls.gratuite = cls._ecole("Ecole sans penalite")
        cls.classe = cls._classe(cls.ecole, cls.annee)
        cls.eleve = cls._eleve("retard", cls.ecole, cls.classe)
        cls.directeur = User.objects.create_user(
            username="dir_penalites",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.ecole,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.directeur)
        self.livre = Book.objects.create(
            title="Algebre 1",
            author="A. Diallo",
            isbn="978-2-1234-5690-2",
            quantity_total=2,
            quantity_available=2,
            etablissement=self.ecole,
        )

    def test_un_retour_dans_les_temps_ne_coute_rien(self):
        emprunt = self._emprunter(self.eleve, self.livre, jours=7)

        reponse = self.client.post(
            f"/api/borrows/{emprunt.data['id']}/return/", {}, format="json"
        )

        self.assertEqual(Decimal(reponse.data["penalty_amount"]), Decimal("0.00"))
        self.assertEqual(reponse.data["days_late"], 0)

    def test_trois_jours_de_retard_coutent_trois_fois_le_tarif(self):
        # Emprunte il y a dix jours pour sept: trois jours de retard.
        emprunt = self._emprunter(self.eleve, self.livre, jours=7, depuis=10)

        reponse = self.client.post(
            f"/api/borrows/{emprunt.data['id']}/return/", {}, format="json"
        )

        self.assertEqual(reponse.data["days_late"], 3)
        self.assertEqual(Decimal(reponse.data["penalty_amount"]), Decimal("750.00"))

    def test_un_montant_impose_prime_sur_le_calcul(self):
        """Le geste commercial reste possible: c'est une decision d'ecole."""
        emprunt = self._emprunter(self.eleve, self.livre, jours=7, depuis=10)

        reponse = self.client.post(
            f"/api/borrows/{emprunt.data['id']}/return/",
            {"penalty_amount": "100"},
            format="json",
        )

        self.assertEqual(Decimal(reponse.data["penalty_amount"]), Decimal("100.00"))

    def test_une_ecole_sans_tarif_ne_facture_aucun_retard(self):
        classe = self._classe(self.gratuite, self.annee)
        eleve = self._eleve("gratuit", self.gratuite, classe)
        livre = Book.objects.create(
            title="Lecture libre",
            author="X",
            isbn="978-2-1234-5691-9",
            quantity_total=1,
            quantity_available=1,
            etablissement=self.gratuite,
        )
        directeur = User.objects.create_user(
            username="dir_gratuit",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.gratuite,
        )
        self.client.force_authenticate(directeur)
        emprunt = self._emprunter(eleve, livre, jours=1, depuis=30)

        reponse = self.client.post(
            f"/api/borrows/{emprunt.data['id']}/return/", {}, format="json"
        )

        self.assertEqual(reponse.data["days_late"], 29)
        self.assertEqual(Decimal(reponse.data["penalty_amount"]), Decimal("0.00"))

    def test_un_emprunt_en_cours_annonce_la_dette_qui_court(self):
        """`penalty_due` grandit tant que le livre n'est pas revenu."""
        self._emprunter(self.eleve, self.livre, jours=7, depuis=9)

        ligne = self.client.get("/api/borrows/", {"status": "late"}).data["results"][0]

        self.assertEqual(ligne["days_late"], 2)
        self.assertEqual(Decimal(ligne["penalty_due"]), Decimal("500.00"))
        # Rien n'est encore facture: le livre peut revenir aujourd'hui.
        self.assertEqual(Decimal(ligne["penalty_amount"]), Decimal("0.00"))

    def test_les_etats_filtrent_les_prets(self):
        en_cours = self._emprunter(self.eleve, self.livre, jours=7)
        rendu = self._emprunter(self.eleve, self.livre, jours=7, depuis=2)
        self.client.post(
            f"/api/borrows/{rendu.data['id']}/return/", {}, format="json"
        )

        for etat, attendus in (
            ("ongoing", {en_cours.data["id"]}),
            ("returned", {rendu.data["id"]}),
            ("late", set()),
        ):
            with self.subTest(etat=etat):
                lignes = self.client.get("/api/borrows/", {"status": etat}).data["results"]
                self.assertEqual({ligne["id"] for ligne in lignes}, attendus)


class BorrowAccessTests(_FondsPapierMixin, APITestCase):
    """Qui prete, qui rend, qui ne voit que ses propres emprunts."""

    @classmethod
    def setUpTestData(cls):
        cls.annee = cls._annee()
        cls.ecole = cls._ecole("LTOB")
        cls.classe = cls._classe(cls.ecole, cls.annee)
        cls.eleve = cls._eleve("lecteur", cls.ecole, cls.classe)
        cls.camarade = cls._eleve("camarade", cls.ecole, cls.classe)
        cls.directeur = User.objects.create_user(
            username="dir_acces",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.ecole,
        )
        cls.livre = Book.objects.create(
            title="Algebre 1",
            author="A. Diallo",
            isbn="978-2-1234-5692-6",
            quantity_total=5,
            quantity_available=5,
            etablissement=cls.ecole,
        )
        aujourd_hui = timezone.localdate()
        cls.pret_eleve = Borrow.objects.create(
            student=cls.eleve,
            book=cls.livre,
            borrowed_at=aujourd_hui,
            due_date=aujourd_hui + timedelta(days=7),
        )
        Borrow.objects.create(
            student=cls.camarade,
            book=cls.livre,
            borrowed_at=aujourd_hui,
            due_date=aujourd_hui + timedelta(days=7),
        )

    def test_l_eleve_ne_voit_que_ses_propres_emprunts(self):
        self.client.force_authenticate(self.eleve.user)

        lignes = self.client.get("/api/borrows/").data["results"]

        self.assertEqual({ligne["id"] for ligne in lignes}, {self.pret_eleve.id})

    def test_l_eleve_ne_rend_pas_le_livre_lui_meme(self):
        self.client.force_authenticate(self.eleve.user)

        reponse = self.client.post(
            f"/api/borrows/{self.pret_eleve.id}/return/", {}, format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_la_ligne_porte_le_titre_et_l_eleve(self):
        """L'ecran croisait deux listes a la main pour les afficher."""
        self.client.force_authenticate(self.directeur)

        ligne = self.client.get(f"/api/borrows/{self.pret_eleve.id}/").data

        self.assertEqual(ligne["book_title"], "Algebre 1")
        self.assertEqual(ligne["student_matricule"], self.eleve.matricule)
