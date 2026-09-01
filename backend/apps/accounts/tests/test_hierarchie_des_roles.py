"""On n'administre que des comptes situes sous le sien.

La matrice ouvrait le module « users » a la direction sans dire sur QUELS
comptes. Un directeur pouvait donc creer un super-administrateur, ou
reinitialiser le mot de passe de celui qui existait, et s'y connecter: la
restauration de la base, tous les etablissements et la passerelle SMS lui
tombaient dans les mains d'un coup -- les trois choses que la matrice lui
refuse par ailleurs.

Chaque chemin est teste separement parce que chacun suffisait a lui seul:
fermer la creation sans fermer la reinitialisation n'aurait rien change.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.access import peut_administrer_compte
from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement


class EchelleDesRolesTests(APITestCase):
    """La regle elle-meme, avant toute question d'API."""

    def test_le_super_admin_administre_tout_le_monde(self):
        for role in UserRole.values:
            self.assertTrue(
                peut_administrer_compte(UserRole.SUPER_ADMIN, role),
                f"le super-admin devrait pouvoir administrer {role}",
            )

    def test_le_directeur_n_atteint_pas_le_super_admin(self):
        self.assertFalse(
            peut_administrer_compte(UserRole.DIRECTOR, UserRole.SUPER_ADMIN)
        )

    def test_le_directeur_ne_nomme_pas_un_autre_directeur(self):
        # Plus sec que necessaire dans le cas courant, mais c'est la seule
        # regle qui ne laisse aucun chemin vers une promotion de soi-meme par
        # personne interposee.
        self.assertFalse(peut_administrer_compte(UserRole.DIRECTOR, UserRole.DIRECTOR))

    def test_le_directeur_administre_le_personnel_sous_lui(self):
        for role in (
            UserRole.CENSOR,
            UserRole.ACCOUNTANT,
            UserRole.SUPERVISOR,
            UserRole.TEACHER,
            UserRole.PARENT,
            UserRole.STUDENT,
        ):
            self.assertTrue(
                peut_administrer_compte(UserRole.DIRECTOR, role),
                f"le directeur devrait pouvoir administrer {role}",
            )

    def test_les_rangs_egaux_ne_s_administrent_pas(self):
        self.assertFalse(peut_administrer_compte(UserRole.CENSOR, UserRole.ACCOUNTANT))
        self.assertFalse(peut_administrer_compte(UserRole.TEACHER, UserRole.SUPERVISOR))

    def test_un_role_inconnu_n_administre_rien(self):
        # On echoue ferme: un role qui n'est pas dans l'echelle ne se voit pas
        # accorder le benefice du doute.
        self.assertFalse(peut_administrer_compte("", UserRole.STUDENT))
        self.assertFalse(peut_administrer_compte("inspecteur", UserRole.STUDENT))
        self.assertFalse(peut_administrer_compte(UserRole.DIRECTOR, "inspecteur"))


class _Decor:
    @classmethod
    def _monter(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Hierarchie", code="EH")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 EH",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.directeur = cls._compte("dir_hier", UserRole.DIRECTOR)
        cls.super_admin = cls._compte("sa_hier", UserRole.SUPER_ADMIN)
        cls.enseignant = cls._compte("ens_hier", UserRole.TEACHER)

    @classmethod
    def _compte(cls, username, role):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=role,
            etablissement=cls.etablissement,
        )

    def _entete(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}


class CreationDeCompteTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.directeur)

    def _creer(self, role, username="nouveau_compte"):
        return self.client.post(
            "/api/auth/users/",
            {
                "username": username,
                "first_name": "Test",
                "last_name": "Compte",
                "role": role,
            },
            format="json",
            **self._entete(),
        )

    def test_un_directeur_ne_cree_pas_de_super_admin(self):
        reponse = self._creer(UserRole.SUPER_ADMIN)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("role", reponse.data)
        self.assertFalse(User.objects.filter(username="nouveau_compte").exists())

    def test_un_directeur_ne_cree_pas_un_autre_directeur(self):
        reponse = self._creer(UserRole.DIRECTOR)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_directeur_cree_le_personnel_sous_lui(self):
        reponse = self._creer(UserRole.ACCOUNTANT, username="compta_neuf")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        self.assertTrue(User.objects.filter(username="compta_neuf").exists())

    def test_le_super_admin_cree_un_super_admin(self):
        self.client.force_authenticate(self.super_admin)

        reponse = self._creer(UserRole.SUPER_ADMIN, username="sa_neuf")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)

    def test_la_route_d_inscription_applique_la_meme_regle(self):
        # Deux portes menent a la creation d'un compte: fermer l'une sans
        # l'autre ne ferme rien.
        reponse = self.client.post(
            "/api/auth/register/",
            {
                "username": "sa_par_register",
                "password": "Pass1234!",
                "role": UserRole.SUPER_ADMIN,
            },
            format="json",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(User.objects.filter(username="sa_par_register").exists())


class PromotionTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.directeur)

    def _modifier(self, cible, **charge):
        return self.client.patch(
            f"/api/auth/users/{cible.id}/",
            charge,
            format="json",
            **self._entete(),
        )

    def test_un_directeur_ne_promeut_personne_super_admin(self):
        reponse = self._modifier(self.enseignant, role=UserRole.SUPER_ADMIN)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.enseignant.refresh_from_db()
        self.assertEqual(self.enseignant.role, UserRole.TEACHER)

    def test_un_directeur_ne_se_promeut_pas_lui_meme(self):
        reponse = self._modifier(self.directeur, role=UserRole.SUPER_ADMIN)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.directeur.refresh_from_db()
        self.assertEqual(self.directeur.role, UserRole.DIRECTOR)

    def test_un_directeur_promeut_dans_ce_qui_est_sous_lui(self):
        reponse = self._modifier(self.enseignant, role=UserRole.CENSOR)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.enseignant.refresh_from_db()
        self.assertEqual(self.enseignant.role, UserRole.CENSOR)

    def test_un_directeur_ne_touche_pas_au_compte_d_un_super_admin(self):
        reponse = self._modifier(self.super_admin, first_name="Renomme")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.super_admin.refresh_from_db()
        self.assertNotEqual(self.super_admin.first_name, "Renomme")

    def test_personne_ne_change_son_propre_role(self):
        self.client.force_authenticate(self.super_admin)

        reponse = self._modifier(self.super_admin, role=UserRole.TEACHER)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.super_admin.refresh_from_db()
        self.assertEqual(self.super_admin.role, UserRole.SUPER_ADMIN)

    def test_le_dernier_super_admin_ne_se_fait_pas_retrograder(self):
        # Meme protection que la desactivation: sans lui, plus personne ne
        # peut rendre le rôle a quiconque.
        autre_sa = self._compte("sa_bis", UserRole.SUPER_ADMIN)
        self.client.force_authenticate(autre_sa)

        reponse = self._modifier(self.super_admin, role=UserRole.TEACHER)
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)

        # Il ne reste plus que `autre_sa`, qui ne peut pas se retrograder
        # lui-meme -- et personne d'autre ne le peut non plus.
        reponse = self.client.patch(
            f"/api/auth/users/{autre_sa.id}/",
            {"role": UserRole.TEACHER},
            format="json",
            **self._entete(),
        )
        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)


class ReinitialisationEtSuppressionTests(_Decor, APITestCase):
    """Reinitialiser le mot de passe de quelqu'un, c'est prendre sa place."""

    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.directeur)

    def test_un_directeur_ne_reinitialise_pas_le_mot_de_passe_d_un_super_admin(self):
        reponse = self.client.post(
            f"/api/auth/users/{self.super_admin.id}/reset-password/",
            {"password": "MotDePasseConnu1"},
            format="json",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.super_admin.refresh_from_db()
        self.assertFalse(self.super_admin.check_password("MotDePasseConnu1"))

    def test_un_directeur_reinitialise_le_personnel_sous_lui(self):
        reponse = self.client.post(
            f"/api/auth/users/{self.enseignant.id}/reset-password/",
            {"password": "Provisoire123"},
            format="json",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.enseignant.refresh_from_db()
        self.assertTrue(self.enseignant.check_password("Provisoire123"))

    def test_un_directeur_ne_supprime_aucun_compte(self):
        """Deux verrous, dans cet ordre.

        La matrice arrete la suppression avant la hierarchie: le directeur a
        l'ecriture sur « users », pas la suppression, et DELETE exige le
        niveau superieur. La garde de rang qui suit dans la vue est une
        seconde ligne, utile le jour ou la matrice bougerait.
        """
        reponse = self.client.delete(
            f"/api/auth/users/{self.super_admin.id}/?confirm=1",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(User.objects.filter(pk=self.super_admin.pk).exists())

    def test_le_super_admin_reste_seul_a_supprimer(self):
        self.client.force_authenticate(self.super_admin)

        reponse = self.client.delete(
            f"/api/auth/users/{self.enseignant.id}/?confirm=1",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(pk=self.enseignant.pk).exists())
