"""L'identite de l'ecole, reglee depuis l'application au lieu du code.

Le nom, le logo, le telephone et jusqu'aux libelles des ecrans publics
vivaient en dur dans le client: servir une autre ecole demandait de
recompiler avec ses constantes. Ce qui se verifie ici est double -- que la
lecture reste ouverte, parce que les ecrans qui en dependent s'affichent
avant toute connexion, et que l'ecriture n'appartient qu'au super admin.
"""

from django.test import TestCase
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.common.models import PersonnalisationPlateforme

URL = "/api/common/personnalisation/"


class PersonnalisationTests(TestCase):
    def setUp(self):
        self.super_admin = User.objects.create_user(
            username="sa", password="Pass1234!", role=UserRole.SUPER_ADMIN
        )
        self.directeur = User.objects.create_user(
            username="dir", password="Pass1234!", role=UserRole.DIRECTOR
        )
        self.anonyme = APIClient()

    def _client(self, compte):
        client = APIClient()
        client.force_authenticate(compte)
        return client

    def test_la_lecture_est_ouverte_avant_toute_connexion(self):
        """L'ecran de connexion en a besoin, et il precede l'authentification."""
        reponse = self.anonyme.get(URL)

        self.assertEqual(reponse.status_code, 200)
        self.assertIn("nom_ecole", reponse.data)
        self.assertIn("logo_url", reponse.data)

    def test_la_lecture_cree_la_ligne_au_premier_appel(self):
        PersonnalisationPlateforme.objects.all().delete()

        reponse = self.anonyme.get(URL)

        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(PersonnalisationPlateforme.objects.count(), 1)

    def test_le_super_admin_modifie_l_identite(self):
        reponse = self._client(self.super_admin).patch(
            URL,
            {"nom_ecole": "Complexe Scolaire Oumar Bah", "sigle": "CSOB"},
            format="json",
        )

        self.assertEqual(reponse.status_code, 200)
        actuelle = PersonnalisationPlateforme.actuelle()
        self.assertEqual(actuelle.nom_ecole, "Complexe Scolaire Oumar Bah")
        self.assertEqual(actuelle.sigle, "CSOB")

    def test_un_directeur_ne_personnalise_pas_la_plateforme(self):
        """Elle engage tous les etablissements, pas seulement le sien."""
        reponse = self._client(self.directeur).patch(
            URL, {"nom_ecole": "Mon lycee"}, format="json"
        )

        self.assertEqual(reponse.status_code, 403)
        self.assertNotEqual(PersonnalisationPlateforme.actuelle().nom_ecole, "Mon lycee")

    def test_un_anonyme_ne_modifie_rien(self):
        reponse = self.anonyme.patch(URL, {"nom_ecole": "Pirate"}, format="json")

        self.assertEqual(reponse.status_code, 401)
        self.assertNotEqual(PersonnalisationPlateforme.actuelle().nom_ecole, "Pirate")

    def test_une_couleur_invalide_est_refusee(self):
        """Le client la lit comme un entier hexadecimal: du texte libre y
        donnerait une couleur au hasard, ou une exception au demarrage."""
        reponse = self._client(self.super_admin).patch(
            URL, {"couleur_principale": "bleu ciel"}, format="json"
        )

        self.assertEqual(reponse.status_code, 400)
        self.assertIn("couleur_principale", reponse.data)

    def test_une_couleur_sans_diese_est_rattrapee(self):
        reponse = self._client(self.super_admin).patch(
            URL, {"couleur_principale": "1a2b3c"}, format="json"
        )

        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(reponse.data["couleur_principale"], "#1A2B3C")

    def test_une_couleur_vide_revient_au_defaut(self):
        reponse = self._client(self.super_admin).patch(
            URL, {"couleur_principale": ""}, format="json"
        )

        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(reponse.data["couleur_principale"], "#6D5BFF")

    def test_il_n_y_a_jamais_qu_une_seule_identite(self):
        """Deux lignes donneraient deux identites, et l'ecran servirait
        celle que le tri ramene en premier."""
        PersonnalisationPlateforme.objects.create(nom_ecole="Deuxieme")
        PersonnalisationPlateforme.objects.create(nom_ecole="Troisieme")

        self.assertEqual(PersonnalisationPlateforme.objects.count(), 1)
        self.assertEqual(PersonnalisationPlateforme.actuelle().nom_ecole, "Troisieme")

    def test_l_identite_ne_se_supprime_pas(self):
        """Sans elle, les ecrans publics n'auraient plus rien a afficher."""
        PersonnalisationPlateforme.actuelle().delete()

        self.assertEqual(PersonnalisationPlateforme.objects.count(), 1)

    def test_les_libelles_vides_restent_vides(self):
        """Les ecrans gardent alors leurs formulations d'origine: une ecole
        qui ne personnalise rien ne doit pas heriter de libelles blancs."""
        reponse = self.anonyme.get(URL)

        self.assertEqual(reponse.data["titre_connexion"], "")
        self.assertEqual(reponse.data["titre_portail"], "")

    def test_les_deux_regles_de_mot_de_passe_sont_servies(self):
        """Celle de l'eleve et celle du parent.

        La seconde vivait en dur dans le module d'admission: l'ecran ne
        montrait que la premiere, et une ecole n'avait aucun moyen de savoir
        quel mot de passe ses familles recevaient.
        """
        reponse = self.anonyme.get(URL)

        self.assertEqual(reponse.data["mot_de_passe_eleve_modele"], "{matricule}")
        self.assertEqual(reponse.data["mot_de_passe_parent_modele"], "{telephone}")

    def test_la_regle_du_parent_se_regle_depuis_l_ecran(self):
        reponse = self._client(self.super_admin).patch(
            URL,
            {"mot_de_passe_parent_modele": "{sigle}{telephone}"},
            format="json",
        )

        self.assertEqual(reponse.status_code, 200)
        self.assertEqual(
            PersonnalisationPlateforme.actuelle().mot_de_passe_parent_modele,
            "{sigle}{telephone}",
        )

    def test_regler_l_une_ne_touche_pas_l_autre(self):
        self._client(self.super_admin).patch(
            URL, {"mot_de_passe_parent_modele": "{nom}{annee}"}, format="json"
        )

        actuelle = PersonnalisationPlateforme.actuelle()
        self.assertEqual(actuelle.mot_de_passe_eleve_modele, "{matricule}")
        self.assertEqual(actuelle.mot_de_passe_parent_modele, "{nom}{annee}")

    def test_un_directeur_ne_regle_pas_les_mots_de_passe_des_familles(self):
        reponse = self._client(self.directeur).patch(
            URL, {"mot_de_passe_parent_modele": "{prenom}"}, format="json"
        )

        self.assertEqual(reponse.status_code, 403)

    def test_le_logo_absent_ne_rend_pas_une_url_cassee(self):
        reponse = self.anonyme.get(URL)

        self.assertEqual(reponse.data["logo_url"], "")
