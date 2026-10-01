"""Une ligne datee trouve son annee, et un parcours garde les siennes.

Deux defauts opposes, le meme jour, sur la meme base reelle.

**Trop peu de rattachement.** Quatre modeles acceptent un `academic_year`
vide: absences, incidents, depenses, fiches de paie. Quarante-quatre lignes en
profitaient -- et une ligne sans annee est invisible des qu'un ecran choisit
une annee, puisque le filtre demande `academic_year=<annee>` et que `NULL` n'y
repond pas. Comme l'application envoie l'en-tete d'annee sur *toutes* ses
requetes, ces quarante-quatre lignes ne s'affichaient jamais. On ne pouvait
donc pas les corriger, faute de les voir.

**Trop de rattachement.** `StudentAcademicHistory` est le parcours d'un eleve:
plusieurs annees, par construction -- sa vue ordonne meme par
`-academic_year_id`. L'ecran « Dossier eleve » l'appelle sans preciser d'annee,
mais l'en-tete global en ajoutait une: le parcours se reduisait a l'annee
active. Sur IFP-OBK, 502 bilans sur 1 893 disparaissaient, et un redoublant ne
voyait plus d'ou il venait.

Un troisieme defaut s'est montre en cherchant les deux premiers: trois notes
d'examen reliaient un eleve a une session d'une **autre** ecole. Le filtre
d'etablissement passe par `student__etablissement`, celui de l'annee par
`session__academic_year`: chacun etait coherent, et la ligne se glissait entre
les deux.
"""

from datetime import date
from decimal import Decimal

from django.core.exceptions import ValidationError
from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    Attendance,
    ClassRoom,
    DisciplineIncident,
    Etablissement,
    ExamResult,
    ExamSession,
    Expense,
    Student,
    StudentAcademicHistory,
    Subject,
    Teacher,
    TeacherAttendance,
    TeacherPayroll,
    TeacherTimeEntry,
)
from apps.school.rattachement_a_l_annee import annee_de_la_date

from .test_perimetre_de_l_annee_scolaire import SocleDeDeuxAnnees


class RangerCeQuiEstDateTests(SocleDeDeuxAnnees):
    """Le rattachement se deduit de la date, sans passer par l'API.

    Volontairement en ecriture directe: `AttendanceViewSet` posait deja
    l'annee a la creation, mais cela ne couvre que l'API. Ce sont les commandes
    de peuplement, l'admin et les migrations qui ont produit les quarante-quatre
    orphelines, et elles ecrivent toutes par le modele.
    """

    def _un_eleve(self, classe):
        return Student.objects.filter(classroom=classe).order_by("id").first()

    def test_une_absence_de_cette_annee_y_est_rangee(self):
        absence = Attendance.objects.create(
            student=self._un_eleve(self.classe_courante),
            date=date(2025, 11, 12),
            is_absent=True,
        )
        self.assertEqual(absence.academic_year, self.cette_annee)

    def test_une_absence_de_l_annee_suivante_y_est_rangee(self):
        absence = Attendance.objects.create(
            student=self._un_eleve(self.classe_suivante),
            date=date(2026, 11, 12),
            is_absent=True,
        )
        self.assertEqual(absence.academic_year, self.annee_suivante)

    def test_une_absence_des_grandes_vacances_reste_sans_annee(self):
        """Aout n'appartient a aucune annee, et ce n'est pas une anomalie.

        Deviner serait pire: ranger cette ligne dans l'annee qui se termine ou
        dans celle qui commence fausserait un decompte d'assiduite sans jamais
        se signaler.
        """
        absence = Attendance.objects.create(
            student=self._un_eleve(self.classe_courante),
            date=date(2026, 8, 15),
            is_absent=True,
        )
        self.assertIsNone(absence.academic_year)

    def test_une_annee_deja_posee_n_est_pas_remplacee(self):
        """Le rattachement comble, il ne corrige pas.

        Une absence datee de novembre mais rattachee a la main a l'annee
        suivante est peut-etre une saisie volontaire de la direction. Ce n'est
        pas a un `pre_save` d'en decider.
        """
        absence = Attendance.objects.create(
            student=self._un_eleve(self.classe_courante),
            date=date(2025, 11, 12),
            academic_year=self.annee_suivante,
            is_absent=True,
        )
        self.assertEqual(absence.academic_year, self.annee_suivante)

    def test_un_incident_est_range_par_sa_date(self):
        incident = DisciplineIncident.objects.create(
            student=self._un_eleve(self.classe_courante),
            incident_date=date(2026, 1, 20),
            category="RETARD",
            description="Trois retards consécutifs.",
        )
        self.assertEqual(incident.academic_year, self.cette_annee)

    def test_une_depense_est_rangee_par_sa_date(self):
        depense = Expense.objects.create(
            label="Craie et registres",
            amount=Decimal("25000"),
            date=date(2025, 10, 3),
            category="FOURNITURES",
            etablissement=self.etablissement,
        )
        self.assertEqual(depense.academic_year, self.cette_annee)

    def test_une_fiche_de_paie_est_rangee_par_son_mois(self):
        paie = TeacherPayroll.objects.create(
            teacher=self.prof,
            month=date(2026, 2, 1),
            amount=Decimal("150000"),
        )
        self.assertEqual(paie.academic_year, self.cette_annee)

    def test_un_emargement_est_range_par_sa_date(self):
        """Le dernier modele date de la famille, et le plus tardif a l'avoir eu.

        Il n'avait aucun champ d'annee, et sa vue n'etait pas bornee: la liste
        rendait 1 593 emargements sur IFP-OBK -- 751 pour une annee, 842 pour
        l'autre -- quelle que soit l'annee demandee.
        """
        from datetime import time as heure

        emargement = TeacherTimeEntry.objects.create(
            teacher=self.prof,
            etablissement=self.etablissement,
            entry_date=date(2025, 11, 4),
            check_in_time=heure(7, 55),
        )
        self.assertEqual(emargement.academic_year, self.cette_annee)

    def test_un_emargement_de_la_rentree_non_ouverte_reste_sans_annee(self):
        """Septembre 2026 pour une ecole restee sur 2025-2026.

        1 180 lignes de la base reelle sont dans ce cas. Les ranger de force
        dans l'annee close serait plus faux que de les laisser en attente: le
        controle les signale, et l'ecole ouvre son annee.
        """
        from datetime import time as heure

        emargement = TeacherTimeEntry.objects.create(
            teacher=self.prof,
            etablissement=self.etablissement,
            entry_date=date(2026, 8, 20),
            check_in_time=heure(7, 55),
        )
        self.assertIsNone(emargement.academic_year)

    def test_un_pointage_d_enseignant_est_range_par_sa_date(self):
        """Aucune orpheline en base, et c'est justement le moment de brancher.

        Les quarante-quatre autres sont nees de la meme facilite: une colonne
        nullable qu'aucun chemin d'ecriture ne remplissait.
        """
        pointage = TeacherAttendance.objects.create(
            teacher=self.prof, date=date(2025, 10, 6)
        )
        self.assertEqual(pointage.academic_year, self.cette_annee)

    def test_une_paie_de_juillet_ne_force_aucune_annee(self):
        paie = TeacherPayroll.objects.create(
            teacher=self.prof,
            month=date(2026, 8, 1),
            amount=Decimal("150000"),
        )
        self.assertIsNone(paie.academic_year)


class AnneeDeLaDateTests(TestCase):
    """La fonction seule, sur les cas ou il n'y a rien a trouver."""

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="École A", code="ECA")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )

    def test_sans_etablissement_rien_n_est_devine(self):
        self.assertIsNone(annee_de_la_date(None, date(2025, 10, 1)))

    def test_sans_date_rien_n_est_devine(self):
        self.assertIsNone(annee_de_la_date(self.etablissement, None))

    def test_l_annee_d_une_autre_ecole_n_est_pas_retenue(self):
        """Le rattachement ne franchit pas la frontiere de l'ecole.

        C'est la garde la plus importante du module: une date de novembre
        existe dans les quatre etablissements, et prendre « la premiere annee
        qui couvre cette date » aurait range la depense d'une ecole dans
        l'annee d'une autre.
        """
        autre = Etablissement.objects.create(name="École B", code="ECB")
        self.assertIsNone(annee_de_la_date(autre, date(2025, 10, 1)))

    def test_les_bornes_sont_incluses(self):
        self.assertEqual(
            annee_de_la_date(self.etablissement, date(2025, 9, 1)), self.annee
        )
        self.assertEqual(
            annee_de_la_date(self.etablissement, date(2026, 7, 31)), self.annee
        )


class UnParcoursGardeToutesSesAnneesTests(SocleDeDeuxAnnees):
    """`/student-history/` traverse les annees, meme avec l'en-tete."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.eleve = Student.objects.filter(
            classroom=cls.classe_courante
        ).order_by("id").first()
        for annee, classe, rang in (
            (cls.cette_annee, cls.classe_courante, 3),
            (cls.annee_suivante, cls.classe_suivante, 1),
        ):
            StudentAcademicHistory.objects.create(
                student=cls.eleve,
                academic_year=annee,
                classroom=classe,
                average=Decimal("13.50"),
                rank=rang,
            )

    def _parcours(self, **entetes):
        client = APIClient()
        client.force_authenticate(user=self.direction)
        reponse = client.get(
            "/api/student-history/",
            {"student": self.eleve.id},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
            **entetes,
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        donnees = reponse.data
        lignes = donnees["results"] if isinstance(donnees, dict) else donnees
        return {ligne["academic_year"] for ligne in lignes}

    def test_les_deux_annees_sortent_malgre_l_en_tete(self):
        annees = self._parcours(HTTP_X_ACADEMIC_YEAR_ID=str(self.cette_annee.id))
        self.assertEqual(annees, {self.cette_annee.id, self.annee_suivante.id})

    def test_une_annee_demandee_explicitement_filtre_toujours(self):
        """L'exemption porte sur l'en-tete, pas sur `?academic_year=`.

        L'ecran qui veut une seule annee peut toujours la demander: c'est la
        restriction implicite qui tombe, pas la possibilite de filtrer.
        """
        client = APIClient()
        client.force_authenticate(user=self.direction)
        reponse = client.get(
            "/api/student-history/",
            {"student": self.eleve.id, "academic_year": self.cette_annee.id},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        donnees = reponse.data
        lignes = donnees["results"] if isinstance(donnees, dict) else donnees
        self.assertEqual(
            {ligne["academic_year"] for ligne in lignes}, {self.cette_annee.id}
        )


class UneNoteResteDansSonEtablissementTests(TestCase):
    """Un resultat d'examen relie un eleve a une session de son ecole."""

    @classmethod
    def setUpTestData(cls):
        cls.ecole_a, cls.annee_a, cls.eleve_a, cls.matiere_a = cls._ecole("A", "ECA")
        cls.ecole_b, cls.annee_b, cls.eleve_b, cls.matiere_b = cls._ecole("B", "ECB")
        cls.session_a = ExamSession.objects.create(
            title="Examen Blanc T1",
            term="T1",
            academic_year=cls.annee_a,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 5),
        )

    @classmethod
    def _ecole(cls, suffixe, code):
        etablissement = Etablissement.objects.create(
            name=f"École {suffixe}", code=code
        )
        annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=etablissement,
            is_active=True,
        )
        classe = ClassRoom.objects.create(
            name="6ème", academic_year=annee, etablissement=etablissement
        )
        matiere = Subject.objects.create(
            name="Mathématiques",
            code=f"MA-{code}",
            coefficient=Decimal(4),
            classroom=classe,
        )
        compte = User.objects.create_user(
            username=f"{code}.eleve",
            password="x",
            role=UserRole.STUDENT,
            etablissement=etablissement,
        )
        eleve = Student.objects.create(
            user=compte,
            matricule=f"{code}E0001",
            classroom=classe,
            etablissement=etablissement,
        )
        return etablissement, annee, eleve, matiere

    def test_une_note_sur_la_session_de_son_ecole_passe(self):
        note = ExamResult.objects.create(
            session=self.session_a,
            student=self.eleve_a,
            subject=self.matiere_a,
            score=Decimal("13.00"),
        )
        self.assertEqual(note.session, self.session_a)

    def test_une_note_sur_la_session_d_une_autre_ecole_est_refusee(self):
        with self.assertRaises(ValidationError) as leve:
            ExamResult.objects.create(
                session=self.session_a,
                student=self.eleve_b,
                subject=self.matiere_b,
                score=Decimal("18.00"),
            )
        self.assertIn("session", leve.exception.message_dict)
