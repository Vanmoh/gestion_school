"""Une annonce partait a tout le monde, quel que soit le public affiche.

L'ecran Communication offrait un champ « Audience (all, parents,
teachers...) » libre. Le champ etait bien enregistre, et lu par personne:
`AnnouncementViewSet.get_queryset` ne restreignait qu'a l'etablissement.
Une consigne de correction adressee aux enseignants s'affichait donc chez les
familles, que la matrice laisse entrer dans le module en lecture.
"""

import importlib
from datetime import date

from django.test import SimpleTestCase
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    Announcement,
    AnnouncementAudience,
    Etablissement,
    Notification,
    NotificationChannel,
    ParentProfile,
)


class SocleAnnonces(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycee des annonces", code="LANN"
        )

        def compte(username, role):
            return User.objects.create_user(
                username=username,
                password="Pass1234!",
                role=role,
                etablissement=cls.etablissement,
            )

        cls.directeur = compte("dir_annonce", UserRole.DIRECTOR)
        cls.censeur = compte("cen_annonce", UserRole.CENSOR)
        cls.comptable = compte("cpt_annonce", UserRole.ACCOUNTANT)
        cls.surveillant = compte("sur_annonce", UserRole.SUPERVISOR)
        cls.enseignant = compte("ens_annonce", UserRole.TEACHER)
        cls.compte_parent = compte("par_annonce", UserRole.PARENT)
        cls.eleve = compte("elv_annonce", UserRole.STUDENT)
        ParentProfile.objects.create(
            user=cls.compte_parent, etablissement=cls.etablissement
        )

        cls.pour_tous = cls._annonce("Rentree le 1er octobre", "all", cls.directeur)
        cls.pour_familles = cls._annonce(
            "Reunion de parents samedi", "families", cls.directeur
        )
        cls.pour_enseignants = cls._annonce(
            "Remise des copies avant vendredi", "teachers", cls.directeur
        )
        cls.pour_administration = cls._annonce(
            "Inventaire de la caisse lundi", "staff", cls.directeur
        )

    @classmethod
    def _annonce(cls, titre, public, auteur):
        return Announcement.objects.create(
            etablissement=cls.etablissement,
            title=titre,
            message=titre,
            audience=public,
            author=auteur,
        )

    def _entetes(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}

    def _titres_vus_par(self, compte):
        self.client.force_authenticate(compte)
        reponse = self.client.get("/api/announcements/", **self._entetes())
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        lignes = reponse.data.get("results", reponse.data)
        return {ligne["title"] for ligne in lignes}


class QuiLitUneAnnonceTests(SocleAnnonces):
    def test_une_consigne_aux_enseignants_ne_part_pas_aux_familles(self):
        """Le defaut d'origine, et la raison de tout ce qui suit."""
        vues = self._titres_vus_par(self.compte_parent)

        self.assertNotIn("Remise des copies avant vendredi", vues)
        self.assertNotIn("Inventaire de la caisse lundi", vues)

    def test_la_famille_lit_ce_qui_la_concerne(self):
        vues = self._titres_vus_par(self.compte_parent)

        self.assertIn("Rentree le 1er octobre", vues)
        self.assertIn("Reunion de parents samedi", vues)

    def test_l_eleve_lit_comme_sa_famille(self):
        vues = self._titres_vus_par(self.eleve)

        self.assertEqual(
            vues, {"Rentree le 1er octobre", "Reunion de parents samedi"}
        )

    def test_l_enseignant_a_sa_salle_des_profs_et_pas_la_comptabilite(self):
        vues = self._titres_vus_par(self.enseignant)

        self.assertIn("Remise des copies avant vendredi", vues)
        self.assertIn("Rentree le 1er octobre", vues)
        self.assertNotIn("Inventaire de la caisse lundi", vues)
        self.assertNotIn("Reunion de parents samedi", vues)

    def test_le_comptable_a_l_administration_et_pas_la_salle_des_profs(self):
        vues = self._titres_vus_par(self.comptable)

        self.assertIn("Inventaire de la caisse lundi", vues)
        self.assertNotIn("Remise des copies avant vendredi", vues)

    def test_le_censeur_lit_les_deux_cotes_du_personnel(self):
        """Il arbitre la pedagogie et siege a l'administration."""
        vues = self._titres_vus_par(self.censeur)

        self.assertIn("Remise des copies avant vendredi", vues)
        self.assertIn("Inventaire de la caisse lundi", vues)
        self.assertNotIn("Reunion de parents samedi", vues)

    def test_la_direction_relit_tout_ce_qu_elle_publie(self):
        vues = self._titres_vus_par(self.directeur)

        self.assertEqual(len(vues), 4)

    def test_l_auteur_retrouve_son_propre_message(self):
        """Un surveillant qui ecrit aux familles doit pouvoir se relire."""
        self._annonce("Sortie de 16h decalee", "families", self.surveillant)

        vues = self._titres_vus_par(self.surveillant)

        self.assertIn("Sortie de 16h decalee", vues)

    def test_un_public_invente_est_refuse(self):
        """Le champ etait libre: « Parents » et « parnets » y entraient."""
        self.client.force_authenticate(self.directeur)

        reponse = self.client.post(
            "/api/announcements/",
            {"title": "Essai", "message": "Essai", "audience": "parnets"},
            format="json",
            **self._entetes(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("audience", reponse.data)

    def test_sans_public_precise_l_annonce_s_adresse_a_tous(self):
        self.client.force_authenticate(self.directeur)

        reponse = self.client.post(
            "/api/announcements/",
            {"title": "Essai", "message": "Essai"},
            format="json",
            **self._entetes(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(reponse.data["audience"], AnnouncementAudience.TOUS)

    def test_le_public_se_filtre_et_se_cherche_au_serveur(self):
        """L'ecran cherchait en memoire, sur la seule page qu'il avait."""
        self.client.force_authenticate(self.directeur)

        par_public = self.client.get(
            "/api/announcements/?audience=families", **self._entetes()
        )
        par_mot = self.client.get(
            "/api/announcements/?search=caisse", **self._entetes()
        )

        self.assertEqual(
            [l["title"] for l in par_public.data.get("results", par_public.data)],
            ["Reunion de parents samedi"],
        )
        self.assertEqual(
            [l["title"] for l in par_mot.data.get("results", par_mot.data)],
            ["Inventaire de la caisse lundi"],
        )


class RetrouverUneNotificationTests(SocleAnnonces):
    """Ce qui n'est pas parti est la seule question qu'on pose a une file."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        Notification.objects.create(
            etablissement=cls.etablissement,
            recipient=cls.compte_parent,
            channel=NotificationChannel.SMS,
            title="Absence de votre enfant",
            message="Absence constatee ce matin.",
            is_sent=True,
        )
        Notification.objects.create(
            etablissement=cls.etablissement,
            recipient=cls.compte_parent,
            channel=NotificationChannel.PUSH,
            title="Bulletin disponible",
            message="Le bulletin du premier trimestre est disponible.",
            is_sent=False,
        )

    def _titres(self, requete):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.get(requete, **self._entetes())
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        lignes = reponse.data.get("results", reponse.data)
        return [ligne["title"] for ligne in lignes]

    def test_ce_qui_attend_encore_de_partir(self):
        self.assertEqual(
            self._titres("/api/notifications/?is_sent=false"),
            ["Bulletin disponible"],
        )

    def test_par_canal(self):
        self.assertEqual(
            self._titres("/api/notifications/?channel=sms"),
            ["Absence de votre enfant"],
        )

    def test_par_destinataire(self):
        self.assertEqual(
            len(self._titres(f"/api/notifications/?recipient={self.compte_parent.id}")),
            2,
        )

    def test_la_recherche_porte_sur_le_destinataire(self):
        """Un nom est ce qu'on a sous la main quand une famille se plaint."""
        self.assertEqual(
            len(self._titres("/api/notifications/?search=par_annonce")), 2
        )


class NormalisationDesAnciennesAudiencesTests(SimpleTestCase):
    """La reprise de la migration, eprouvee sans base.

    Le champ ayant ete libre, la base contient ce que les utilisateurs ont
    tape. On ne peut pas inserer ces valeurs apres coup -- `choices` les
    refuse -- donc on eprouve la fonction de conversion elle-meme.
    """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.migration = importlib.import_module(
            "apps.school.migrations.0069_l_annonce_porte_son_public"
        )

    def test_les_graphies_du_francais_et_de_l_anglais(self):
        normalisee = self.migration.audience_normalisee

        self.assertEqual(normalisee("parents"), "families")
        self.assertEqual(normalisee("Parents"), "families")
        self.assertEqual(normalisee("  ELEVES "), "families")
        self.assertEqual(normalisee("enseignants"), "teachers")
        self.assertEqual(normalisee("teacher"), "teachers")
        self.assertEqual(normalisee("administration"), "staff")

    def test_une_saisie_incomprise_garde_le_comportement_qu_elle_avait(self):
        """Faute de filtre, ces annonces partaient a tout le monde."""
        normalisee = self.migration.audience_normalisee

        self.assertEqual(normalisee("parnets"), "all")
        self.assertEqual(normalisee("6eme A"), "all")
        self.assertEqual(normalisee(""), "all")
        self.assertEqual(normalisee(None), "all")

    def test_les_quatre_publics_traversent_sans_changer(self):
        normalisee = self.migration.audience_normalisee

        for public in ("all", "families", "teachers", "staff"):
            self.assertEqual(normalisee(public), public)
