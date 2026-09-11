"""Ce que la sauvegarde emporte, ce qu'elle annonce, ce qu'elle efface."""

import tempfile
from pathlib import Path
from unittest.mock import patch

from django.conf import settings
from django.test import SimpleTestCase, override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.common.models import BackupArchive
from apps.common.sauvegarde import (
    est_un_document_de_bibliotheque,
    fichiers_a_archiver,
    poids_total,
    volume_de_la_bibliotheque,
)
from apps.common.views import BackupArchiveViewSet
from apps.school.models import Etablissement


def _poser(racine: Path, chemin: str, octets: int) -> Path:
    fichier = racine / chemin
    fichier.parent.mkdir(parents=True, exist_ok=True)
    fichier.write_bytes(b"x" * octets)
    return fichier


class SelectionDesFichiersTests(SimpleTestCase):
    """Le tri de ce qui entre dans l'archive, sans base de donnees."""

    def setUp(self):
        self.dossier = tempfile.TemporaryDirectory()
        self.addCleanup(self.dossier.cleanup)
        self.racine = Path(self.dossier.name)

        _poser(self.racine, "students/photo.jpg", 100)
        _poser(self.racine, "profiles/avatar.png", 50)
        _poser(self.racine, "library_docs/TSExp/Maths/annale.pdf", 5000)
        _poser(self.racine, "library_docs/etab_3/Reglement/regle.pdf", 3000)

    def test_la_bibliotheque_reste_dehors_par_defaut(self):
        retenus = fichiers_a_archiver(self.racine, avec_bibliotheque=False)

        noms = sorted(str(fichier.relatif) for fichier in retenus)
        self.assertEqual(noms, ["profiles/avatar.png", "students/photo.jpg"])
        self.assertEqual(poids_total(retenus), 150)

    def test_la_bibliotheque_entre_quand_on_la_demande(self):
        retenus = fichiers_a_archiver(self.racine, avec_bibliotheque=True)

        self.assertEqual(len(retenus), 4)
        self.assertEqual(poids_total(retenus), 8150)

    def test_le_volume_de_la_bibliotheque_se_mesure_a_part(self):
        self.assertEqual(volume_de_la_bibliotheque(self.racine), 8000)

    def test_un_dossier_absent_ne_fait_pas_echouer(self):
        self.assertEqual(fichiers_a_archiver(self.racine / "nulle_part", avec_bibliotheque=True), [])
        self.assertEqual(volume_de_la_bibliotheque(self.racine / "nulle_part"), 0)

    def test_un_dossier_qui_commence_pareil_n_est_pas_la_bibliotheque(self):
        # « library_docs_archive » n'est pas « library_docs »: comparer sur
        # le prefixe de la chaine aurait exclu les deux.
        self.assertFalse(
            est_un_document_de_bibliotheque(Path("library_docs_archive/a.pdf"))
        )
        self.assertTrue(est_un_document_de_bibliotheque(Path("library_docs/a.pdf")))

    def test_le_nom_dans_l_archive_est_prefixe_par_media(self):
        retenus = fichiers_a_archiver(self.racine, avec_bibliotheque=False)
        noms = sorted(fichier.nom_dans_l_archive for fichier in retenus)
        self.assertEqual(noms, ["media/profiles/avatar.png", "media/students/photo.jpg"])


class AvancementDeLaSauvegardeTests(APITestCase):
    """La barre de progression et le volume annonce."""

    def setUp(self):
        self.super_admin = User.objects.create_user(
            username="superadmin_avancement",
            password="pass12345",
            role=UserRole.SUPER_ADMIN,
        )
        self.etablissement = Etablissement.objects.create(
            name="Etab Avancement",
            address="Adresse",
            phone="770000010",
            email="avancement@example.com",
        )

    def test_la_progression_couvre_la_tranche_des_medias(self):
        viewset = BackupArchiveViewSet()
        debut, fin = viewset._PART_MEDIAS

        self.assertEqual(viewset._pourcentage_des_medias(0, 1000), debut)
        self.assertEqual(viewset._pourcentage_des_medias(1000, 1000), fin)
        milieu = viewset._pourcentage_des_medias(500, 1000)
        self.assertGreater(milieu, debut)
        self.assertLess(milieu, fin)

    def test_une_archive_vide_n_affiche_pas_une_division_par_zero(self):
        viewset = BackupArchiveViewSet()
        self.assertEqual(viewset._pourcentage_des_medias(0, 0), viewset._PART_MEDIAS[1])

    def test_l_ecriture_renseigne_le_volume_et_termine_a_cent(self):
        with tempfile.TemporaryDirectory() as media:
            _poser(Path(media), "students/photo.jpg", 400)
            _poser(Path(media), "library_docs/TSExp/annale.pdf", 90000)

            backup = BackupArchive.objects.create(
                scope=BackupArchive.Scope.ETABLISSEMENT,
                etablissement=self.etablissement,
                created_by=self.super_admin,
                include_media=True,
                include_library_documents=False,
                status=BackupArchive.Status.PENDING,
            )
            with override_settings(MEDIA_ROOT=media):
                BackupArchiveViewSet()._build_archive(backup)

        backup.refresh_from_db()
        self.assertEqual(backup.status, BackupArchive.Status.COMPLETED)
        self.assertEqual(backup.build_progress, 100)
        self.assertEqual(backup.build_phase, "Terminee")
        self.assertEqual(backup.bytes_done, backup.bytes_total)
        self.assertGreater(backup.bytes_total, 0)
        self.assertIsNotNone(backup.build_started_at)
        # Le volume annonce ne compte pas les 90 Ko de la bibliotheque.
        self.assertLess(backup.bytes_total, 90000)
        self.assertEqual(backup.manifest["media_files"], 1)
        self.assertFalse(backup.manifest["include_library_documents"])

        archive = Path(backup.file_path)
        self.addCleanup(lambda: archive.unlink(missing_ok=True))
        import zipfile

        with zipfile.ZipFile(archive) as zf:
            noms = zf.namelist()
        self.assertIn("media/students/photo.jpg", noms)
        self.assertNotIn("media/library_docs/TSExp/annale.pdf", noms)

    def test_la_creation_rend_la_main_sans_attendre_l_archive(self):
        self.client.force_authenticate(self.super_admin)
        lancements = []
        with patch.object(
            BackupArchiveViewSet,
            "_run_build_in_background",
            lambda self, backup_id: lancements.append(backup_id),
        ):
            response = self.client.post(
                "/api/backup-archives/",
                {"scope": "global", "include_media": True, "include_library_documents": False},
                format="json",
            )

        self.assertEqual(response.status_code, status.HTTP_202_ACCEPTED)
        self.assertEqual(len(lancements), 1)
        backup = BackupArchive.objects.get(pk=response.data["id"])
        self.assertEqual(backup.status, BackupArchive.Status.PENDING)
        self.assertFalse(backup.include_library_documents)

    def test_la_bibliotheque_se_demande_explicitement(self):
        self.client.force_authenticate(self.super_admin)
        with patch.object(BackupArchiveViewSet, "_run_build_in_background"):
            response = self.client.post(
                "/api/backup-archives/",
                {"scope": "global", "include_media": True, "include_library_documents": "true"},
                format="json",
            )

        backup = BackupArchive.objects.get(pk=response.data["id"])
        self.assertTrue(backup.include_library_documents)

    def test_sans_media_la_bibliotheque_ne_revient_pas_par_la_bande(self):
        self.client.force_authenticate(self.super_admin)
        with patch.object(BackupArchiveViewSet, "_run_build_in_background"):
            response = self.client.post(
                "/api/backup-archives/",
                {"scope": "global", "include_media": False, "include_library_documents": True},
                format="json",
            )

        backup = BackupArchive.objects.get(pk=response.data["id"])
        self.assertFalse(backup.include_library_documents)

    def test_le_volume_s_annonce_avant_de_lancer(self):
        self.client.force_authenticate(self.super_admin)
        with tempfile.TemporaryDirectory() as media:
            _poser(Path(media), "students/photo.jpg", 400)
            _poser(Path(media), "library_docs/TSExp/annale.pdf", 90000)
            with override_settings(MEDIA_ROOT=media):
                response = self.client.get("/api/backup-archives/volumes/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["media_hors_bibliotheque_octets"], 400)
        self.assertEqual(response.data["bibliotheque_octets"], 90000)
        self.assertEqual(response.data["media_total_octets"], 90400)


class SuppressionDesArchivesTests(APITestCase):
    """Le menage de l'historique."""

    def setUp(self):
        self.super_admin = User.objects.create_user(
            username="superadmin_menage",
            password="pass12345",
            role=UserRole.SUPER_ADMIN,
        )
        self.director = User.objects.create_user(
            username="director_menage",
            password="pass12345",
            role=UserRole.DIRECTOR,
        )
        self.racine = Path(settings.BASE_DIR) / "backups" / "archives"
        self.racine.mkdir(parents=True, exist_ok=True)

    def _archive(self, nom: str, *, status_=BackupArchive.Status.COMPLETED):
        chemin = self.racine / nom
        chemin.write_bytes(b"z" * 10)
        self.addCleanup(lambda: chemin.unlink(missing_ok=True))
        return BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            status=status_,
            created_by=self.super_admin,
            filename=nom,
            file_path=str(chemin),
            file_size_bytes=10,
        )

    def test_la_suppression_retire_la_ligne_et_le_fichier(self):
        backup = self._archive("test_menage_un.zip")
        chemin = Path(backup.file_path)
        self.client.force_authenticate(self.super_admin)

        response = self.client.delete(f"/api/backup-archives/{backup.id}/")

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(BackupArchive.objects.filter(pk=backup.id).exists())
        self.assertFalse(chemin.exists())

    def test_une_sauvegarde_en_cours_ne_se_supprime_pas(self):
        backup = self._archive("test_menage_encours.zip", status_=BackupArchive.Status.RUNNING)
        self.client.force_authenticate(self.super_admin)

        response = self.client.delete(f"/api/backup-archives/{backup.id}/")

        self.assertEqual(response.status_code, status.HTTP_409_CONFLICT)
        self.assertTrue(BackupArchive.objects.filter(pk=backup.id).exists())
        self.assertTrue(Path(backup.file_path).exists())

    def test_la_direction_ne_supprime_pas(self):
        backup = self._archive("test_menage_direction.zip")
        self.client.force_authenticate(self.director)

        response = self.client.delete(f"/api/backup-archives/{backup.id}/")

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(BackupArchive.objects.filter(pk=backup.id).exists())

    def test_un_chemin_hors_de_l_entrepot_n_est_pas_efface(self):
        # Un `file_path` errone ne doit pas donner le moyen d'effacer un
        # fichier quelconque du serveur.
        with tempfile.TemporaryDirectory() as ailleurs:
            intrus = Path(ailleurs) / "important.conf"
            intrus.write_text("ne pas toucher")
            backup = BackupArchive.objects.create(
                scope=BackupArchive.Scope.GLOBAL,
                status=BackupArchive.Status.COMPLETED,
                created_by=self.super_admin,
                filename="intrus.zip",
                file_path=str(intrus),
            )
            self.client.force_authenticate(self.super_admin)

            response = self.client.delete(f"/api/backup-archives/{backup.id}/")

            self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
            self.assertTrue(intrus.exists())

    def test_le_menage_garde_les_plus_recentes(self):
        archives = [self._archive(f"test_purge_{rang}.zip") for rang in range(5)]
        self.client.force_authenticate(self.super_admin)

        response = self.client.post(
            "/api/backup-archives/purge/", {"conserver": 2}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["supprimees"], 3)
        self.assertEqual(response.data["octets_liberes"], 30)
        restantes = set(BackupArchive.objects.values_list("id", flat=True))
        self.assertEqual(restantes, {archives[-1].id, archives[-2].id})

    def test_le_menage_ne_vide_jamais_tout(self):
        self._archive("test_purge_seule.zip")
        self.client.force_authenticate(self.super_admin)

        response = self.client.post(
            "/api/backup-archives/purge/", {"conserver": 0}, format="json"
        )

        self.assertEqual(response.data["supprimees"], 0)
        self.assertEqual(BackupArchive.objects.count(), 1)

    def test_le_menage_epargne_une_sauvegarde_en_cours(self):
        self._archive("test_purge_recente.zip")
        encours = self._archive("test_purge_active.zip", status_=BackupArchive.Status.RUNNING)
        self.client.force_authenticate(self.super_admin)

        self.client.post("/api/backup-archives/purge/", {"conserver": 1}, format="json")

        self.assertTrue(BackupArchive.objects.filter(pk=encours.id).exists())
