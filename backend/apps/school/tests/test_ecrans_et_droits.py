"""Ce qu'un ecran demande, et ce que le profil qui l'ouvre a le droit de lire.

Plusieurs ecrans chargeaient leurs donnees en un seul groupe. Un refus sur une
source annexe -- la liste des enseignants pour y retrouver son propre nom,
l'annee scolaire pour dater un tableau -- faisait tomber le groupe entier, et
l'ecran avec lui. Le profil voyait « erreur de chargement » la ou il ne lui
manquait qu'un detail.

Ces tests fixent ce que chaque role obtient reellement, pour que le jour ou
une matrice bouge, l'ecran qui s'en trouve prive le dise ici plutot que chez
l'utilisateur.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Teacher


class ProfilEnseignantTests(APITestCase):
    """L'enseignant retrouve sa propre fiche sans acceder au personnel."""

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Ecrans", code="EE")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 EE",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.compte = User.objects.create_user(
            username="ens_ecran",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
            first_name="Awa",
            last_name="Traore",
        )
        cls.enseignant = Teacher.objects.create(
            user=cls.compte,
            employee_code="ENS-77",
            hire_date=date(2025, 9, 1),
            etablissement=cls.etablissement,
        )
        cls.surveillant = User.objects.create_user(
            username="surv_ecran",
            password="Pass1234!",
            role=UserRole.SUPERVISOR,
            etablissement=cls.etablissement,
        )

    def _entete(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}

    def test_la_liste_du_personnel_reste_fermee_a_l_enseignant(self):
        """Le point de depart: c'est ce refus qui tuait son emargement."""
        self.client.force_authenticate(self.compte)

        reponse = self.client.get("/api/teachers/", **self._entete())

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_mais_il_obtient_sa_propre_fiche(self):
        self.client.force_authenticate(self.compte)

        reponse = self.client.get("/api/teachers/mon-profil/", **self._entete())

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["id"], self.enseignant.id)
        self.assertEqual(reponse.data["employee_code"], "ENS-77")

    def test_un_compte_sans_fiche_recoit_un_refus_clair(self):
        # Un surveillant n'est pas un enseignant: il n'a pas de fiche, et on
        # le lui dit plutot que de rendre celle de quelqu'un d'autre.
        self.client.force_authenticate(self.surveillant)

        reponse = self.client.get("/api/teachers/mon-profil/", **self._entete())

        self.assertEqual(reponse.status_code, status.HTTP_404_NOT_FOUND)

    def test_la_route_reste_fermee_aux_anonymes(self):
        self.client.force_authenticate(None)

        reponse = self.client.get("/api/teachers/mon-profil/")

        self.assertIn(
            reponse.status_code,
            (status.HTTP_401_UNAUTHORIZED, status.HTTP_403_FORBIDDEN),
        )

    def test_elle_ne_sert_pas_de_porte_derobee_sur_le_personnel(self):
        """Elle rend une fiche, jamais une liste."""
        collegue = User.objects.create_user(
            username="ens_collegue",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        Teacher.objects.create(
            user=collegue,
            employee_code="ENS-78",
            hire_date=date(2025, 9, 1),
            etablissement=self.etablissement,
        )

        self.client.force_authenticate(self.compte)
        reponse = self.client.get("/api/teachers/mon-profil/", **self._entete())

        self.assertIsInstance(reponse.data, dict)
        self.assertEqual(reponse.data["employee_code"], "ENS-77")


class DonneesAnnexesRefuseesTests(APITestCase):
    """L'inventaire de ce que chaque role se voit refuser.

    Ces refus ne sont pas des defauts -- la matrice les veut. Ce qui etait un
    defaut, c'est qu'un ecran entier tombe parce qu'une de ses sources annexes
    repondait ainsi. Les fixer ici documente ce que le client doit savoir
    encaisser.
    """

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Refus", code="ER")
        AcademicYear.objects.create(
            name="2025-2026 ER",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.comptes = {}
        for role in (
            UserRole.CENSOR,
            UserRole.ACCOUNTANT,
            UserRole.SUPERVISOR,
            UserRole.TEACHER,
            UserRole.PARENT,
            UserRole.STUDENT,
        ):
            cls.comptes[role] = User.objects.create_user(
                username=f"refus_{role}",
                password="Pass1234!",
                role=role,
                etablissement=cls.etablissement,
            )

    def _statut(self, role, route):
        self.client.force_authenticate(self.comptes[role])
        return self.client.get(
            route, HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        ).status_code

    def test_l_enseignant_et_le_surveillant_n_ont_pas_le_personnel(self):
        for role in (UserRole.TEACHER, UserRole.SUPERVISOR):
            with self.subTest(role=role):
                self.assertEqual(
                    self._statut(role, "/api/teachers/"), status.HTTP_403_FORBIDDEN
                )

    def test_la_famille_n_a_pas_le_referentiel(self):
        for role in (UserRole.PARENT, UserRole.STUDENT):
            for route in ("/api/classrooms/", "/api/academic-years/", "/api/subjects/"):
                with self.subTest(role=role, route=route):
                    self.assertEqual(
                        self._statut(role, route), status.HTTP_403_FORBIDDEN
                    )

    def test_le_censeur_et_l_enseignant_n_ont_pas_les_encaissements(self):
        for role in (UserRole.CENSOR, UserRole.SUPERVISOR, UserRole.TEACHER):
            with self.subTest(role=role):
                self.assertEqual(
                    self._statut(role, "/api/payments/"), status.HTTP_403_FORBIDDEN
                )

    def test_le_comptable_n_a_plus_les_absences(self):
        self.assertEqual(
            self._statut(UserRole.ACCOUNTANT, "/api/attendances/"),
            status.HTTP_403_FORBIDDEN,
        )

    def test_le_comptable_garde_le_referentiel(self):
        # Ouvert a la decision F: sans lui, « Gestion des eleves » ne rendait
        # que son message d'erreur.
        for route in ("/api/classrooms/", "/api/academic-years/"):
            with self.subTest(route=route):
                self.assertEqual(
                    self._statut(UserRole.ACCOUNTANT, route), status.HTTP_200_OK
                )
