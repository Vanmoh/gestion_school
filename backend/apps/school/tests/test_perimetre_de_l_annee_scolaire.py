"""Chaque liste ne rend que l'annee demandee.

`AnneeScolaireScopeMixin` existe depuis longtemps, et sa docstring explique
pourquoi il ne filtre que si l'ecran demande une annee: « la bascule arrive
ecran par ecran sans casser les autres ». C'etait un bon plan de transition.
Douze vues n'avaient jamais fait la bascule.

Le defaut ne se voit que le jour ou une ecole ouvre sa deuxieme annee -- et
IFP-OBK l'a fait. Son directeur lisait **611 eleves** pour 450 inscrits, **544
matieres** pour 297, et l'ecran des notes affichait ces chiffres sans que rien
n'indique qu'ils melangeaient deux annees. Ce n'est pas une fuite: tout
appartient a son ecole. C'est un comptage faux, ce qui est plus difficile a
reperer qu'une erreur.

Ces tests montent deux annees dans une ecole et verifient que chacune rend les
siennes. Un test sur une base a une seule annee ne peut rien voir: c'est
exactement pourquoi le defaut a vecu.
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
    TeacherScheduleSlot,
)


class SocleDeDeuxAnnees(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des deux années", code="LDEU"
        )
        cls.cette_annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.annee_suivante = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 7, 31),
            etablissement=cls.etablissement,
            is_active=False,
        )

        cls.prof = cls._enseignant()
        cls.classe_courante, cls.matiere_courante = cls._monter(
            cls.cette_annee, "10ème CT", "MA-25", nombre_eleves=3
        )
        cls.classe_suivante, cls.matiere_suivante = cls._monter(
            cls.annee_suivante, "11ème CT", "MA-26", nombre_eleves=2
        )

        cls.direction = User.objects.create_user(
            username="ldeu.dir",
            password="x",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _enseignant(cls):
        compte = User.objects.create_user(
            username="ldeu.prof",
            password="x",
            role=UserRole.TEACHER,
            first_name="Moussa",
            last_name="KEITA",
            etablissement=cls.etablissement,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code="LDEU-01",
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )

    @classmethod
    def _monter(cls, annee, nom_classe, code_matiere, nombre_eleves):
        classe = ClassRoom.objects.create(
            name=nom_classe, academic_year=annee, etablissement=cls.etablissement
        )
        matiere = Subject.objects.create(
            name="Mathématiques",
            code=code_matiere,
            coefficient=Decimal(4),
            classroom=classe,
        )
        affectation = TeacherAssignment.objects.create(
            teacher=cls.prof, subject=matiere, classroom=classe
        )
        TeacherScheduleSlot.objects.create(
            assignment=affectation,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
        )
        for rang in range(nombre_eleves):
            compte = User.objects.create_user(
                username=f"ldeu.{code_matiere}.{rang}",
                password="x",
                role=UserRole.STUDENT,
                first_name=f"Eleve{rang}",
                last_name="DIALLO",
                etablissement=cls.etablissement,
            )
            Student.objects.create(
                user=compte,
                matricule=f"{code_matiere}{rang}",
                classroom=classe,
                etablissement=cls.etablissement,
            )
        return classe, matiere

    def _compter(self, route, annee):
        client = APIClient()
        client.force_authenticate(user=self.direction)
        reponse = client.get(
            route,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
            HTTP_X_ACADEMIC_YEAR_ID=str(annee.id),
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        donnees = reponse.data
        if isinstance(donnees, dict) and "count" in donnees:
            return donnees["count"]
        return len(donnees.get("results", donnees) if isinstance(donnees, dict) else donnees)


class ChaqueAnneeRendLesSiennesTests(SocleDeDeuxAnnees):
    def test_les_eleves(self):
        """611 pour 450: le comptage faux qu'un directeur lisait a l'ecran."""
        self.assertEqual(self._compter("/api/students/", self.cette_annee), 3)
        self.assertEqual(self._compter("/api/students/", self.annee_suivante), 2)

    def test_les_matieres(self):
        self.assertEqual(self._compter("/api/subjects/", self.cette_annee), 1)
        self.assertEqual(self._compter("/api/subjects/", self.annee_suivante), 1)

    def test_les_affectations(self):
        self.assertEqual(
            self._compter("/api/teacher-assignments/", self.cette_annee), 1
        )
        self.assertEqual(
            self._compter("/api/teacher-assignments/", self.annee_suivante), 1
        )

    def test_les_creneaux_d_emploi_du_temps(self):
        self.assertEqual(
            self._compter("/api/teacher-schedule-slots/", self.cette_annee), 1
        )
        self.assertEqual(
            self._compter("/api/teacher-schedule-slots/", self.annee_suivante), 1
        )

    def test_les_classes(self):
        """Celle-ci filtrait deja: le test la garde."""
        self.assertEqual(self._compter("/api/classrooms/", self.cette_annee), 1)


class CeQuiNAPasEncoreDAnneeResteVisibleTests(SocleDeDeuxAnnees):
    """Un filtre brut aurait fait disparaitre ce qui n'est rattache a rien.

    `Student.classroom` et `Subject.classroom` sont nullables. Un eleve inscrit
    mais pas encore affecte n'appartient a aucune annee -- il n'est pas d'une
    autre, ce qui n'est pas la meme chose -- et il disparaitrait de la liste ou
    l'on vient justement l'affecter.
    """

    def test_un_eleve_sans_classe_reste_dans_la_liste(self):
        compte = User.objects.create_user(
            username="ldeu.attente",
            password="x",
            role=UserRole.STUDENT,
            first_name="Awa",
            last_name="SANOGO",
            etablissement=self.etablissement,
        )
        Student.objects.create(
            user=compte,
            matricule="LDEUATT",
            classroom=None,
            etablissement=self.etablissement,
        )

        self.assertEqual(self._compter("/api/students/", self.cette_annee), 4)

    def test_une_matiere_sans_classe_n_est_pas_ecartee_par_l_annee(self):
        """Mesure sur le super-admin, et la raison est instructive.

        `SubjectViewSet` rattache une matiere a son etablissement par sa classe,
        par une affectation ou par des notes. Une matiere qui n'a aucun des trois
        n'appartient a aucun etablissement, et le filtre d'etablissement -- qui
        est une autre regle, anterieure et volontaire -- la cache au directeur.

        Ce test mesure donc le filtre d'annee seul, aupres du seul compte que le
        filtre d'etablissement ne restreint pas. Si `academic_year_keep_orphans`
        disparaissait, la matiere tomberait ici aussi.
        """
        Subject.objects.create(
            name="Atelier", code="AT-LIBRE", coefficient=Decimal(2), classroom=None
        )
        super_admin = User.objects.create_user(
            username="ldeu.super", password="x", role=UserRole.SUPER_ADMIN
        )

        client = APIClient()
        client.force_authenticate(user=super_admin)
        reponse = client.get(
            "/api/subjects/", HTTP_X_ACADEMIC_YEAR_ID=str(self.cette_annee.id)
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        codes = {ligne["code"] for ligne in reponse.data["results"]}
        self.assertIn("AT-LIBRE", codes)
        self.assertIn("MA-25", codes)
        self.assertNotIn("MA-26", codes, "l'annee suivante ne doit pas sortir")


class SansEnTeteLAnneeActiveSAppliqueTests(SocleDeDeuxAnnees):
    """Le dernier trou du mixin, referme.

    Le filtre ne s'appliquait **que** si le client envoyait
    `X-Academic-Year-Id`. C'etait la regle de transition: « sans en-tete, la vue
    rend ce qu'elle rendait avant », pour que la bascule arrive ecran par ecran.

    La bascule est finie: les vingt-cinq vues portent le mixin. La permissivite,
    elle, etait restee -- et sans en-tete l'API rendait encore 611 eleves pour
    450 inscrits. L'application envoie l'en-tete, donc elle ne voyait rien; un
    export, un script, ou un ecran qui interroge avant que l'annee soit chargee
    le voyaient.

    Ce fichier affirmait l'ancienne regle. Il affirme maintenant la nouvelle:
    sans en-tete, l'annee active de l'etablissement s'applique.
    """

    def _compter_sans_annee(self, route, **entetes):
        client = APIClient()
        client.force_authenticate(user=self.direction)
        reponse = client.get(route, **entetes)
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data["count"]

    def test_sans_annee_demandee_l_annee_active_s_applique(self):
        compte = self._compter_sans_annee(
            "/api/students/", HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )

        # 3 eleves dans l'annee active, et non les 5 des deux annees.
        self.assertEqual(compte, 3)

    def test_l_en_tete_reste_prioritaire_sur_le_repli(self):
        """Choisir l'annee suivante doit encore marcher."""
        self.assertEqual(self._compter("/api/students/", self.annee_suivante), 2)

    def test_le_repli_prend_l_annee_de_cette_ecole_et_pas_d_une_autre(self):
        """`AcademicYear.courante(None)` rendrait l'annee de n'importe quelle ecole.

        Elle trie `filter(is_active=True)` par `-start_date`: l'ecole dont
        l'annee active commence le plus tard gagne. Une deuxieme ecole dont
        l'annee active est 2027-2028 suffit donc a detourner le repli -- et
        notre lycee, filtre sur une annee qui n'est pas la sienne, rendrait
        zero eleve la ou il en compte trois.

        C'est pourquoi le repli passe par `_resolve_target_etablissement()`.
        """
        voisine = Etablissement.objects.create(name="École voisine", code="EVO")
        AcademicYear.objects.create(
            name="2027-2028",
            start_date=date(2027, 9, 1),
            end_date=date(2028, 7, 31),
            etablissement=voisine,
            is_active=True,
        )

        compte = self._compter_sans_annee(
            "/api/students/", HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id)
        )

        self.assertEqual(compte, 3)


class UnAgregatCompteLAnneeQuIlNommeTests(SocleDeDeuxAnnees):
    """Les actions personnalisees ne passent pas par `filter_queryset`.

    C'est lui qui applique l'annee. Une action qui agrege sur
    `self.get_queryset()` la contourne donc en silence -- et un agregat faux ne
    se voit pas, contrairement a une liste ou l'on reconnait les intrus.
    """

    def _agregat(self, route, annee=None, **params):
        client = APIClient()
        client.force_authenticate(user=self.direction)
        entetes = {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}
        if annee is not None:
            entetes["HTTP_X_ACADEMIC_YEAR_ID"] = str(annee.id)
        reponse = client.get(route, params, **entetes)
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data

    def test_les_effectifs_comptent_l_annee_affichee(self):
        """La carte annoncait « 2025-2026 : 611 eleves » sur 450 inscrits.

        Le decompte ignorait l'annee tandis que l'etiquette l'affichait. Un
        chiffre faux portant le nom de la bonne annee trompe davantage qu'un
        chiffre sans etiquette: rien n'invite a le verifier.
        """
        courante = self._agregat("/api/students/stats/", self.cette_annee)
        self.assertEqual(courante["total"], 3)
        self.assertEqual(courante["academic_year"], self.cette_annee.name)

        suivante = self._agregat("/api/students/stats/", self.annee_suivante)
        self.assertEqual(suivante["total"], 2)
        self.assertEqual(suivante["academic_year"], self.annee_suivante.name)

    def test_la_charge_horaire_ne_cumule_pas_deux_annees(self):
        """Un enseignant present deux annees paraissait faire le double.

        C'est le chiffre sur lequel la direction arbitre les services, et notre
        enseignant unique tient une classe dans chacune des deux annees.
        """
        courante = self._agregat(
            "/api/teacher-schedule-slots/teacher_workload/", self.cette_annee
        )
        self.assertEqual(courante["teacher_count"], 1)
        self.assertEqual(courante["total_minutes"], 60)

        # Sans en-tete non plus: le repli sur l'annee active s'applique aussi
        # aux agregats, donc la charge ne cumule plus les deux annees.
        sans_annee = self._agregat("/api/teacher-schedule-slots/teacher_workload/")
        self.assertEqual(sans_annee["total_minutes"], 60)


class UnEleveNeDisparaitPasDUneAutreAnneeTests(SocleDeDeuxAnnees):
    """Le detail d'un eleve survit au changement d'annee.

    `Student.classroom` ne contient que la classe **actuelle**: un eleve promu
    de 6eme en 5eme n'a plus aucun lien avec l'annee passee. Le filtrer par
    l'annee choisie le faisait disparaitre -- et avec lui son dossier, qui est
    justement l'ecran qu'on ouvre pour regarder le passe. La direction lisait
    404 sur un eleve inscrit.
    """

    def _demander(self, eleve, annee):
        client = APIClient()
        client.force_authenticate(user=self.direction)
        return client.get(
            f"/api/students/{eleve.id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
            HTTP_X_ACADEMIC_YEAR_ID=str(annee.id),
        )

    def test_le_detail_reste_accessible_depuis_une_autre_annee(self):
        eleve = Student.objects.filter(
            classroom=self.classe_courante
        ).order_by("id").first()

        reponse = self._demander(eleve, self.annee_suivante)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertEqual(reponse.data["id"], eleve.id)

    def test_la_liste_reste_filtree_elle(self):
        """L'exemption porte sur le detail seul: c'est la liste qui comptait faux."""
        self.assertEqual(self._compter("/api/students/", self.annee_suivante), 2)
