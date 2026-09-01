"""Qui peut ouvrir une conversation avec qui.

La messagerie s'ouvrait de tous vers tous dans l'etablissement: un eleve
pouvait ecrire au comptable ou au promoteur, deux eleves pouvaient
correspondre entre eux sous couvert de l'ecole.

Quatre portes menent a une conversation -- l'annuaire, le message direct, la
creation d'un groupe, l'ajout a un groupe existant. Elles sont testees une par
une: en fermer trois n'aurait ferme aucune.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.chat.correspondants import peut_correspondre
from apps.chat.models import Conversation, ConversationParticipant
from apps.school.models import AcademicYear, Etablissement


class RegleDeCorrespondanceTests(APITestCase):
    """La regle seule, avant toute question d'API."""

    def test_l_eleve_joint_le_personnel_pedagogique(self):
        for role in (
            UserRole.TEACHER,
            UserRole.CENSOR,
            UserRole.SUPERVISOR,
            UserRole.DIRECTOR,
            UserRole.SUPER_ADMIN,
        ):
            self.assertTrue(
                peut_correspondre(UserRole.STUDENT, role),
                f"un eleve devrait pouvoir ecrire a {role}",
            )

    def test_l_eleve_ne_joint_ni_la_comptabilite_ni_le_promoteur(self):
        self.assertFalse(peut_correspondre(UserRole.STUDENT, UserRole.ACCOUNTANT))
        self.assertFalse(peut_correspondre(UserRole.STUDENT, UserRole.PROMOTER))

    def test_deux_eleves_ne_correspondent_pas(self):
        self.assertFalse(peut_correspondre(UserRole.STUDENT, UserRole.STUDENT))

    def test_deux_parents_non_plus(self):
        self.assertFalse(peut_correspondre(UserRole.PARENT, UserRole.PARENT))

    def test_la_regle_est_symetrique(self):
        # Sans cela, le comptable ouvrirait la conversation et l'eleve n'aurait
        # plus qu'a repondre: la restriction ne tiendrait pas une journee.
        self.assertFalse(peut_correspondre(UserRole.ACCOUNTANT, UserRole.STUDENT))
        self.assertFalse(peut_correspondre(UserRole.PROMOTER, UserRole.PARENT))

    def test_le_personnel_continue_de_se_parler(self):
        self.assertTrue(peut_correspondre(UserRole.ACCOUNTANT, UserRole.TEACHER))
        self.assertTrue(peut_correspondre(UserRole.PROMOTER, UserRole.DIRECTOR))
        self.assertTrue(peut_correspondre(UserRole.SUPERVISOR, UserRole.CENSOR))


class _Decor:
    @classmethod
    def _monter(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Etab Correspondance", code="EC2"
        )
        AcademicYear.objects.create(
            name="2025-2026 EC2",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.eleve = cls._compte("eleve_corr", UserRole.STUDENT)
        cls.autre_eleve = cls._compte("eleve_corr_bis", UserRole.STUDENT)
        cls.parent = cls._compte("parent_corr", UserRole.PARENT)
        cls.enseignant = cls._compte("ens_corr", UserRole.TEACHER)
        cls.comptable = cls._compte("compta_corr", UserRole.ACCOUNTANT)
        cls.directeur = cls._compte("dir_corr", UserRole.DIRECTOR)

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


class AnnuaireTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def _annuaire(self):
        reponse = self.client.get("/api/chat/users/", **self._entete())
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        return {ligne["username"] for ligne in reponse.data}

    def test_l_annuaire_de_l_eleve_ne_montre_que_le_pedagogique(self):
        # Laisser apparaitre un nom qu'on ne peut pas joindre revient a
        # promettre puis refuser.
        self.client.force_authenticate(self.eleve)

        noms = self._annuaire()

        self.assertIn("ens_corr", noms)
        self.assertIn("dir_corr", noms)
        self.assertNotIn("compta_corr", noms)
        self.assertNotIn("eleve_corr_bis", noms)
        self.assertNotIn("parent_corr", noms)

    def test_l_annuaire_du_comptable_ne_montre_plus_les_familles(self):
        self.client.force_authenticate(self.comptable)

        noms = self._annuaire()

        self.assertIn("ens_corr", noms)
        self.assertIn("dir_corr", noms)
        self.assertNotIn("eleve_corr", noms)
        self.assertNotIn("parent_corr", noms)

    def test_l_annuaire_de_l_enseignant_reste_entier(self):
        self.client.force_authenticate(self.enseignant)

        noms = self._annuaire()

        self.assertIn("eleve_corr", noms)
        self.assertIn("parent_corr", noms)
        self.assertIn("compta_corr", noms)


class ConversationDirecteTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def _ouvrir(self, cible):
        return self.client.post(
            "/api/chat/conversations/direct/",
            {"user_id": cible.id},
            format="json",
            **self._entete(),
        )

    def test_un_eleve_n_ouvre_pas_de_conversation_avec_le_comptable(self):
        # Filtrer l'annuaire ne suffit pas: cette route accepte un identifiant
        # brut, et rien n'oblige a etre passe par la liste pour l'obtenir.
        self.client.force_authenticate(self.eleve)

        reponse = self._ouvrir(self.comptable)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(
            Conversation.objects.filter(participants__user=self.comptable).exists()
        )

    def test_un_eleve_n_ecrit_pas_a_un_autre_eleve(self):
        self.client.force_authenticate(self.eleve)

        reponse = self._ouvrir(self.autre_eleve)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_eleve_ecrit_a_son_enseignant(self):
        self.client.force_authenticate(self.eleve)

        reponse = self._ouvrir(self.enseignant)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)

    def test_le_comptable_n_ouvre_pas_la_porte_dans_l_autre_sens(self):
        self.client.force_authenticate(self.comptable)

        reponse = self._ouvrir(self.eleve)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)


class GroupeTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def test_un_groupe_ne_reunit_pas_ce_qui_ne_peut_se_parler(self):
        # Un groupe met tout le monde avec tout le monde: il ne doit pas servir
        # de detour a la regle.
        self.client.force_authenticate(self.enseignant)

        reponse = self.client.post(
            "/api/chat/conversations/group/",
            {
                "title": "Suivi de classe",
                "participant_ids": [self.eleve.id, self.comptable.id],
            },
            format="json",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_un_groupe_pedagogique_passe(self):
        self.client.force_authenticate(self.enseignant)

        reponse = self.client.post(
            "/api/chat/conversations/group/",
            {
                "title": "Suivi de classe",
                "participant_ids": [self.eleve.id, self.directeur.id],
            },
            format="json",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)

    def test_on_n_ajoute_pas_apres_coup_ce_qu_on_ne_pouvait_pas_reunir(self):
        # Verrouiller la creation sans verrouiller les ajouts ne verrouille
        # rien: il suffirait de creer le groupe puis d'y glisser la personne.
        conversation = Conversation.objects.create(
            is_group=True, title="Suivi", etablissement=self.etablissement
        )
        ConversationParticipant.objects.create(
            conversation=conversation, user=self.enseignant, is_admin=True
        )
        ConversationParticipant.objects.create(
            conversation=conversation, user=self.eleve
        )

        self.client.force_authenticate(self.enseignant)
        reponse = self.client.post(
            f"/api/chat/conversations/{conversation.id}/group/add-member/",
            {"user_id": self.comptable.id},
            format="json",
            **self._entete(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(
            ConversationParticipant.objects.filter(
                conversation=conversation, user=self.comptable
            ).exists()
        )
