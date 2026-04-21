from pathlib import Path

from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.common.models import BackupArchive
from apps.school.models import Etablissement


class BackupRestorePermissionsApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etab Backup",
            address="Adresse",
            phone="770000002",
            email="backup@example.com",
        )
        self.director = User.objects.create_user(
            username="director_backup",
            password="pass12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.super_admin = User.objects.create_user(
            username="superadmin_backup",
            password="pass12345",
            role=UserRole.SUPER_ADMIN,
        )

        archives_dir = Path(settings.BASE_DIR) / "backups" / "archives"
        archives_dir.mkdir(parents=True, exist_ok=True)
        archive_path = archives_dir / "test_restore_permission.zip"
        archive_path.write_bytes(b"dummy")

        self.backup = BackupArchive.objects.create(
            scope=BackupArchive.Scope.ETABLISSEMENT,
            status=BackupArchive.Status.COMPLETED,
            etablissement=self.etablissement,
            created_by=self.super_admin,
            filename=archive_path.name,
            file_path=str(archive_path),
        )

    def test_director_cannot_trigger_restore_from_existing_backup(self):
        self.client.force_authenticate(self.director)
        response = self.client.post(f"/api/backup-archives/{self.backup.id}/restore/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_director_cannot_upload_restore_archive(self):
        self.client.force_authenticate(self.director)
        upload = SimpleUploadedFile("restore.zip", b"zipcontent", content_type="application/zip")
        response = self.client.post(
            "/api/backup-archives/upload-restore/",
            {"scope": BackupArchive.Scope.ETABLISSEMENT, "file": upload},
            format="multipart",
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
