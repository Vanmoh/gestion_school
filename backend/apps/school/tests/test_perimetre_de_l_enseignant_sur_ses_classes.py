"""Un enseignant ne voit que les classes ou il enseigne.

`StudentViewSet.get_queryset` traite l'eleve et le parent, puis **l'enseignant
tombe dans la branche generale** et recoit toute l'ecole, comme un directeur.
Il n'y a aucune branche enseignant.

Mesure sur la base reelle, avec Aissata SIDIBE qui enseigne l'Atelier a deux
classes du Lycee Technique -- 11eme GM et 12eme GM, soit **60 eleves**:

| ce qu'elle obtient        | mesure            | son perimetre |
|---------------------------|-------------------|---------------|
| `/students/`              | **150 eleves**    | 60            |
| dossier d'une autre classe| **HTTP 200**      | refus         |
| `/teacher-payrolls/`      | **43 fiches**     | 2 (les siennes)|
| `/classrooms/`            | **5 classes**     | 2             |
| `/subjects/`              | **78 matieres**   | 1             |

La matrice classe pourtant `students` en `L*` et `payroll` en `L*` -- lecture
**restreinte**. L'etoile y est documentaire: c'est au code de l'appliquer. Le
plus grave est la paie: elle lit le salaire de ses vingt-deux collegues.

L'ecran le disait a sa facon: le selecteur de classes de « Mon emploi du
temps » restait vide, et les compteurs melangeaient ses chiffres (2
affectations) avec ceux du lycee (78 matieres, 5 classes, 60 horaires).
"""

from datetime import date, time
from decimal import Decimal

from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherPayroll,
    TeacherScheduleSlot,
)


class SocleDeDeuxEnseignants(TestCase):
    """Deux enseignants, quatre classes, et personne qui enseigne partout.

    Un socle a un seul enseignant ne verrait rien: s'il enseigne dans toutes
    les classes, « son perimetre » et « l'ecole » se confondent. C'est
    exactement ce qui a laisse le defaut vivre.
    """

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des périmètres", code="LDP"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )

        cls.sienne_a = cls._classe("11ème GM", 2)
        cls.sienne_b = cls._classe("12ème GM", 2)
        cls.autre_a = cls._classe("10ème CT", 3)
        cls.autre_b = cls._classe("11ème CG", 3)

        cls.prof = cls._enseignant("sidibe", "LDP-01")
        cls.collegue = cls._enseignant("traore", "LDP-02")

        for classe in (cls.sienne_a, cls.sienne_b):
            cls._affecter(cls.prof, classe, f"AT-{classe.name[:2]}")
        for classe in (cls.autre_a, cls.autre_b):
            cls._affecter(cls.collegue, classe, f"MA-{classe.name[:2]}")

        # Deux fiches de paie chacun: la sienne, et celle du collegue.
        for enseignant in (cls.prof, cls.collegue):
            for mois in (date(2025, 10, 1), date(2025, 11, 1)):
                TeacherPayroll.objects.create(
                    teacher=enseignant,
                    month=mois,
                    academic_year=cls.annee,
                    amount=Decimal("150000"),
                )

    @classmethod
    def _classe(cls, nom, nombre_eleves):
        classe = ClassRoom.objects.create(
            name=nom, academic_year=cls.annee, etablissement=cls.etablissement
        )
        for rang in range(nombre_eleves):
            compte = User.objects.create_user(
                username=f"ldp.{nom.replace(' ', '')}.{rang}",
                password="x",
                role=UserRole.STUDENT,
                etablissement=cls.etablissement,
            )
            Student.objects.create(
                user=compte,
                # Le nom entier et non ses quatre premieres lettres: « 11ème
                # GM » et « 11ème CG » donnaient le meme prefixe, donc le meme
                # matricule, et `Student.matricule` est unique.
                matricule=f"LDP{nom.replace(' ', '').replace('è', 'e')}{rang}",
                classroom=classe,
                etablissement=cls.etablissement,
            )
        return classe

    @classmethod
    def _enseignant(cls, suffixe, code):
        compte = User.objects.create_user(
            username=f"ldp.{suffixe}",
            password="x",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code=code,
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )

    @classmethod
    def _affecter(cls, enseignant, classe, code):
        matiere = Subject.objects.create(
            name="Atelier",
            code=code,
            coefficient=Decimal(2),
            classroom=classe,
        )
        affectation = TeacherAssignment.objects.create(
            teacher=enseignant, subject=matiere, classroom=classe
        )
        TeacherScheduleSlot.objects.create(
            assignment=affectation,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
        )
        return matiere

    def _lire(self, route, **params):
        client = APIClient()
        client.force_authenticate(user=self.prof.user)
        reponse = client.get(
            route,
            params,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
            HTTP_X_ACADEMIC_YEAR_ID=str(self.annee.id),
        )
        return reponse


class SesElevesEtPasCeuxDesAutresTests(SocleDeDeuxEnseignants):
    def test_la_liste_des_eleves_s_arrete_a_ses_classes(self):
        """150 pour 60: ce que l'ecran « Mes élèves » lui faisait imprimer."""
        reponse = self._lire("/api/students/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        # 4 eleves dans ses deux classes, 6 dans les deux autres.
        self.assertEqual(reponse.data["count"], 4)

    def test_le_dossier_d_un_eleve_d_une_autre_classe_est_refuse(self):
        """Il rendait 200, avec ses notes, ses absences et son parcours.

        C'est le cas le plus grave de la liste: non pas un comptage trop large,
        mais la fiche nominative d'un enfant qu'on n'a pas en charge.
        """
        etranger = Student.objects.filter(classroom=self.autre_a).first()

        reponse = self._lire(f"/api/students/{etranger.id}/dossier/")

        self.assertEqual(reponse.status_code, status.HTTP_404_NOT_FOUND)

    def test_le_dossier_d_un_de_ses_eleves_reste_ouvert(self):
        """La restriction ne doit pas l'empecher de faire son travail."""
        sien = Student.objects.filter(classroom=self.sienne_a).first()

        reponse = self._lire(f"/api/students/{sien.id}/dossier/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)

    def test_la_fiche_d_un_eleve_d_une_autre_classe_est_refusee(self):
        etranger = Student.objects.filter(classroom=self.autre_b).first()

        reponse = self._lire(f"/api/students/{etranger.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_404_NOT_FOUND)


class SesClassesEtSesMatieresTests(SocleDeDeuxEnseignants):
    def test_le_selecteur_de_classes_n_offre_que_les_siennes(self):
        """Et c'est ce qui remplit enfin le selecteur de son emploi du temps.

        Il restait vide: la page demandait les classes et n'en proposait
        aucune, alors que l'ecole en a quatre -- dont deux qui sont a elle.
        """
        reponse = self._lire("/api/classrooms/", page_size=50)

        noms = sorted(ligne["name"] for ligne in reponse.data["results"])
        self.assertEqual(noms, ["11ème GM", "12ème GM"])

    def test_les_matieres_s_arretent_aux_siennes(self):
        """78 matieres affichees pour une enseignante qui en tient une."""
        reponse = self._lire("/api/subjects/", page_size=50)

        self.assertEqual(reponse.data["count"], 2)

    def test_les_creneaux_sont_les_siens(self):
        reponse = self._lire("/api/teacher-schedule-slots/", page_size=50)

        self.assertEqual(reponse.data["count"], 2)


class SaPaieEtPasCelleDesCollegues(SocleDeDeuxEnseignants):
    """Le plus grave: elle lisait le salaire de ses vingt-deux collegues.

    La matrice classe `payroll` en `L*` pour un enseignant -- la sienne. Le
    code ne l'appliquait pas, et l'API rendait les quarante-trois fiches de
    l'ecole.
    """

    def test_elle_ne_voit_que_ses_propres_fiches(self):
        reponse = self._lire("/api/teacher-payrolls/", page_size=50)

        self.assertEqual(reponse.data["count"], 2)

    def test_aucune_fiche_d_un_collegue_ne_passe(self):
        reponse = self._lire("/api/teacher-payrolls/", page_size=50)

        enseignants = {ligne["teacher"] for ligne in reponse.data["results"]}
        self.assertEqual(enseignants, {self.prof.id})

    def test_la_fiche_d_un_collegue_est_refusee_en_direct(self):
        """Par identifiant aussi: la liste filtree ne suffit pas.

        Un filtre de liste qui n'est pas double d'un refus sur le detail laisse
        passer qui connait l'identifiant -- et ils se devinent.
        """
        du_collegue = TeacherPayroll.objects.filter(teacher=self.collegue).first()

        reponse = self._lire(f"/api/teacher-payrolls/{du_collegue.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_404_NOT_FOUND)


class LeDirecteurGardeSaVueDEnsembleTests(SocleDeDeuxEnseignants):
    """La restriction vise l'enseignant, et personne d'autre.

    Une correction de perimetre qui ampute aussi la direction remplace un
    defaut par un autre.
    """

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.direction = User.objects.create_user(
            username="ldp.dir",
            password="x",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def _lire_en_direction(self, route):
        client = APIClient()
        client.force_authenticate(user=self.direction)
        return client.get(
            route,
            {"page_size": 50},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
            HTTP_X_ACADEMIC_YEAR_ID=str(self.annee.id),
        )

    def test_la_direction_voit_tous_les_eleves(self):
        self.assertEqual(self._lire_en_direction("/api/students/").data["count"], 10)

    def test_la_direction_voit_toutes_les_classes(self):
        self.assertEqual(
            self._lire_en_direction("/api/classrooms/").data["count"], 4
        )

    def test_la_direction_voit_toutes_les_fiches_de_paie(self):
        self.assertEqual(
            self._lire_en_direction("/api/teacher-payrolls/").data["count"], 4
        )
