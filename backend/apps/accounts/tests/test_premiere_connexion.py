"""Le mot de passe remis a la famille ne vaut que pour une fois.

Il suit une regle que l'ecole applique a tous, et l'identifiant est le
matricule -- imprime sur la carte scolaire, les listes d'appel et les
bulletins. Un eleve qui devine la regle a partir de la sienne ouvrirait le
compte de toute sa classe. Ce qui l'en empeche n'est pas le secret du modele,
c'est que le mot de passe cesse de servir des la premiere connexion.
"""

import json
from datetime import date

from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement

User = get_user_model()


class PremiereConnexionTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etab = Etablissement.objects.create(name="Ecole premiere", code="EPRE")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 premiere",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6eme B", academic_year=cls.annee, etablissement=cls.etab
        )
        cls.directeur = User.objects.create_user(
            username="dir_premiere",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etab,
        )

    def _inscrire(self):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/students/inscription/",
            {
                "first_name": "Aminata",
                "last_name": "Coulibaly",
                "gender": "F",
                "classroom": self.classe.id,
                "lien_parente": "mere",
                "parent_first_name": "Fanta",
                "parent_last_name": "Coulibaly",
                "parent_phone": "76 00 11 22",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etab.id),
        )
        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.client.force_authenticate(None)
        return reponse.data["identifiants_eleve"]

    def _jeton(self, username, mot_de_passe):
        reponse = self.client.post(
            "/api/auth/login/",
            {"username": username, "password": mot_de_passe},
            format="json",
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data["access"]

    def test_rien_ne_s_ouvre_avant_le_changement(self):
        """Le drapeau ne suffit pas: il faut que quelque chose l'applique."""
        remis = self._inscrire()
        jeton = self._jeton(remis["username"], remis["mot_de_passe"])

        reponse = self.client.get(
            "/api/students/", HTTP_AUTHORIZATION=f"Bearer {jeton}"
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        # Le refus vient du middleware, donc d'une JsonResponse: c'est le
        # corps qu'on lit, pas `.data` de DRF.
        corps = json.loads(reponse.content.decode())
        self.assertTrue(corps["changement_de_mot_de_passe_requis"])

    def test_l_ecran_de_changement_reste_joignable(self):
        remis = self._inscrire()
        jeton = self._jeton(remis["username"], remis["mot_de_passe"])

        reponse = self.client.post(
            "/api/auth/changer-mot-de-passe/",
            {"nouveau_mot_de_passe": "MonChoix2026"},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {jeton}",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)

    def test_apres_le_changement_l_application_s_ouvre(self):
        remis = self._inscrire()
        jeton = self._jeton(remis["username"], remis["mot_de_passe"])
        self.client.post(
            "/api/auth/changer-mot-de-passe/",
            {"nouveau_mot_de_passe": "MonChoix2026"},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {jeton}",
        )

        reponse = self.client.get(
            "/api/students/", HTTP_AUTHORIZATION=f"Bearer {jeton}"
        )

        self.assertNotEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_le_mot_de_passe_remis_ne_sert_plus(self):
        """Le papier circule: il ne doit plus rien ouvrir."""
        remis = self._inscrire()
        jeton = self._jeton(remis["username"], remis["mot_de_passe"])
        self.client.post(
            "/api/auth/changer-mot-de-passe/",
            {"nouveau_mot_de_passe": "MonChoix2026"},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {jeton}",
        )

        refus = self.client.post(
            "/api/auth/login/",
            {"username": remis["username"], "password": remis["mot_de_passe"]},
            format="json",
        )

        self.assertEqual(refus.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_garder_le_meme_mot_de_passe_est_refuse(self):
        remis = self._inscrire()
        jeton = self._jeton(remis["username"], remis["mot_de_passe"])

        reponse = self.client.post(
            "/api/auth/changer-mot-de-passe/",
            {"nouveau_mot_de_passe": remis["mot_de_passe"]},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {jeton}",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_le_compte_bloque_ne_peut_pas_se_liberer_lui_meme(self):
        """La route /me/ reste ouverte pendant le blocage: elle ne doit pas
        servir a s'ecrire « je n'ai plus rien a changer »."""
        remis = self._inscrire()
        jeton = self._jeton(remis["username"], remis["mot_de_passe"])

        self.client.patch(
            "/api/auth/users/me/",
            {"doit_changer_mot_de_passe": False},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {jeton}",
        )

        refus = self.client.get(
            "/api/students/", HTTP_AUTHORIZATION=f"Bearer {jeton}"
        )
        self.assertEqual(refus.status_code, status.HTTP_403_FORBIDDEN)

    def test_un_compte_ordinaire_n_est_pas_gene(self):
        """Le directeur n'a rien a changer: rien ne doit lui etre ferme."""
        jeton = self._jeton("dir_premiere", "Pass1234!")

        reponse = self.client.get(
            "/api/students/", HTTP_AUTHORIZATION=f"Bearer {jeton}"
        )

        self.assertNotEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_un_changement_volontaire_exige_l_ancien(self):
        """Sans cela, un jeton vole suffirait a prendre le compte."""
        jeton = self._jeton("dir_premiere", "Pass1234!")

        refus = self.client.post(
            "/api/auth/changer-mot-de-passe/",
            {"nouveau_mot_de_passe": "AutreChose2026"},
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {jeton}",
        )
        self.assertEqual(refus.status_code, status.HTTP_400_BAD_REQUEST)

        accepte = self.client.post(
            "/api/auth/changer-mot-de-passe/",
            {
                "ancien_mot_de_passe": "Pass1234!",
                "nouveau_mot_de_passe": "AutreChose2026",
            },
            format="json",
            HTTP_AUTHORIZATION=f"Bearer {jeton}",
        )
        self.assertEqual(accepte.status_code, status.HTTP_200_OK, accepte.data)
