"""Une restauration va-t-elle jusqu'au bout ?

L'ecran la montre figee a quelques pour cent, sans jamais atteindre 100.
Ce test fait le trajet complet -- sauvegarde puis restauration -- et regarde
ou il s'arrete.
"""

import tempfile
from datetime import date
from pathlib import Path

from django.test import override_settings
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.common.models import BackupArchive
from apps.common.views import BackupArchiveViewSet
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class RestaurationBoutEnBoutTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Etab Restauration", code="ERST"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 rest",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.admin = User.objects.create_user(
            username="admin_restauration",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=cls.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_restauration",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=eleve_user,
            classroom=cls.classe,
            etablissement=cls.etablissement,
            gender="F",
        )

    def test_une_restauration_globale_atteint_cent_pour_cent(self):
        vue = BackupArchiveViewSet()

        with tempfile.TemporaryDirectory() as media:
            with override_settings(MEDIA_ROOT=media):
                sauvegarde = BackupArchive.objects.create(
                    scope=BackupArchive.Scope.GLOBAL,
                    created_by=self.admin,
                    include_media=False,
                    status=BackupArchive.Status.PENDING,
                )
                vue._build_archive(sauvegarde)
                sauvegarde.refresh_from_db()
                archive = Path(sauvegarde.file_path)
                self.addCleanup(lambda: archive.unlink(missing_ok=True))

                vue._restore_from_archive(sauvegarde, archive, actor=self.admin)

        ligne = BackupArchive.objects.filter(pk=sauvegarde.pk).first()
        self.assertIsNotNone(ligne, "La ligne de sauvegarde a disparu en cours de route.")
        self.assertEqual(ligne.restore_progress, 100, ligne.restore_phase)
        self.assertEqual(ligne.status, BackupArchive.Status.COMPLETED)
        self.assertEqual(ligne.restore_phase, "Terminee")

    def test_l_avancement_progresse_pendant_le_chargement(self):
        # Tout partait en un seul `loaddata`: l'ecran affichait 62 % pendant
        # toute la duree du chargement, et la restauration paraissait figee
        # alors qu'elle travaillait.
        vue = BackupArchiveViewSet()
        etapes = []

        reel = vue._set_restore_progress

        def _tracer(ref, **kwargs):
            if kwargs.get("progress") is not None:
                etapes.append((kwargs["progress"], kwargs.get("phase") or ""))
            return reel(ref, **kwargs)

        vue._set_restore_progress = _tracer

        with tempfile.TemporaryDirectory() as media:
            with override_settings(MEDIA_ROOT=media):
                sauvegarde = BackupArchive.objects.create(
                    scope=BackupArchive.Scope.GLOBAL,
                    created_by=self.admin,
                    include_media=False,
                    status=BackupArchive.Status.PENDING,
                )
                vue._build_archive(sauvegarde)
                sauvegarde.refresh_from_db()
                archive = Path(sauvegarde.file_path)
                self.addCleanup(lambda: archive.unlink(missing_ok=True))
                vue._restore_from_archive(sauvegarde, archive, actor=self.admin)

        chargement = [
            pourcent
            for pourcent, phase in etapes
            if phase.startswith("Chargement des donnees (")
        ]
        self.assertTrue(chargement, "Aucun avancement pendant le chargement.")
        self.assertEqual(chargement, sorted(chargement))

    def test_une_restauration_muette_est_declaree_interrompue(self):
        # Elle restait « en cours » a son dernier pourcentage, indefiniment:
        # l'ecran affichait une barre qui n'avancait plus, et personne ne
        # pouvait ni relancer ni comprendre.
        from django.utils import timezone

        vue = BackupArchiveViewSet()
        morte = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            created_by=self.admin,
            status=BackupArchive.Status.RUNNING,
            restore_phase="Chargement des donnees (120/5000)",
            restore_progress=64,
        )
        BackupArchive.objects.filter(pk=morte.pk).update(
            updated_at=timezone.now() - vue.SILENCE_AVANT_ABANDON * 2
        )

        vue._verifier_les_restaurations_bloquees(BackupArchive.objects.all())

        morte.refresh_from_db()
        self.assertEqual(morte.status, BackupArchive.Status.FAILED)
        self.assertEqual(morte.restore_phase, "Interrompue")
        self.assertIn("ne repond plus", morte.restore_log)

    def test_une_restauration_qui_avance_est_laissee_tranquille(self):
        vue = BackupArchiveViewSet()
        vivante = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            created_by=self.admin,
            status=BackupArchive.Status.RUNNING,
            restore_phase="Chargement des donnees (120/5000)",
            restore_progress=64,
        )

        vue._verifier_les_restaurations_bloquees(BackupArchive.objects.all())

        vivante.refresh_from_db()
        self.assertEqual(vivante.status, BackupArchive.Status.RUNNING)

    def test_une_sauvegarde_en_cours_n_est_pas_prise_pour_une_restauration(self):
        # Une archive qui s'ecrit est « en cours » elle aussi, mais elle n'a
        # pas de phase de restauration: la confondre l'aurait declaree morte.
        from django.utils import timezone

        vue = BackupArchiveViewSet()
        ecriture = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            created_by=self.admin,
            status=BackupArchive.Status.RUNNING,
            build_phase="Medias (12/40)",
            build_progress=42,
        )
        BackupArchive.objects.filter(pk=ecriture.pk).update(
            updated_at=timezone.now() - vue.SILENCE_AVANT_ABANDON * 2
        )

        vue._verifier_les_restaurations_bloquees(BackupArchive.objects.all())

        ecriture.refresh_from_db()
        self.assertEqual(ecriture.status, BackupArchive.Status.RUNNING)
