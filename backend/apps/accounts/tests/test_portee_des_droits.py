"""Deux droits ouverts, et l'etoile qui les retient.

La matrice accorde desormais le dossier eleve a la famille, et la fiche
d'etablissement au directeur. Les deux portent une portee restreinte -- « son
enfant », « son ecole ». Une etoile dans un tableau n'arrete rien par
elle-meme: ce qui suit verifie que quelqu'un l'applique.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ParentProfile,
    Student,
)


class DossierDeLaFamilleTests(APITestCase):
    """Parent et eleve lisent leur dossier, et rien d'autre."""

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Portee", code="EP")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 EP",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )

        cls.compte_parent = User.objects.create_user(
            username="parent_portee",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=cls.etablissement,
        )
        cls.profil_parent = ParentProfile.objects.create(user=cls.compte_parent)

        cls.compte_eleve = User.objects.create_user(
            username="eleve_portee",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.compte_eleve.first_name = "Awa"
        cls.compte_eleve.last_name = "Traore"
        cls.compte_eleve.save(update_fields=["first_name", "last_name"])
        cls.mon_enfant = Student.objects.create(
            classroom=cls.classe,
            etablissement=cls.etablissement,
            user=cls.compte_eleve,
            parent=cls.profil_parent,
        )

        # Un eleve de la meme classe, sans lien avec cette famille: c'est lui
        # que la portee doit tenir hors de vue.
        compte_voisin = User.objects.create_user(
            username="eleve_voisin",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
            first_name="Moussa",
            last_name="Diarra",
        )
        cls.enfant_des_autres = Student.objects.create(
            classroom=cls.classe,
            etablissement=cls.etablissement,
            user=compte_voisin,
        )

    def _entete(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}

    def _lignes(self, reponse):
        donnees = reponse.data
        if isinstance(donnees, dict):
            return donnees.get("results", [])
        return donnees

    def test_le_parent_lit_le_dossier_de_son_enfant(self):
        # Il lisait deja les notes et les absences, mais pas la fiche: une
        # erreur sur un numero de telephone lui restait invisible.
        self.client.force_authenticate(self.compte_parent)

        reponse = self.client.get("/api/students/", **self._entete())

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        identifiants = {ligne["id"] for ligne in self._lignes(reponse)}
        self.assertEqual(identifiants, {self.mon_enfant.id})

    def test_le_parent_n_atteint_pas_l_enfant_d_un_autre(self):
        self.client.force_authenticate(self.compte_parent)

        reponse = self.client.get(
            f"/api/students/{self.enfant_des_autres.id}/", **self._entete()
        )

        self.assertEqual(reponse.status_code, status.HTTP_404_NOT_FOUND)

    def test_l_eleve_ne_lit_que_son_propre_dossier(self):
        self.client.force_authenticate(self.compte_eleve)

        reponse = self.client.get("/api/students/", **self._entete())

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        identifiants = {ligne["id"] for ligne in self._lignes(reponse)}
        self.assertEqual(identifiants, {self.mon_enfant.id})

    def test_la_lecture_n_emporte_pas_l_ecriture(self):
        # L'ouverture ne porte que la consultation: corriger sa propre fiche
        # reste hors de portee.
        self.client.force_authenticate(self.compte_parent)

        reponse = self.client.patch(
            f"/api/students/{self.mon_enfant.id}/",
            {"matricule": "TRUQUE-001"},
            format="json",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.mon_enfant.refresh_from_db()
        self.assertNotEqual(self.mon_enfant.matricule, "TRUQUE-001")

    def test_la_famille_ne_supprime_aucun_dossier(self):
        self.client.force_authenticate(self.compte_eleve)

        reponse = self.client.delete(
            f"/api/students/{self.mon_enfant.id}/", **self._entete()
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Student.objects.filter(pk=self.mon_enfant.pk).exists())


class FicheEtablissementTests(APITestCase):
    """Le directeur corrige son ecole, pas celle du voisin."""

    @classmethod
    def setUpTestData(cls):
        cls.mon_etablissement = Etablissement.objects.create(name="Mon Ecole", code="ME")
        cls.autre_etablissement = Etablissement.objects.create(
            name="Ecole Voisine", code="EV"
        )
        cls.directeur = User.objects.create_user(
            username="dir_portee",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.mon_etablissement,
        )
        cls.super_admin = User.objects.create_user(
            username="sa_portee",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=cls.mon_etablissement,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.directeur)

    def test_le_directeur_corrige_la_fiche_de_son_ecole(self):
        # Nom, adresse, telephone, logo, en-tete des bulletins: chaque
        # correction passait par le super-administrateur.
        reponse = self.client.patch(
            f"/api/etablissements/{self.mon_etablissement.id}/",
            {"phone": "66083152"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.mon_etablissement.refresh_from_db()
        self.assertEqual(self.mon_etablissement.phone, "66083152")

    def test_le_directeur_ne_touche_pas_a_l_ecole_voisine(self):
        reponse = self.client.patch(
            f"/api/etablissements/{self.autre_etablissement.id}/",
            {"name": "Ecole Capturee"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.autre_etablissement.refresh_from_db()
        self.assertEqual(self.autre_etablissement.name, "Ecole Voisine")

    def test_le_directeur_ne_cree_pas_d_etablissement(self):
        reponse = self.client.post(
            "/api/etablissements/",
            {"name": "Ecole Inventee", "code": "EI"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(Etablissement.objects.filter(name="Ecole Inventee").exists())

    def test_le_directeur_ne_supprime_pas_son_etablissement(self):
        # La suppression demande le niveau superieur, que la matrice ne lui
        # donne pas: l'ecriture ouverte pour corriger une fiche n'ouvre pas
        # la porte a l'effacer.
        reponse = self.client.delete(
            f"/api/etablissements/{self.mon_etablissement.id}/"
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(
            Etablissement.objects.filter(pk=self.mon_etablissement.pk).exists()
        )

    def test_le_super_admin_garde_la_main_sur_toutes_les_ecoles(self):
        self.client.force_authenticate(self.super_admin)

        reponse = self.client.patch(
            f"/api/etablissements/{self.autre_etablissement.id}/",
            {"phone": "70000000"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)

    def test_le_super_admin_cree_encore_des_etablissements(self):
        self.client.force_authenticate(self.super_admin)

        reponse = self.client.post(
            "/api/etablissements/",
            {"name": "Ecole Neuve", "code": "EN"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
