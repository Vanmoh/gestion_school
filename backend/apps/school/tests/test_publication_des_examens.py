"""La publication des résultats d'examen.

Les notes étaient visibles dès la saisie: un élève rafraîchissait son écran
pendant la correction et lisait une note avant que le jury ne l'ait arrêtée.
Une note corrigée ensuite — erreur de report, copie retrouvée — avait déjà
circulé dans la cour.

Le cahier des charges demandait une « publication des résultats » au module
Examens; c'est ce geste qui manquait.
"""

from datetime import date, timedelta
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamResult,
    ExamSession,
    ParentProfile,
    Student,
    Subject,
)


class PublicationDesExamensTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee des Examens")
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.classe = ClassRoom.objects.create(
            name="Terminale", academic_year=self.annee, etablissement=self.etablissement
        )
        self.matiere = Subject.objects.create(name="Maths", coefficient=Decimal("4"))

        self.directeur = User.objects.create_user(
            username="directeur_examens",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_examens",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        parent_user = User.objects.create_user(
            username="parent_examens",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        self.parent = ParentProfile.objects.create(user=parent_user)
        self.eleve = Student.objects.create(
            user=eleve_user,
            matricule="E001",
            classroom=self.classe,
            etablissement=self.etablissement,
            parent=self.parent,
        )

        self.session = ExamSession.objects.create(
            title="Composition du 1er trimestre",
            term="T1",
            academic_year=self.annee,
            start_date=date(2026, 1, 12),
            end_date=date(2026, 1, 16),
        )
        self.resultat = ExamResult.objects.create(
            session=self.session,
            student=self.eleve,
            subject=self.matiere,
            score=Decimal("14"),
        )

    def _resultats_vus_par(self, utilisateur):
        self.client.force_authenticate(utilisateur)
        reponse = self.client.get("/api/exam-results/")
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        return reponse.data["count"]

    # ----- ce que voient les familles -----------------------------------

    def test_avant_publication_l_eleve_ne_voit_rien(self):
        self.assertEqual(self._resultats_vus_par(self.eleve.user), 0)

    def test_avant_publication_le_parent_ne_voit_rien(self):
        self.assertEqual(self._resultats_vus_par(self.parent.user), 0)

    def test_la_direction_voit_les_notes_avant_publication(self):
        """La saisie et la relecture doivent rester possibles à couvert."""
        self.assertEqual(self._resultats_vus_par(self.directeur), 1)

    def test_apres_publication_l_eleve_voit_sa_note(self):
        self.session.publier_les_resultats(user=self.directeur)

        self.assertEqual(self._resultats_vus_par(self.eleve.user), 1)

    def test_apres_publication_le_parent_voit_la_note_de_son_enfant(self):
        self.session.publier_les_resultats(user=self.directeur)

        self.assertEqual(self._resultats_vus_par(self.parent.user), 1)

    def test_depublier_referme_l_acces(self):
        """Une note publiée par erreur doit pouvoir être retirée."""
        self.session.publier_les_resultats(user=self.directeur)
        self.session.depublier_les_resultats()

        self.assertEqual(self._resultats_vus_par(self.eleve.user), 0)

    # ----- l'API de publication -----------------------------------------

    def test_la_direction_publie(self):
        self.client.force_authenticate(self.directeur)

        reponse = self.client.post(f"/api/exam-sessions/{self.session.id}/publier/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.session.refresh_from_db()
        self.assertTrue(self.session.results_published)
        self.assertEqual(self.session.results_published_by, self.directeur)
        self.assertIsNotNone(self.session.results_published_at)

    def test_publier_une_session_sans_note_est_refuse(self):
        """Publier le vide ferait chercher aux familles ce qui n'existe pas."""
        vide = ExamSession.objects.create(
            title="Session vide",
            term="T2",
            academic_year=self.annee,
            start_date=date(2026, 3, 2),
            end_date=date(2026, 3, 6),
        )
        self.client.force_authenticate(self.directeur)

        reponse = self.client.post(f"/api/exam-sessions/{vide.id}/publier/")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        vide.refresh_from_db()
        self.assertFalse(vide.results_published)

    def test_l_eleve_ne_peut_pas_publier(self):
        self.client.force_authenticate(self.eleve.user)

        reponse = self.client.post(f"/api/exam-sessions/{self.session.id}/publier/")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.session.refresh_from_db()
        self.assertFalse(self.session.results_published)

    def test_depublier_par_l_api(self):
        self.session.publier_les_resultats(user=self.directeur)
        self.client.force_authenticate(self.directeur)

        reponse = self.client.post(f"/api/exam-sessions/{self.session.id}/depublier/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.session.refresh_from_db()
        self.assertFalse(self.session.results_published)

    def test_depublier_garde_la_trace_de_la_premiere_publication(self):
        """C'est elle qui explique pourquoi une famille a vu passer un chiffre."""
        self.session.publier_les_resultats(user=self.directeur)
        self.session.depublier_les_resultats()

        self.session.refresh_from_db()
        self.assertEqual(self.session.results_published_by, self.directeur)
        self.assertIsNotNone(self.session.results_published_at)

    def test_le_champ_ne_s_ecrit_pas_directement(self):
        """La publication passe par l'action, qui journalise et vérifie."""
        self.client.force_authenticate(self.directeur)

        reponse = self.client.patch(
            f"/api/exam-sessions/{self.session.id}/",
            {"results_published": True},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.session.refresh_from_db()
        self.assertFalse(self.session.results_published)

    def test_la_session_annonce_combien_de_notes_elle_porte(self):
        self.client.force_authenticate(self.directeur)

        reponse = self.client.get(f"/api/exam-sessions/{self.session.id}/")

        self.assertEqual(reponse.data["resultats_saisis"], 1)

    def test_les_sessions_se_filtrent_sur_leur_publication(self):
        self.session.publier_les_resultats(user=self.directeur)
        ExamSession.objects.create(
            title="Session fermee",
            term="T2",
            academic_year=self.annee,
            start_date=date(2026, 3, 2),
            end_date=date(2026, 3, 6),
        )
        self.client.force_authenticate(self.directeur)

        reponse = self.client.get("/api/exam-sessions/?results_published=true")

        self.assertEqual(reponse.data["count"], 1)


class RepriseDesSessionsPasseesTests(APITestCase):
    """Les sessions terminées avant la migration restent visibles.

    Les refermer retirerait aux familles ce qu'elles consultaient hier. Le
    critère retenu est la date de fin: une session terminée a de fait déjà
    rendu ses notes publiques.
    """

    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Repris")
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            etablissement=self.etablissement,
        )

    def _session(self, titre, fin):
        return ExamSession.objects.create(
            title=titre,
            term="T1",
            academic_year=self.annee,
            start_date=fin - timedelta(days=4),
            end_date=fin,
        )

    def _rejouer_la_reprise(self):
        """Appelle la fonction de la migration sur le registre réel."""
        import importlib

        from django.apps import apps as registre

        module = importlib.import_module(
            "apps.school.migrations.0059_publication_des_resultats_d_examen"
        )
        module.publier_les_sessions_terminees(registre, None)

    def test_une_session_terminee_est_publiee(self):
        passee = self._session("Passée", date.today() - timedelta(days=10))

        self._rejouer_la_reprise()

        passee.refresh_from_db()
        self.assertTrue(passee.results_published)

    def test_une_session_a_venir_reste_fermee(self):
        """C'est exactement le cas que la publication vient couvrir."""
        future = self._session("À venir", date.today() + timedelta(days=10))

        self._rejouer_la_reprise()

        future.refresh_from_db()
        self.assertFalse(future.results_published)
