"""Le journal offrait ses filtres au serveur, et l'ecran n'en proposait aucun.

`ActivityLogViewSet` filtre depuis toujours sur `user`, `role` et `module`.
L'ecran ne donnait que la methode HTTP, le succes et les dates: « qui a fait
ca » et « qu'est-ce qui s'est passe dans les paiements » -- les deux seules
questions qu'on pose a un journal d'audit -- n'etaient pas posables.

Pour peupler ces listes, l'ecran a besoin de savoir quels modules et quels
auteurs le journal contient reellement. C'est ce que `repertoire/` rend, et ce
que ces tests fixent.
"""

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.common.models import ActivityLog
from apps.school.models import Etablissement


class RepertoireDuJournalTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycee du journal", code="LJRN"
        )
        cls.autre = Etablissement.objects.create(
            name="Lycee voisin", code="LVOI"
        )

        cls.admin = User.objects.create_user(
            username="admin_journal",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=cls.etablissement,
        )
        cls.comptable = User.objects.create_user(
            username="cpt_journal",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
            first_name="Awa",
            last_name="Traore",
        )
        cls.enseignant = User.objects.create_user(
            username="ens_journal",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
        )

        cls._ligne(cls.comptable, "payments", "POST", 201, True)
        cls._ligne(cls.comptable, "payments", "POST", 201, True)
        cls._ligne(cls.enseignant, "grades", "DELETE", 403, False)
        # Une ecriture anonyme: elle a bien un module, mais pas d'auteur.
        cls._ligne(None, "auth", "POST", 401, False)
        # Et une d'un autre etablissement, qui ne doit pas se melanger.
        ActivityLog.objects.create(
            user=None,
            etablissement=cls.autre,
            role="",
            action="Autre ecole",
            method="POST",
            path="/api/library/",
            module="library",
            status_code=201,
            success=True,
        )

    @classmethod
    def _ligne(cls, auteur, module, methode, statut, reussi):
        return ActivityLog.objects.create(
            user=auteur,
            etablissement=cls.etablissement,
            role=getattr(auteur, "role", "") or "",
            action=f"{methode} {module}",
            method=methode,
            path=f"/api/{module}/",
            module=module,
            status_code=statut,
            success=reussi,
        )

    def _repertoire(self, entetes=None):
        self.client.force_authenticate(self.admin)
        reponse = self.client.get("/api/activity-logs/repertoire/", **(entetes or {}))
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data

    def test_les_modules_viennent_du_journal(self):
        """Une liste ecrite cote ecran aurait vieilli des la route suivante."""
        donnees = self._repertoire()

        self.assertEqual(donnees["modules"], ["auth", "grades", "library", "payments"])

    def test_un_auteur_ne_figure_qu_une_fois(self):
        """Le comptable a deux lignes: la liste de choix n'en veut qu'une."""
        donnees = self._repertoire()

        identifiants = [auteur["id"] for auteur in donnees["auteurs"]]
        self.assertEqual(identifiants.count(self.comptable.id), 1)

    def test_l_auteur_porte_son_nom_et_son_role(self):
        donnees = self._repertoire()

        comptable = next(
            auteur
            for auteur in donnees["auteurs"]
            if auteur["id"] == self.comptable.id
        )
        self.assertEqual(comptable["label"], "Awa Traore")
        self.assertEqual(comptable["role"], UserRole.ACCOUNTANT)

    def test_une_ecriture_anonyme_ne_cree_pas_d_auteur_vide(self):
        """Une tentative de connexion refusee n'a pas d'auteur a proposer."""
        donnees = self._repertoire()

        self.assertTrue(all(auteur["id"] for auteur in donnees["auteurs"]))

    def test_le_perimetre_demande_ecarte_l_autre_ecole(self):
        donnees = self._repertoire(
            {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}
        )

        self.assertNotIn("library", donnees["modules"])

    def test_les_trois_filtres_reduisent_bien_le_journal(self):
        """Le serveur les acceptait deja; on fixe qu'il continue."""
        self.client.force_authenticate(self.admin)

        par_auteur = self.client.get(
            f"/api/activity-logs/?user={self.enseignant.id}"
        )
        par_module = self.client.get("/api/activity-logs/?module=payments")
        par_role = self.client.get(f"/api/activity-logs/?role={UserRole.ACCOUNTANT}")

        self.assertEqual(len(par_auteur.data["results"]), 1)
        self.assertEqual(len(par_module.data["results"]), 2)
        self.assertEqual(len(par_role.data["results"]), 2)

    def test_le_journal_est_ferme_a_qui_n_y_a_pas_droit(self):
        """`activity_logs` n'est ouvert qu'au super-admin et a la direction."""
        self.client.force_authenticate(self.enseignant)

        reponse = self.client.get("/api/activity-logs/repertoire/")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
