"""Le magasin: des comptes qui suivent leurs mouvements.

`quantity` valait ce qu'un increment avait laisse, et cet increment ne jouait
qu'a la creation d'un mouvement. Trois consequences, toutes verifiees ici:
une sortie de cent sur cinq disponibles affichait -95, supprimer une entree
de cinquante laissait les cinquante au stock, et corriger un mouvement ne
changeait rien du tout.
"""

from io import StringIO

from django.core.management import call_command
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    Etablissement,
    Notification,
    StockItem,
    StockMovement,
    StockMovementType,
    Supplier,
)


class _MagasinMixin:
    @classmethod
    def _decor(cls, nom="Etab Stock"):
        cls.etablissement = Etablissement.objects.create(name=nom)
        cls.direction = User.objects.create_user(
            username=f"dir_{nom.lower().replace(' ', '_')}",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def _article(self, nom="Craie", depart=0, seuil=5):
        article = StockItem.objects.create(
            etablissement=self.etablissement, name=nom, minimum_threshold=seuil
        )
        if depart:
            StockMovement.objects.create(
                item=article,
                movement_type=StockMovementType.IN,
                quantity=depart,
                reason="Stock initial",
            )
        article.refresh_from_db()
        return article

    def _bouger(self, article, genre, quantite, **extra):
        charge = {
            "item": article.id,
            "movement_type": genre,
            "quantity": quantite,
        }
        charge.update(extra)
        return self.client.post(
            "/api/stock-movements/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )


class QuantiteDeriveeTests(_MagasinMixin, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._decor()

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def test_une_entree_augmente_le_stock(self):
        article = self._article(depart=10)

        self._bouger(article, StockMovementType.IN, 5)

        article.refresh_from_db()
        self.assertEqual(article.quantity, 15)

    def test_une_sortie_diminue_le_stock(self):
        article = self._article(depart=10)

        self._bouger(article, StockMovementType.OUT, 4)

        article.refresh_from_db()
        self.assertEqual(article.quantity, 6)

    def test_supprimer_un_mouvement_rend_ses_unites(self):
        """Une entree supprimee laissait ses unites au stock pour toujours."""
        article = self._article(depart=0)
        entree = StockMovement.objects.create(
            item=article, movement_type=StockMovementType.IN, quantity=50
        )
        article.refresh_from_db()
        self.assertEqual(article.quantity, 50)

        entree.delete()

        article.refresh_from_db()
        self.assertEqual(article.quantity, 0)

    def test_corriger_un_mouvement_corrige_le_stock(self):
        """La correction ne changeait rien: seule la creation comptait."""
        article = self._article(depart=0)
        entree = StockMovement.objects.create(
            item=article, movement_type=StockMovementType.IN, quantity=50
        )

        reponse = self.client.patch(
            f"/api/stock-movements/{entree.id}/",
            {"quantity": 20},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        article.refresh_from_db()
        self.assertEqual(article.quantity, 20)

    def test_le_stock_se_recalcule_a_partir_de_rien(self):
        article = self._article(depart=0)
        StockMovement.objects.create(
            item=article, movement_type=StockMovementType.IN, quantity=30
        )
        StockMovement.objects.create(
            item=article, movement_type=StockMovementType.OUT, quantity=12
        )

        # Un compteur fausse a la main est rattrape par le recalcul.
        StockItem.objects.filter(id=article.id).update(quantity=999)
        article.refresh_from_db()
        article.recalculer_quantite()

        self.assertEqual(article.quantity, 18)


class StockNegatifTests(_MagasinMixin, APITestCase):
    """Un stock negatif n'est pas une alerte, c'est une donnee fausse."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Decouvert")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def test_une_sortie_superieure_au_disponible_est_refusee(self):
        article = self._article(depart=5)

        reponse = self._bouger(article, StockMovementType.OUT, 100)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        article.refresh_from_db()
        self.assertEqual(article.quantity, 5)

    def test_le_refus_annonce_ce_qui_reste(self):
        article = self._article(depart=5)

        reponse = self._bouger(article, StockMovementType.OUT, 100)

        self.assertIn("5", str(reponse.data))

    def test_une_sortie_du_dernier_exemplaire_passe(self):
        article = self._article(depart=5)

        reponse = self._bouger(article, StockMovementType.OUT, 5)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        article.refresh_from_db()
        self.assertEqual(article.quantity, 0)

    def test_une_quantite_nulle_ou_negative_est_refusee(self):
        article = self._article(depart=5)

        for quantite in (0, -3):
            with self.subTest(quantite=quantite):
                reponse = self._bouger(article, StockMovementType.IN, quantite)
                self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_corriger_une_sortie_a_la_hausse_reste_borne(self):
        article = self._article(depart=10)
        sortie = self.client.post(
            "/api/stock-movements/",
            {"item": article.id, "movement_type": StockMovementType.OUT, "quantity": 4},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        trop = self.client.patch(
            f"/api/stock-movements/{sortie.data['id']}/",
            {"quantity": 30},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(trop.status_code, status.HTTP_400_BAD_REQUEST)

    def test_corriger_une_sortie_dans_les_limites_passe(self):
        """La sortie corrigee libere d'abord ce qu'elle retenait."""
        article = self._article(depart=10)
        sortie = self.client.post(
            "/api/stock-movements/",
            {"item": article.id, "movement_type": StockMovementType.OUT, "quantity": 4},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        correction = self.client.patch(
            f"/api/stock-movements/{sortie.data['id']}/",
            {"quantity": 9},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(correction.status_code, status.HTTP_200_OK, correction.data)
        article.refresh_from_db()
        self.assertEqual(article.quantity, 1)


class StockInitialTests(_MagasinMixin, APITestCase):
    """Le stock de depart ouvre l'historique au lieu de le contourner."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Ouverture")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def _creer(self, **extra):
        charge = {"name": "Cahier", "unit": "pcs", "minimum_threshold": 5}
        charge.update(extra)
        return self.client.post(
            "/api/stock-items/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_la_quantite_de_depart_devient_un_mouvement(self):
        reponse = self._creer(initial_quantity=40)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        article = StockItem.objects.get(id=reponse.data["id"])
        self.assertEqual(article.quantity, 40)
        mouvement = article.movements.get()
        self.assertEqual(mouvement.movement_type, StockMovementType.IN)
        self.assertEqual(mouvement.reason, "Stock initial")

    def test_un_article_sans_quantite_part_de_zero(self):
        reponse = self._creer()

        self.assertEqual(reponse.data["quantity"], 0)
        self.assertEqual(StockItem.objects.get(id=reponse.data["id"]).movements.count(), 0)

    def test_la_quantite_annoncee_directement_est_ignoree(self):
        """Elle se deduit des mouvements: la poser a la main la ferait mentir."""
        reponse = self._creer(quantity=999)

        self.assertEqual(reponse.data["quantity"], 0)

    def test_modifier_un_article_ne_change_pas_son_stock(self):
        creation = self._creer(initial_quantity=10)

        self.client.patch(
            f"/api/stock-items/{creation.data['id']}/",
            {"name": "Cahier grand format", "initial_quantity": 500},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        article = StockItem.objects.get(id=creation.data["id"])
        self.assertEqual(article.quantity, 10)
        self.assertEqual(article.name, "Cahier grand format")


class SeuilBasTests(_MagasinMixin, APITestCase):
    """Le seuil se franchissait en silence."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Seuil")
        cls.comptable = User.objects.create_user(
            username="cpt_seuil",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def test_la_route_liste_les_articles_sous_seuil(self):
        self._article(nom="Craie", depart=2, seuil=5)
        self._article(nom="Cahier", depart=100, seuil=5)

        reponse = self.client.get(
            "/api/stock-items/low_stock/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.data["count"], 1)
        self.assertEqual(reponse.data["results"][0]["name"], "Craie")

    def test_le_plus_critique_arrive_en_tete(self):
        self._article(nom="Craie", depart=4, seuil=5)
        self._article(nom="Encre", depart=0, seuil=10)

        reponse = self.client.get(
            "/api/stock-items/low_stock/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        noms = [ligne["name"] for ligne in reponse.data["results"]]
        self.assertEqual(noms[0], "Encre")

    def test_l_alerte_recapitule_en_un_message(self):
        self._article(nom="Craie", depart=2, seuil=5)
        self._article(nom="Encre", depart=1, seuil=10)

        sortie = StringIO()
        call_command("signaler_stock_bas", stdout=sortie)

        alertes = Notification.objects.filter(title="Stock bas")
        # La direction et la comptabilite, une notification chacune.
        self.assertEqual(alertes.count(), 2)
        message = alertes.first().message
        self.assertIn("Craie", message)
        self.assertIn("Encre", message)

    def test_un_magasin_fourni_ne_declenche_rien(self):
        self._article(nom="Cahier", depart=100, seuil=5)

        sortie = StringIO()
        call_command("signaler_stock_bas", stdout=sortie)

        self.assertIn("Aucun article", sortie.getvalue())
        self.assertEqual(Notification.objects.count(), 0)

    def test_le_dry_run_ne_notifie_personne(self):
        self._article(nom="Craie", depart=2, seuil=5)

        sortie = StringIO()
        call_command("signaler_stock_bas", "--dry-run", stdout=sortie)

        self.assertIn("dry-run", sortie.getvalue())
        self.assertEqual(Notification.objects.count(), 0)

    def test_une_autre_ecole_n_est_pas_prevenue(self):
        autre = Etablissement.objects.create(name="Ecole voisine stock")
        etranger = User.objects.create_user(
            username="dir_voisin_stock",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=autre,
        )
        self._article(nom="Craie", depart=2, seuil=5)

        call_command("signaler_stock_bas", stdout=StringIO())

        self.assertFalse(Notification.objects.filter(recipient=etranger).exists())
