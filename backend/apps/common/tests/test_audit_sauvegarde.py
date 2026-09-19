"""Les defauts trouves a l'audit du module de sauvegarde.

Chacun de ces tests echouait avant sa correction.
"""

import json
import tempfile
import zipfile
from datetime import date
from pathlib import Path
from unittest.mock import patch

from django.conf import settings
from django.core import serializers
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.common.models import BackupArchive
from apps.common.views import BackupArchiveViewSet
from apps.school.models import AcademicYear, ClassRoom, Etablissement, ParentProfile


def _archive(chemin: Path, *, scope, etablissement_id=None, donnees=None, manifeste=True):
    with zipfile.ZipFile(chemin, "w") as zf:
        if manifeste:
            zf.writestr(
                "manifest.json",
                json.dumps({"scope": scope, "etablissement_id": etablissement_id}),
            )
        zf.writestr("data.json", json.dumps(donnees or []))
    return chemin


class _Decor:
    @classmethod
    def _monter(cls):
        cls.etablissement = Etablissement.objects.create(name="Etab Audit", code="EAUD")
        cls.voisine = Etablissement.objects.create(name="Etab Voisine", code="EVOI")
        cls.admin = User.objects.create_user(
            username="admin_audit",
            password="Pass1234!",
            role=UserRole.SUPER_ADMIN,
            etablissement=cls.etablissement,
        )


class PorteeDeLArchiveTests(_Decor, APITestCase):
    """La portee de l'archive tranche, pas le menu deroulant."""

    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def setUp(self):
        super().setUp()
        self.vue = BackupArchiveViewSet()
        self.dossier = tempfile.TemporaryDirectory()
        self.addCleanup(self.dossier.cleanup)

    def _chemin(self, nom="archive.zip"):
        return Path(self.dossier.name) / nom

    def test_une_archive_d_etablissement_ne_se_restaure_pas_en_global(self):
        # Le plus grave de l'audit: le mode global efface toutes les ecoles,
        # puis ne rechargeait que celle de l'archive.
        from rest_framework.exceptions import ValidationError

        chemin = _archive(
            self._chemin(),
            scope=BackupArchive.Scope.ETABLISSEMENT,
            etablissement_id=self.etablissement.id,
        )

        with self.assertRaises(ValidationError) as contexte:
            self.vue._verifier_la_portee(chemin, BackupArchive.Scope.GLOBAL, None)
        self.assertIn("un seul établissement", str(contexte.exception.detail))

    def test_une_archive_globale_ne_se_restaure_pas_dans_une_ecole(self):
        from rest_framework.exceptions import ValidationError

        chemin = _archive(self._chemin(), scope=BackupArchive.Scope.GLOBAL)

        with self.assertRaises(ValidationError):
            self.vue._verifier_la_portee(
                chemin, BackupArchive.Scope.ETABLISSEMENT, self.etablissement.id
            )

    def test_l_archive_d_une_ecole_ne_se_restaure_pas_dans_une_autre(self):
        # Elle viderait l'ecole cible, puis ecraserait la sienne avec ses
        # anciennes donnees.
        from rest_framework.exceptions import ValidationError

        chemin = _archive(
            self._chemin(),
            scope=BackupArchive.Scope.ETABLISSEMENT,
            etablissement_id=self.voisine.id,
        )

        with self.assertRaises(ValidationError) as contexte:
            self.vue._verifier_la_portee(
                chemin, BackupArchive.Scope.ETABLISSEMENT, self.etablissement.id
            )
        self.assertIn("autre établissement", str(contexte.exception.detail))

    def test_une_archive_concordante_passe(self):
        chemin = _archive(
            self._chemin(),
            scope=BackupArchive.Scope.ETABLISSEMENT,
            etablissement_id=self.etablissement.id,
        )

        self.vue._verifier_la_portee(
            chemin, BackupArchive.Scope.ETABLISSEMENT, self.etablissement.id
        )

    def test_un_fichier_qui_n_est_pas_un_zip_est_refuse(self):
        from rest_framework.exceptions import ValidationError

        chemin = self._chemin("faux.zip")
        chemin.write_bytes(b"ceci n'est pas une archive")

        with self.assertRaises(ValidationError):
            self.vue._verifier_la_portee(chemin, BackupArchive.Scope.GLOBAL, None)

    def test_une_archive_sans_manifeste_est_refusee(self):
        # Sans manifeste, rien ne dit ce qu'elle contient: on ne devine pas
        # avant d'effacer.
        from rest_framework.exceptions import ValidationError

        chemin = _archive(
            self._chemin(), scope=BackupArchive.Scope.GLOBAL, manifeste=False
        )

        with self.assertRaises(ValidationError):
            self.vue._verifier_la_portee(chemin, BackupArchive.Scope.GLOBAL, None)

    def test_le_televersement_refuse_avant_de_lancer_quoi_que_ce_soit(self):
        from django.core.files.uploadedfile import SimpleUploadedFile

        chemin = _archive(
            self._chemin(),
            scope=BackupArchive.Scope.ETABLISSEMENT,
            etablissement_id=self.etablissement.id,
        )
        self.client.force_authenticate(self.admin)

        with patch.object(BackupArchiveViewSet, "_run_restore_in_background") as lancement:
            reponse = self.client.post(
                "/api/backup-archives/upload-restore/",
                {
                    "scope": "global",
                    "file": SimpleUploadedFile("archive.zip", chemin.read_bytes()),
                },
                format="multipart",
            )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        lancement.assert_not_called()
        self.assertFalse(
            BackupArchive.objects.filter(filename__startswith="uploaded_restore").exists()
        )


class HistoriqueHorsArchiveTests(_Decor, APITestCase):
    """L'historique des sauvegardes ne voyage pas dans les archives."""

    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def test_une_sauvegarde_globale_n_emporte_pas_l_historique(self):
        BackupArchive.objects.create(scope=BackupArchive.Scope.GLOBAL, filename="ancienne.zip")
        vue = BackupArchiveViewSet()

        with tempfile.TemporaryDirectory() as dossier:
            fichier = Path(dossier) / "data.json"
            vue._serialize_global_vers(fichier)
            modeles = {ligne["model"] for ligne in json.loads(fichier.read_text())}

        self.assertNotIn("common.backuparchive", modeles)
        self.assertNotIn("chat.chatpresence", modeles)

    def test_une_sauvegarde_d_ecole_n_emporte_pas_l_historique(self):
        # BackupArchive porte un champ etablissement: elle passait le filtre
        # de la sauvegarde d'une ecole.
        BackupArchive.objects.create(
            scope=BackupArchive.Scope.ETABLISSEMENT,
            etablissement=self.etablissement,
            filename="ecole.zip",
        )
        vue = BackupArchiveViewSet()

        with tempfile.TemporaryDirectory() as dossier:
            fichier = Path(dossier) / "data.json"
            vue._serialize_etablissement_vers(self.etablissement, fichier)
            modeles = {ligne["model"] for ligne in json.loads(fichier.read_text())}

        self.assertNotIn("common.backuparchive", modeles)

    def test_une_vieille_archive_ne_reecrit_pas_l_historique_actuel(self):
        # Le mecanisme des neuf archives orphelines: la restauration recopiait
        # l'historique du jour de la sauvegarde par-dessus celui d'aujourd'hui.
        actuelle = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            filename="aujourd_hui.zip",
            status=BackupArchive.Status.COMPLETED,
        )
        vieille = json.loads(
            serializers.serialize("json", [BackupArchive.objects.get(pk=actuelle.pk)])
        )
        vieille[0]["fields"]["filename"] = "d_il_y_a_un_mois.zip"

        BackupArchiveViewSet()._charger_les_donnees(actuelle, vieille)

        actuelle.refresh_from_db()
        self.assertEqual(actuelle.filename, "aujourd_hui.zip")


class SignauxAuChargementTests(_Decor, APITestCase):
    """Une restauration recharge les donnees telles qu'elles etaient."""

    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def test_le_numero_whatsapp_restaure_n_est_pas_reecrit(self):
        # Le signal de propagation reecrivait le numero WhatsApp du parent a
        # partir du telephone du compte, sur des donnees a moitie chargees.
        compte = User.objects.create_user(
            username="parent_restaure",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
            phone="+22370000001",
        )
        profil = ParentProfile.objects.create(user=compte)
        # Le numero WhatsApp suit encore le telephone: c'est le seul cas ou
        # le signal le reecrit, donc le seul ou la garde se voit.
        ParentProfile.objects.filter(pk=profil.pk).update(whatsapp_phone="+22370000001")

        brut = json.loads(serializers.serialize("json", [User.objects.get(pk=compte.pk)]))
        brut[0]["fields"]["phone"] = "+22370000002"

        en_cours = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL, status=BackupArchive.Status.RUNNING
        )
        BackupArchiveViewSet()._charger_les_donnees(en_cours, brut)

        profil.refresh_from_db()
        self.assertEqual(profil.whatsapp_phone, "+22370000001")


class UneOperationALaFoisTests(_Decor, APITestCase):
    """Deux operations a la fois epuisent les 512 Mo du conteneur."""

    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.admin)

    def test_une_sauvegarde_attend_la_fin_de_la_precedente(self):
        BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            status=BackupArchive.Status.RUNNING,
            build_phase="Lecture de la base",
            filename="en_cours.zip",
        )

        with patch.object(BackupArchiveViewSet, "_run_build_in_background") as lancement:
            reponse = self.client.post(
                "/api/backup-archives/", {"scope": "global"}, format="json"
            )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("en cours", str(reponse.data))
        lancement.assert_not_called()

    def test_une_operation_morte_ne_bloque_pas_la_suivante(self):
        # La tenir pour active bloquerait tout indefiniment.
        from django.utils import timezone

        morte = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            status=BackupArchive.Status.RUNNING,
            build_phase="Lecture de la base",
        )
        BackupArchive.objects.filter(pk=morte.pk).update(
            updated_at=timezone.now() - BackupArchiveViewSet.SILENCE_AVANT_ABANDON * 2
        )

        with patch.object(BackupArchiveViewSet, "_run_build_in_background"):
            reponse = self.client.post(
                "/api/backup-archives/", {"scope": "global"}, format="json"
            )

        self.assertEqual(reponse.status_code, status.HTTP_202_ACCEPTED, reponse.data)


class DossierDesSauvegardesTests(APITestCase):
    def test_les_tests_n_ecrivent_pas_dans_le_vrai_dossier(self):
        # Ils y laissaient des archives qu'aucune ligne ne referencait.
        vrai = (Path(settings.BASE_DIR) / "backups").resolve()
        courant = Path(settings.BACKUP_ROOT).resolve()

        self.assertNotEqual(courant, vrai)
        self.assertNotIn(vrai, courant.parents)
