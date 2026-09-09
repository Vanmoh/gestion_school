"""La génération d'un emploi du temps, de bout en bout.

Le module 11 du cahier des charges demande la « génération automatique ».
Elle n'existait pas: un établissement saisissait ses centaines de créneaux un
par un, en vérifiant de tête qu'aucun enseignant n'était attendu dans deux
classes à la fois — la détection de conflits n'intervenant qu'après coup, au
moment d'enregistrer.

L'algorithme lui-même est éprouvé hors base dans test_planification.py. Ce
qui suit vérifie ce que le serveur en fait: la portée, les droits, la
simulation qui n'écrit rien, et le remplacement.
"""

from datetime import date, time

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherAvailabilitySlot,
    TeacherScheduleSlot,
)


class GenerationEmploiDuTempsTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Planifie")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.classe = ClassRoom.objects.create(
            name="6A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.directeur = User.objects.create_user(
            username="directeur_edt",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.eleve = User.objects.create_user(
            username="eleve_edt",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(self.directeur)

    def _enseignant(self, nom):
        user = User.objects.create_user(
            username=f"ens_{nom}",
            password="Pass1234!",
            role=UserRole.TEACHER,
            first_name=nom,
            last_name="Test",
            etablissement=self.etablissement,
        )
        return Teacher.objects.create(
            user=user,
            etablissement=self.etablissement,
            employee_code=f"ENS-{nom[:6].upper()}",
            hire_date=date(2025, 9, 1),
        )

    def _matiere(self, nom, code, seances, classe=None):
        return Subject.objects.create(
            name=nom,
            code=code,
            coefficient=2,
            classroom=classe or self.classe,
            weekly_slots=seances,
        )

    def _affecter(self, enseignant, matiere, classe=None):
        return TeacherAssignment.objects.create(
            teacher=enseignant, subject=matiere, classroom=classe or self.classe
        )

    def _charge(self, **extra):
        donnees = {
            "classroom": self.classe.id,
            "days": ["MON", "TUE", "WED"],
            "start_time": "08:00",
            "end_time": "12:00",
            "slot_minutes": 60,
        }
        donnees.update(extra)
        return donnees

    # ----- simulation ---------------------------------------------------

    def test_la_simulation_n_ecrit_rien(self):
        """Un emploi du temps engage l'année: il se relit avant d'être posé."""
        self._affecter(self._enseignant("Awa"), self._matiere("Maths", "MAT", 3))

        reponse = self.client.post(
            "/api/teacher-schedule-slots/simuler/", self._charge(), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertFalse(reponse.data["applique"])
        self.assertEqual(reponse.data["placees"], 3)
        self.assertEqual(TeacherScheduleSlot.objects.count(), 0)

    def test_elle_annonce_ce_qui_ne_rentre_pas(self):
        # Une seule séance disponible dans la grille, trois demandées.
        self._affecter(self._enseignant("Awa"), self._matiere("Maths", "MAT", 3))

        reponse = self.client.post(
            "/api/teacher-schedule-slots/simuler/",
            self._charge(days=["MON"], start_time="08:00", end_time="09:00"),
            format="json",
        )

        self.assertEqual(reponse.data["placees"], 1)
        self.assertEqual(reponse.data["non_placees"], 2)
        self.assertIn("motif", reponse.data["echecs"][0])

    def test_le_rendu_nomme_la_matiere_et_la_classe(self):
        """Une liste d'identifiants ne se relit pas."""
        self._affecter(self._enseignant("Awa"), self._matiere("Maths", "MAT", 1))

        reponse = self.client.post(
            "/api/teacher-schedule-slots/simuler/", self._charge(), format="json"
        )

        placement = reponse.data["placements"][0]
        self.assertEqual(placement["subject"], "Maths")
        self.assertEqual(placement["classroom"], "6A")
        self.assertIn("Awa", placement["teacher"])

    # ----- generation ---------------------------------------------------

    def test_elle_enregistre_les_creneaux(self):
        self._affecter(self._enseignant("Awa"), self._matiere("Maths", "MAT", 3))

        reponse = self.client.post(
            "/api/teacher-schedule-slots/generer/", self._charge(), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertTrue(reponse.data["applique"])
        self.assertEqual(TeacherScheduleSlot.objects.count(), 3)

    def test_un_enseignant_n_est_jamais_dans_deux_classes_a_la_fois(self):
        """Le cœur du problème, sur des données réelles."""
        classe_b = ClassRoom.objects.create(
            name="6B", academic_year=self.annee, etablissement=self.etablissement
        )
        enseignant = self._enseignant("Awa")
        self._affecter(enseignant, self._matiere("Maths", "MAT", 4))
        self._affecter(
            enseignant,
            self._matiere("Maths B", "MATB", 4, classe=classe_b),
            classe=classe_b,
        )

        self.client.post(
            "/api/teacher-schedule-slots/generer/",
            self._charge(classroom=None),
            format="json",
        )

        creneaux = [
            (slot.day_of_week, slot.start_time)
            for slot in TeacherScheduleSlot.objects.filter(
                assignment__teacher=enseignant
            )
        ]
        self.assertEqual(len(creneaux), len(set(creneaux)))

    def test_elle_respecte_les_creneaux_deja_poses(self):
        """Une génération n'écrase pas ce qui a été saisi à la main."""
        enseignant = self._enseignant("Awa")
        affectation = self._affecter(enseignant, self._matiere("Maths", "MAT", 1))
        existant = TeacherScheduleSlot.objects.create(
            assignment=affectation,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
        )

        self.client.post(
            "/api/teacher-schedule-slots/generer/", self._charge(), format="json"
        )

        nouveaux = TeacherScheduleSlot.objects.exclude(id=existant.id)
        self.assertEqual(nouveaux.count(), 1)
        self.assertNotEqual(nouveaux.first().start_time, time(8, 0))

    def test_le_remplacement_efface_l_ancien_planning(self):
        enseignant = self._enseignant("Awa")
        affectation = self._affecter(enseignant, self._matiere("Maths", "MAT", 2))
        TeacherScheduleSlot.objects.create(
            assignment=affectation,
            day_of_week="WED",
            start_time=time(11, 0),
            end_time=time(12, 0),
        )

        self.client.post(
            "/api/teacher-schedule-slots/generer/",
            self._charge(replace=True),
            format="json",
        )

        self.assertEqual(TeacherScheduleSlot.objects.count(), 2)
        self.assertFalse(
            TeacherScheduleSlot.objects.filter(
                day_of_week="WED", start_time=time(11, 0)
            ).exists()
        )

    def test_une_indisponibilite_declaree_est_respectee(self):
        enseignant = self._enseignant("Awa")
        self._affecter(enseignant, self._matiere("Maths", "MAT", 1))
        TeacherAvailabilitySlot.objects.create(
            teacher=enseignant,
            etablissement=self.etablissement,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
            kind="unavailable",
        )

        self.client.post(
            "/api/teacher-schedule-slots/generer/", self._charge(), format="json"
        )

        pose = TeacherScheduleSlot.objects.get()
        self.assertNotEqual((pose.day_of_week, pose.start_time), ("MON", time(8, 0)))

    def test_un_placement_hors_disponibilite_porte_sa_raison(self):
        """L'administration arbitre, mais la raison est conservée."""
        enseignant = self._enseignant("Awa")
        self._affecter(enseignant, self._matiere("Maths", "MAT", 1))
        TeacherAvailabilitySlot.objects.create(
            teacher=enseignant,
            etablissement=self.etablissement,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
            kind="unavailable",
        )

        self.client.post(
            "/api/teacher-schedule-slots/generer/",
            self._charge(days=["MON"], start_time="08:00", end_time="09:00"),
            format="json",
        )

        pose = TeacherScheduleSlot.objects.get()
        self.assertIn("indisponible", pose.off_availability_reason)

    # ----- garde-fous -----------------------------------------------------

    def test_une_matiere_sans_volume_horaire_n_est_pas_placee(self):
        """Inventer un volume produirait un planning que personne n'a décidé."""
        self._affecter(self._enseignant("Awa"), self._matiere("Sport", "SPT", 0))

        reponse = self.client.post(
            "/api/teacher-schedule-slots/simuler/", self._charge(), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("séances hebdomadaires", str(reponse.data))

    def test_l_eleve_ne_peut_pas_generer(self):
        self._affecter(self._enseignant("Awa"), self._matiere("Maths", "MAT", 2))
        self.client.force_authenticate(self.eleve)

        reponse = self.client.post(
            "/api/teacher-schedule-slots/generer/", self._charge(), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(TeacherScheduleSlot.objects.count(), 0)

    def test_une_classe_d_un_autre_etablissement_est_refusee(self):
        annee_voisine = AcademicYear.objects.create(
            name="2025-2026 voisin",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            etablissement=self.autre,
        )
        classe_voisine = ClassRoom.objects.create(
            name="6A voisin", academic_year=annee_voisine, etablissement=self.autre
        )

        reponse = self.client.post(
            "/api/teacher-schedule-slots/simuler/",
            self._charge(classroom=classe_voisine.id),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_la_pause_meridienne_reste_libre(self):
        self._affecter(self._enseignant("Awa"), self._matiere("Maths", "MAT", 2))

        self.client.post(
            "/api/teacher-schedule-slots/generer/",
            self._charge(
                start_time="11:00",
                end_time="15:00",
                break_start="12:00",
                break_end="13:00",
            ),
            format="json",
        )

        heures = list(
            TeacherScheduleSlot.objects.values_list("start_time", flat=True)
        )
        self.assertNotIn(time(12, 0), heures)
