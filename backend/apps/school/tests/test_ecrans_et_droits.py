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
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ParentProfile,
    Student,
    StudentAcademicHistory,
    Subject,
    Teacher,
)


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


class ReferentielDeLaFamilleTests(APITestCase):
    """Ce que le parent et l'eleve lisent du referentiel scolaire.

    Il leur etait refuse entierement. Leurs quatre ecrans -- notes, examens,
    emploi du temps, frais -- commencent pourtant par charger les classes,
    les matieres et les annees scolaires: le parent voyait « Élèves 8 » puis
    « Classes 0 · Années 0 », des listes deroulantes vides et une « Année
    scolaire » non disponible sous un bandeau qui annoncait l'annee active.

    La lecture est desormais ouverte, et bornee: les classes et les matieres
    de ses enfants, pas celles de l'ecole.
    """

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Etab Famille", code="EF"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 EF",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe_de_l_enfant = ClassRoom.objects.create(
            name="6ème A",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        cls.classe_voisine = ClassRoom.objects.create(
            name="5ème B",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        cls.matiere_de_l_enfant = Subject.objects.create(
            name="Mathématiques",
            code="MATH",
            classroom=cls.classe_de_l_enfant,
        )
        cls.matiere_voisine = Subject.objects.create(
            name="Physique",
            code="PHY",
            classroom=cls.classe_voisine,
        )

        cls.compte_parent = User.objects.create_user(
            username="parent_ref",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=cls.etablissement,
        )
        cls.parent = ParentProfile.objects.create(
            user=cls.compte_parent, etablissement=cls.etablissement
        )
        cls.compte_eleve = User.objects.create_user(
            username="eleve_ref",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=cls.compte_eleve,
            matricule="EF-0001",
            classroom=cls.classe_de_l_enfant,
            parent=cls.parent,
            etablissement=cls.etablissement,
        )

    def _lire(self, compte, route):
        self.client.force_authenticate(compte)
        return self.client.get(
            route, HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )

    @staticmethod
    def _noms(reponse):
        donnees = reponse.data
        lignes = donnees["results"] if isinstance(donnees, dict) else donnees
        return {ligne["name"] for ligne in lignes}

    def test_la_famille_lit_le_referentiel(self):
        for compte in (self.compte_parent, self.compte_eleve):
            for route in (
                "/api/classrooms/",
                "/api/academic-years/",
                "/api/subjects/",
            ):
                with self.subTest(compte=compte.username, route=route):
                    self.assertEqual(
                        self._lire(compte, route).status_code, status.HTTP_200_OK
                    )

    def test_elle_ne_lit_que_les_classes_de_ses_enfants(self):
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                self.assertEqual(
                    self._noms(self._lire(compte, "/api/classrooms/")), {"6ème A"}
                )

    def test_elle_ne_lit_que_les_matieres_de_ses_enfants(self):
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                self.assertEqual(
                    self._noms(self._lire(compte, "/api/subjects/")),
                    {"Mathématiques"},
                )

    def test_les_annees_scolaires_restent_celles_de_l_ecole(self):
        """Le calendrier de l'etablissement, et non une donnee d'eleve.

        Le bulletin et l'historique se choisissent par annee, y compris
        celles ou l'enfant n'etait pas encore inscrit.
        """
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                self.assertIn(
                    "2025-2026 EF",
                    self._noms(self._lire(compte, "/api/academic-years/")),
                )

    def test_un_autre_etablissement_demande_dans_l_url_est_refuse(self):
        """La portee tient a qui est inscrit sous son nom, pas a l'URL.

        Le refus est ici anterieur a la lecture -- une garde de la vue le
        rend en 400 -- et c'est le bon ordre: mieux vaut refuser la question
        que rendre une liste vide dont personne ne saura si elle est vide
        parce que l'ecole n'a pas de classe ou parce qu'on n'y a pas droit.
        """
        autre = Etablissement.objects.create(name="Etab Voisin", code="EV")
        autre_annee = AcademicYear.objects.create(
            name="2025-2026 EV",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=autre,
        )
        ClassRoom.objects.create(
            name="Terminale D", academic_year=autre_annee, etablissement=autre
        )

        self.client.force_authenticate(self.compte_parent)
        reponse = self.client.get(f"/api/classrooms/?etablissement={autre.id}")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_la_classe_d_une_annee_passee_reste_lisible(self):
        """Rouvrir un ancien bulletin suppose de retrouver l'ancienne classe.

        La fiche de l'eleve ne porte que son inscription en cours: s'en
        tenir a elle vidait le selecteur des que la famille remontait d'une
        annee, et le bulletin restait introuvable.
        """
        annee_passee = AcademicYear.objects.create(
            name="2024-2025 EF",
            start_date=date(2024, 9, 1),
            end_date=date(2025, 7, 31),
            etablissement=self.etablissement,
            is_closed=True,
        )
        classe_passee = ClassRoom.objects.create(
            name="7ème C",
            academic_year=annee_passee,
            etablissement=self.etablissement,
        )
        StudentAcademicHistory.objects.create(
            student=self.eleve,
            academic_year=annee_passee,
            classroom=classe_passee,
        )

        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                self.assertEqual(
                    self._noms(self._lire(compte, "/api/classrooms/")),
                    {"6ème A", "7ème C"},
                )

    def test_un_parent_sans_enfant_rattache_ne_lit_aucune_classe(self):
        orphelin = User.objects.create_user(
            username="parent_sans_enfant",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        ParentProfile.objects.create(user=orphelin, etablissement=self.etablissement)

        self.assertEqual(self._noms(self._lire(orphelin, "/api/classrooms/")), set())
        self.assertEqual(self._noms(self._lire(orphelin, "/api/subjects/")), set())

    def test_les_ecrans_de_la_famille_chargent_leur_referentiel(self):
        """Les quatre ecrans nommes dans la matrice, et ce qu'ils demandent.

        Chacun charge son referentiel avant d'afficher quoi que ce soit. Un
        seul refus dans le lot et l'ecran rendait ses listes vides -- sans
        rien dire, parce que le client encaisse les 403 pour ne pas tomber.
        """
        ecrans = {
            "Notes de mes enfants": ("/api/classrooms/", "/api/subjects/", "/api/academic-years/"),
            "Examens de mes enfants": ("/api/classrooms/", "/api/subjects/", "/api/academic-years/"),
            "Emploi du temps de mes enfants": ("/api/classrooms/", "/api/subjects/"),
            "Frais de mes enfants": ("/api/classrooms/",),
        }
        for compte in (self.compte_parent, self.compte_eleve):
            for ecran, routes in ecrans.items():
                for route in routes:
                    with self.subTest(compte=compte.username, ecran=ecran, route=route):
                        self.assertEqual(
                            self._lire(compte, route).status_code,
                            status.HTTP_200_OK,
                        )

    def test_l_ouverture_s_arrete_au_referentiel(self):
        """Elle ne deborde pas sur le personnel ni sur l'administration.

        Le module academique tient trois ressources. Les autres refus de la
        famille restent les siens: c'est la borne de ce qu'on vient
        d'ouvrir.
        """
        for compte in (self.compte_parent, self.compte_eleve):
            for route in ("/api/teachers/", "/api/teacher-assignments/"):
                with self.subTest(compte=compte.username, route=route):
                    self.assertEqual(
                        self._lire(compte, route).status_code,
                        status.HTTP_403_FORBIDDEN,
                    )

    def test_la_famille_n_ecrit_pas_le_referentiel(self):
        """Lire n'est pas administrer: creer une classe lui reste ferme."""
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                self.client.force_authenticate(compte)
                reponse = self.client.post(
                    "/api/classrooms/",
                    {"name": "Classe pirate", "academic_year": self.annee.id},
                    HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
                )
                self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
