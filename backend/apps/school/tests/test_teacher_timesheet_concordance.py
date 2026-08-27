"""La concordance entre l'emploi du temps et l'emargement enseignant.

Les deux modules vivaient cote a cote sans se regarder. Le pointage devinait
bien un creneau pour calculer les heures, mais il n'en gardait aucune trace,
n'en retenait qu'un seul par journee, et rien ne signalait une seance que
personne n'avait assuree.
"""

from datetime import date, time, timedelta
from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Notification,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherPayroll,
    TeacherScheduleSlot,
    TeacherTimeEntry,
)

DAY_CODES = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


class _EmploiDuTempsMixin:
    """Un enseignant, ses cours, et de quoi pointer dessus."""

    @classmethod
    def _decor(cls, nom_ecole="Etab Concordance", tolerance=15):
        cls.etablissement = Etablissement.objects.create(
            name=nom_ecole, timesheet_late_tolerance_minutes=tolerance
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.maths = Subject.objects.create(
            name="Mathematiques", code="MAT", coefficient=1, classroom=cls.classe
        )
        cls.physique = Subject.objects.create(
            name="Physique", code="PHY", coefficient=1, classroom=cls.classe
        )
        cls.enseignant = cls._enseignant("prof_concordance")
        cls.direction = User.objects.create_user(
            username="dir_concordance",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _enseignant(cls, username):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
        )
        return Teacher.objects.create(
            user=user,
            employee_code=username.upper(),
            hire_date=date(2025, 9, 1),
            hourly_rate=Decimal("1000.00"),
            etablissement=cls.etablissement,
        )

    @classmethod
    def _creneau(cls, enseignant, matiere, jour, debut, fin):
        affectation, _ = TeacherAssignment.objects.get_or_create(
            teacher=enseignant, subject=matiere, classroom=cls.classe
        )
        return TeacherScheduleSlot.objects.create(
            assignment=affectation,
            day_of_week=jour,
            start_time=debut,
            end_time=fin,
        )

    @staticmethod
    def _un_lundi():
        """Un lundi de l'annee scolaire, jamais « aujourd'hui ».

        Un test cale sur la date du jour tombe un dimanche une semaine sur
        sept, et le pointage y est interdit.
        """
        return date(2026, 1, 5)


class CouvertureMultiCreneauxTests(_EmploiDuTempsMixin, APITestCase):
    """Le defaut le plus couteux: une journee ne comptait qu'un seul cours."""

    @classmethod
    def setUpTestData(cls):
        cls._decor()
        cls.lundi = cls._un_lundi()
        cls.matin = cls._creneau(
            cls.enseignant, cls.maths, "MON", time(8, 0), time(10, 0)
        )
        cls.apres_midi = cls._creneau(
            cls.enseignant, cls.physique, "MON", time(14, 0), time(16, 0)
        )

    def _pointer(self, debut, fin, **extra):
        return TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=debut,
            check_out_time=fin,
            **extra,
        )

    def test_deux_cours_dans_la_journee_sont_tous_les_deux_payes(self):
        """8h-10h puis 14h-16h: quatre heures, pas deux."""
        pointage = self._pointer(time(8, 0), time(16, 0))

        self.assertEqual(pointage.worked_hours, Decimal("4.00"))
        self.assertEqual(pointage.slot_coverages.count(), 2)

    def test_le_trou_entre_deux_cours_n_est_pas_paye(self):
        """La pause de midi est dans la presence, pas dans le planning."""
        pointage = self._pointer(time(8, 0), time(16, 0))

        # Huit heures de presence, quatre heures de cours.
        self.assertEqual(pointage.covered_minutes, 240)
        self.assertEqual(pointage.planned_minutes, 240)

    def test_un_seul_cours_assure_ne_paie_que_celui_la(self):
        pointage = self._pointer(time(8, 0), time(10, 0))

        self.assertEqual(pointage.worked_hours, Decimal("2.00"))
        self.assertEqual(
            [couverture.schedule_slot_id for couverture in pointage.slot_coverages.all()],
            [self.matin.id],
        )

    def test_chaque_couverture_nomme_son_cours(self):
        pointage = self._pointer(time(8, 0), time(16, 0))

        couvertures = list(pointage.slot_coverages.select_related(
            "schedule_slot__assignment__subject"
        ))
        matieres = [
            couverture.schedule_slot.assignment.subject.name for couverture in couvertures
        ]
        self.assertEqual(matieres, ["Mathematiques", "Physique"])

    def test_un_depart_anticipe_ne_paie_que_ce_qui_a_ete_fait(self):
        pointage = self._pointer(time(8, 0), time(9, 0))

        self.assertEqual(pointage.worked_hours, Decimal("1.00"))
        couverture = pointage.slot_coverages.get()
        self.assertFalse(couverture.est_complete)

    def test_arriver_avant_l_heure_ne_paie_pas_l_avance(self):
        """Le planning fait foi: une heure d'avance n'est pas un cours."""
        pointage = self._pointer(time(7, 0), time(10, 0))

        self.assertEqual(pointage.worked_hours, Decimal("2.00"))

    def test_rester_apres_la_fin_ne_paie_pas_le_supplement(self):
        pointage = self._pointer(time(8, 0), time(11, 0))

        self.assertEqual(pointage.worked_hours, Decimal("2.00"))

    def test_un_retard_dans_la_tolerance_ne_coute_pas_l_heure(self):
        """Dix minutes de retard, tolerance a quinze: le cours est du entier."""
        pointage = self._pointer(time(8, 10), time(10, 0))

        self.assertEqual(pointage.worked_hours, Decimal("2.00"))
        self.assertEqual(pointage.late_minutes, 10)
        self.assertEqual(pointage.tolerated_late_minutes, 10)

    def test_un_retard_au_dela_de_la_tolerance_est_retenu(self):
        pointage = self._pointer(time(8, 30), time(10, 0))

        # 90 minutes faites, 15 rendues par la tolerance.
        self.assertEqual(pointage.worked_hours, Decimal("1.75"))
        self.assertEqual(pointage.late_minutes, 30)

    def test_le_retard_retenu_est_celui_du_premier_cours(self):
        pointage = self._pointer(time(8, 20), time(16, 0))

        self.assertEqual(pointage.late_minutes, 20)

    def test_corriger_l_emploi_du_temps_reecrit_la_couverture(self):
        """Un creneau retire ne doit pas laisser sa ligne derriere lui."""
        pointage = self._pointer(time(8, 0), time(16, 0))
        self.assertEqual(pointage.slot_coverages.count(), 2)

        self.apres_midi.delete()
        pointage.save()

        self.assertEqual(pointage.slot_coverages.count(), 1)
        self.assertEqual(pointage.worked_hours, Decimal("2.00"))


class ToleranceParEtablissementTests(_EmploiDuTempsMixin, APITestCase):
    """La tolerance etait figee a quinze minutes pour toute la plateforme."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom_ecole="Etab Tolerant", tolerance=30)
        cls.lundi = cls._un_lundi()
        cls._creneau(cls.enseignant, cls.maths, "MON", time(8, 0), time(10, 0))

    def test_l_ecole_tolerante_ne_retient_pas_le_retard_qu_elle_accepte(self):
        pointage = TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=time(8, 25),
            check_out_time=time(10, 0),
        )

        # 95 minutes faites, 25 rendues: le cours entier est du.
        self.assertEqual(pointage.worked_hours, Decimal("2.00"))
        self.assertEqual(pointage.late_minutes, 25)
        self.assertEqual(pointage.tolerated_late_minutes, 25)


class GelApresValidationTests(_EmploiDuTempsMixin, APITestCase):
    """Une paie signee ne bouge plus, meme si l'emploi du temps change."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom_ecole="Etab Gel")
        cls.lundi = cls._un_lundi()
        cls.creneau = cls._creneau(
            cls.enseignant, cls.maths, "MON", time(8, 0), time(10, 0)
        )

    def test_les_heures_ne_changent_plus_apres_validation_de_niveau_deux(self):
        pointage = TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=time(8, 0),
            check_out_time=time(10, 0),
        )
        self.assertEqual(pointage.worked_hours, Decimal("2.00"))

        TeacherPayroll.objects.create(
            teacher=self.enseignant,
            month=self.lundi.replace(day=1),
            hours_worked=Decimal("2.00"),
            hourly_rate=Decimal("1000.00"),
            amount=Decimal("2000.00"),
            level_two_validated_at=timezone.now(),
            level_two_validated_by=self.direction,
        )

        # L'administration corrige l'emploi du temps deux mois plus tard.
        self.creneau.end_time = time(12, 0)
        self.creneau.save()
        pointage.save()

        pointage.refresh_from_db()
        self.assertEqual(pointage.worked_hours, Decimal("2.00"))

    def test_un_mois_non_valide_suit_la_correction(self):
        pointage = TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=time(8, 0),
            check_out_time=time(12, 0),
        )
        self.assertEqual(pointage.worked_hours, Decimal("2.00"))

        self.creneau.end_time = time(12, 0)
        self.creneau.save()
        pointage.save()

        pointage.refresh_from_db()
        self.assertEqual(pointage.worked_hours, Decimal("4.00"))


class PointageHorsPlanningTests(_EmploiDuTempsMixin, APITestCase):
    """Un remplacement est legitime, mais il doit dire son nom."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom_ecole="Etab Hors Planning")
        cls.lundi = cls._un_lundi()
        cls._creneau(cls.enseignant, cls.maths, "MON", time(8, 0), time(10, 0))

    def _poster(self, **charge):
        self.client.force_authenticate(self.direction)
        donnees = {
            "teacher": self.enseignant.id,
            "entry_date": self.lundi.isoformat(),
            "check_in_time": "08:00",
            "check_out_time": "10:00",
        }
        donnees.update(charge)
        return self.client.post(
            "/api/teacher-time-entries/",
            donnees,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_un_pointage_sur_un_cours_planifie_passe_sans_motif(self):
        reponse = self._poster()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertFalse(reponse.data["is_off_schedule"])

    def test_un_pointage_apres_tous_les_cours_exige_un_motif(self):
        reponse = self._poster(check_in_time="15:00", check_out_time="17:00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("off_schedule_reason", reponse.data)

    def test_le_motif_donne_debloque_le_pointage_hors_cours(self):
        reponse = self._poster(
            check_in_time="15:00",
            check_out_time="17:00",
            off_schedule_reason="Réunion pédagogique",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertTrue(reponse.data["is_off_schedule"])
        # Hors planning, c'est la presence reelle qui fait foi: il n'y a
        # aucun cours auquel la comparer.
        self.assertEqual(Decimal(reponse.data["worked_hours"]), Decimal("2.00"))

    def test_un_jour_sans_aucun_cours_exige_aussi_un_motif(self):
        mardi = self.lundi + timedelta(days=1)

        reponse = self._poster(entry_date=mardi.isoformat())

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("off_schedule_reason", reponse.data)

    def test_le_dimanche_reste_interdit_meme_avec_un_motif(self):
        dimanche = self.lundi - timedelta(days=1)

        reponse = self._poster(
            entry_date=dimanche.isoformat(), off_schedule_reason="Rattrapage"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("entry_date", reponse.data)

    def test_la_ligne_de_pointage_nomme_les_cours_couverts(self):
        """Le tableau n'affichait qu'un nombre d'heures, sans dire lesquelles."""
        creation = self._poster()

        couvertures = creation.data["slot_coverages"]
        self.assertEqual(len(couvertures), 1)
        self.assertEqual(couvertures[0]["subject_name"], "Mathematiques")
        self.assertEqual(couvertures[0]["classroom_name"], "6A")
        self.assertTrue(couvertures[0]["is_complete"])


class ConcordanceApiTests(_EmploiDuTempsMixin, APITestCase):
    """L'ecart entre ce qui devait etre assure et ce qui l'a ete."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom_ecole="Etab Rapprochement")
        cls.lundi = cls._un_lundi()
        cls.matin = cls._creneau(
            cls.enseignant, cls.maths, "MON", time(8, 0), time(10, 0)
        )
        cls.apres_midi = cls._creneau(
            cls.enseignant, cls.physique, "MON", time(14, 0), time(16, 0)
        )

    def _concordance(self, **params):
        self.client.force_authenticate(self.direction)
        return self.client.get(
            "/api/teacher-time-entries/concordance/",
            {"from": self.lundi.isoformat(), "to": self.lundi.isoformat(), **params},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def _pointer(self, debut, fin, **extra):
        return TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=debut,
            check_out_time=fin,
            **extra,
        )

    def test_sans_aucun_pointage_les_deux_seances_sont_manquees(self):
        reponse = self._concordance()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        totaux = reponse.data["totals"]
        self.assertEqual(totaux["sessions_planned"], 2)
        self.assertEqual(totaux["sessions_missed"], 2)
        self.assertEqual(totaux["sessions_assured"], 0)
        self.assertEqual(totaux["covered_minutes"], 0)
        self.assertEqual(totaux["gap_minutes"], 240)

    def test_l_enseignant_absent_apparait_quand_meme(self):
        """Sans pointage, il n'a aucune ligne: c'est pourtant lui qu'on cherche."""
        reponse = self._concordance()

        noms = [ligne["teacher"] for ligne in reponse.data["teachers"]]
        self.assertIn(self.enseignant.id, noms)

    def test_la_journee_complete_ne_laisse_aucun_ecart(self):
        self._pointer(time(8, 0), time(16, 0))

        totaux = self._concordance().data["totals"]

        self.assertEqual(totaux["sessions_assured"], 2)
        self.assertEqual(totaux["sessions_missed"], 0)
        self.assertEqual(totaux["gap_minutes"], 0)

    def test_le_cours_de_l_apres_midi_manquant_ressort(self):
        self._pointer(time(8, 0), time(10, 0))

        jour = self._concordance().data["teachers"][0]["days"][0]

        statuts = {seance["subject_name"]: seance["status"] for seance in jour["sessions"]}
        self.assertEqual(statuts, {"Mathematiques": "assured", "Physique": "missed"})

    def test_un_depart_anticipe_donne_une_seance_partielle(self):
        self._pointer(time(8, 0), time(9, 0))

        jour = self._concordance().data["teachers"][0]["days"][0]
        maths = next(s for s in jour["sessions"] if s["subject_name"] == "Mathematiques")

        self.assertEqual(maths["status"], "partial")
        self.assertEqual(maths["covered_minutes"], 60)
        self.assertEqual(maths["planned_minutes"], 120)

    def test_un_pointage_hors_planning_est_compte_a_part(self):
        self._pointer(time(17, 0), time(19, 0), off_schedule_reason="Conseil de classe")

        reponse = self._concordance().data

        self.assertEqual(reponse["totals"]["off_schedule_entries"], 1)
        entree = reponse["teachers"][0]["days"][0]["entries"][0]
        self.assertTrue(entree["is_off_schedule"])
        self.assertEqual(entree["off_schedule_reason"], "Conseil de classe")

    def test_une_periode_trop_large_est_refusee(self):
        reponse = self._concordance(to=(self.lundi + timedelta(days=120)).isoformat())

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_fin_avant_le_debut_est_refusee(self):
        reponse = self._concordance(to=(self.lundi - timedelta(days=3)).isoformat())

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_enseignant_ne_voit_que_sa_propre_concordance(self):
        collegue = self._enseignant("prof_voisin")
        self._creneau(collegue, self.maths, "MON", time(10, 0), time(12, 0))

        self.client.force_authenticate(self.enseignant.user)
        reponse = self.client.get(
            "/api/teacher-time-entries/concordance/",
            {"from": self.lundi.isoformat(), "to": self.lundi.isoformat()},
        )

        identifiants = [ligne["teacher"] for ligne in reponse.data["teachers"]]
        self.assertEqual(identifiants, [self.enseignant.id])

    def test_une_autre_ecole_ne_figure_pas_au_rapprochement(self):
        autre = Etablissement.objects.create(name="Ecole voisine")
        user = User.objects.create_user(
            username="prof_ailleurs",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=autre,
        )
        Teacher.objects.create(
            user=user,
            employee_code="AILLEURS",
            hire_date=date(2025, 9, 1),
            hourly_rate=Decimal("1000.00"),
            etablissement=autre,
        )

        reponse = self._concordance()

        identifiants = [ligne["teacher"] for ligne in reponse.data["teachers"]]
        self.assertEqual(identifiants, [self.enseignant.id])

    def test_le_filtre_par_enseignant_isole_sa_ligne(self):
        collegue = self._enseignant("prof_filtre")
        self._creneau(collegue, self.maths, "MON", time(10, 0), time(12, 0))

        reponse = self._concordance(teacher=collegue.id)

        identifiants = [ligne["teacher"] for ligne in reponse.data["teachers"]]
        self.assertEqual(identifiants, [collegue.id])

    def test_les_ecarts_les_plus_lourds_arrivent_en_tete(self):
        collegue = self._enseignant("prof_assidu")
        self._creneau(collegue, self.maths, "MON", time(10, 0), time(12, 0))
        TeacherTimeEntry.objects.create(
            teacher=collegue,
            entry_date=self.lundi,
            check_in_time=time(10, 0),
            check_out_time=time(12, 0),
        )

        lignes = self._concordance().data["teachers"]

        # L'enseignant aux deux seances manquees passe devant celui qui a
        # tout assure: c'est ce qu'on ouvre l'ecran pour voir.
        self.assertEqual(lignes[0]["teacher"], self.enseignant.id)
        self.assertEqual(lignes[0]["totals"]["sessions_missed"], 2)


class SignalementDesSeancesNonAssureesTests(_EmploiDuTempsMixin, APITestCase):
    """La direction apprend le lendemain qu'une classe est restee seule.

    L'ecart ne se voyait qu'en ouvrant l'ecran de rapprochement, c'est-a-dire
    en se doutant deja qu'il y avait quelque chose a voir.
    """

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom_ecole="Etab Signalement")
        cls.lundi = cls._un_lundi()
        cls.matin = cls._creneau(
            cls.enseignant, cls.maths, "MON", time(8, 0), time(10, 0)
        )
        cls.apres_midi = cls._creneau(
            cls.enseignant, cls.physique, "MON", time(14, 0), time(16, 0)
        )
        cls.censeur = User.objects.create_user(
            username="censeur_signalement",
            password="Pass1234!",
            role=UserRole.CENSOR,
            etablissement=cls.etablissement,
        )

    def _signaler(self, **options):
        sortie = StringIO()
        call_command(
            "signaler_seances_non_assurees",
            "--jour",
            self.lundi.isoformat(),
            stdout=sortie,
            **options,
        )
        return sortie.getvalue()

    def test_les_seances_manquees_sont_notifiees_a_la_direction(self):
        self._signaler()

        notifications = Notification.objects.filter(title="Séances non assurées")
        # Le super-administrateur et le censeur de l'ecole, une chacun.
        self.assertEqual(notifications.count(), 2)
        message = notifications.first().message
        self.assertIn("Mathematiques", message)
        self.assertIn("Physique", message)

    def test_un_seul_message_recapitule_toutes_les_seances(self):
        """Cinq cours manques ne font pas cinq alertes dans la meme boite."""
        self._signaler()

        pour_le_censeur = Notification.objects.filter(recipient=self.censeur)
        self.assertEqual(pour_le_censeur.count(), 1)
        self.assertIn("2 séance(s)", pour_le_censeur.get().message)

    def test_une_seance_assuree_ne_declenche_rien(self):
        TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=time(8, 0),
            check_out_time=time(16, 0),
        )

        sortie = self._signaler()

        self.assertIn("assurees", sortie)
        self.assertEqual(Notification.objects.count(), 0)

    def test_seule_la_seance_manquante_est_signalee(self):
        TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=time(8, 0),
            check_out_time=time(10, 0),
        )

        self._signaler()

        message = Notification.objects.first().message
        self.assertIn("Physique", message)
        self.assertNotIn("Mathematiques", message)

    def test_le_dry_run_ne_notifie_personne(self):
        sortie = self._signaler(dry_run=True)

        self.assertIn("dry-run", sortie)
        self.assertEqual(Notification.objects.count(), 0)

    def test_une_autre_ecole_n_est_pas_prevenue(self):
        autre = Etablissement.objects.create(name="Ecole non concernee")
        etranger = User.objects.create_user(
            username="dir_etranger",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=autre,
        )

        self._signaler()

        self.assertFalse(Notification.objects.filter(recipient=etranger).exists())


class SortieOublieeTests(_EmploiDuTempsMixin, APITestCase):
    """Ce qu'on paie quand personne n'a pointe la sortie."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom_ecole="Etab Sortie Oubliee")
        cls.lundi = cls._un_lundi()
        cls._creneau(cls.enseignant, cls.maths, "MON", time(8, 0), time(10, 0))
        cls._creneau(cls.enseignant, cls.physique, "MON", time(14, 0), time(16, 0))

    def test_la_sortie_oubliee_se_referme_sur_le_cours_du_matin(self):
        """Et non sur le dernier cours de la journee.

        Presumer que l'enseignant est reste jusqu'a 16h lui paierait quatre
        heures que rien n'atteste: il a pu partir a 10h.
        """
        pointage = TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=time(8, 0),
        )

        self.assertTrue(pointage.is_auto_closed)
        self.assertEqual(pointage.check_out_time, time(10, 0))
        self.assertEqual(pointage.worked_hours, Decimal("2.00"))

    def test_la_journee_reste_annoncee_entiere_au_planning(self):
        """Le cours de l'apres-midi compte comme prevu, meme non assure."""
        pointage = TeacherTimeEntry.objects.create(
            teacher=self.enseignant,
            entry_date=self.lundi,
            check_in_time=time(8, 0),
        )

        self.assertEqual(pointage.planned_minutes, 240)
        self.assertEqual(pointage.covered_minutes, 120)
