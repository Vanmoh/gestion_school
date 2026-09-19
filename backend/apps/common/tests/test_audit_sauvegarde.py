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
from django.test import TransactionTestCase
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


class ChargementParLotsTests(_Decor, APITestCase):
    """Le chargement: par lots, en ecrasant l'existant, avec ses liens."""

    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def _compte(self, pk, username, **champs):
        return {
            "model": "accounts.user",
            "pk": pk,
            "fields": {
                "username": username,
                "password": "x",
                "role": "teacher",
                "is_active": True,
                "first_name": champs.get("prenom", ""),
                "last_name": "",
                "email": "",
                "is_staff": False,
                "is_superuser": False,
                "date_joined": "2026-01-01T00:00:00Z",
                "groups": champs.get("groupes", []),
                "user_permissions": [],
            },
        }

    def test_une_ligne_existante_est_ecrasee_sans_echouer(self):
        # Une restauration d'etablissement recharge aussi les comptes
        # d'autres ecoles que ses enseignants referencent, et ceux-la n'ont
        # pas ete supprimes.
        existant = User.objects.create_user(
            username="deja_la", password="Pass1234!", role=UserRole.TEACHER, first_name="Ancien"
        )
        en_cours = BackupArchive.objects.create(scope="global", status="running")

        BackupArchiveViewSet()._charger_les_donnees(
            en_cours, [self._compte(existant.pk, "deja_la", prenom="Restaure")]
        )

        existant.refresh_from_db()
        self.assertEqual(existant.first_name, "Restaure")

    def test_les_groupes_d_un_compte_sont_restaures(self):
        # Les liens multiples ne passent pas par l'insertion en lot.
        from django.contrib.auth.models import Group

        groupe = Group.objects.create(name="Surveillance")
        en_cours = BackupArchive.objects.create(scope="global", status="running")

        BackupArchiveViewSet()._charger_les_donnees(
            en_cours, [self._compte(880001, "avec_groupe", groupes=[groupe.pk])]
        )

        self.assertEqual(
            list(User.objects.get(pk=880001).groups.values_list("name", flat=True)),
            ["Surveillance"],
        )

    def test_mille_lignes_ne_font_pas_mille_allers_retours(self):
        # Le coeur de la lenteur en production: un aller-retour par ligne,
        # vers une base distante.
        from django.db import connection
        from django.test.utils import CaptureQueriesContext

        en_cours = BackupArchive.objects.create(scope="global", status="running")
        lignes = [self._compte(870000 + rang, f"lot_{rang}") for rang in range(1000)]

        with CaptureQueriesContext(connection) as requetes:
            BackupArchiveViewSet()._charger_les_donnees(en_cours, lignes)

        ecritures = [
            q for q in requetes.captured_queries if q["sql"].lstrip().upper().startswith("INSERT")
        ]
        self.assertEqual(User.objects.filter(username__startswith="lot_").count(), 1000)
        # Le seuil tient pour les deux moteurs: PostgreSQL passe en deux ou
        # trois insertions, SQLite en une quinzaine -- il borne le nombre de
        # parametres par requete. Les deux sont sans commune mesure avec les
        # mille allers-retours d'avant.
        self.assertLessEqual(
            len(ecritures), 25, f"{len(ecritures)} insertions pour 1000 lignes"
        )


class CompteursApresRestaurationTests(TransactionTestCase):
    """La saisie qui suit une restauration ne doit pas heurter une ligne restauree."""

    def test_la_saisie_suivante_recoit_un_identifiant_libre(self):
        from django.db import connection

        if connection.vendor != "postgresql":
            self.skipTest("Les sequences n'existent qu'avec PostgreSQL.")

        en_cours = BackupArchive.objects.create(scope="global", status="running")
        self.addCleanup(lambda: User.objects.filter(pk=900000).delete())
        BackupArchiveViewSet()._charger_les_donnees(
            en_cours,
            [
                {
                    "model": "accounts.user",
                    "pk": 900000,
                    "fields": {
                        "username": "restaure_haut",
                        "password": "x",
                        "role": "teacher",
                        "is_active": True,
                        "first_name": "",
                        "last_name": "",
                        "email": "",
                        "is_staff": False,
                        "is_superuser": False,
                        "date_joined": "2026-01-01T00:00:00Z",
                        "groups": [],
                        "user_permissions": [],
                    },
                }
            ],
        )

        suivant = User.objects.create_user(
            username="saisi_apres", password="Pass1234!", role=UserRole.TEACHER
        )
        self.addCleanup(suivant.delete)

        # Prouve avant correction: la saisie suivante recevait le numero 1.
        self.assertGreater(suivant.pk, 900000)


class MediasDansLeStockageTests(_Decor, APITestCase):
    """Les medias suivent le stockage configure, pas le disque du conteneur.

    En production, les fichiers vivent chez Supabase et le dossier `media` du
    conteneur est vide. La sauvegarde lisait ce dossier: une archive faite en
    production n'emportait aucune photo d'eleve, aucune piece jointe, aucun
    logo -- alors que « inclure les medias » etait coche. Et une archive faite
    en local deposait ses images sur ce disque, ou rien ne va les chercher et
    que le prochain deploiement efface.
    """

    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def setUp(self):
        super().setUp()
        from django.core.files.storage import FileSystemStorage

        self.dossier = tempfile.TemporaryDirectory()
        self.addCleanup(self.dossier.cleanup)
        # Un stockage qui n'est pas MEDIA_ROOT: c'est exactement la situation
        # de la production, ou le stockage est ailleurs que le disque.
        self.stockage = FileSystemStorage(location=self.dossier.name)

    def _poser(self, nom, contenu=b"x"):
        from django.core.files.base import ContentFile

        return self.stockage.save(nom, ContentFile(contenu))

    def test_la_sauvegarde_voit_les_fichiers_du_stockage(self):
        from apps.common.sauvegarde import fichiers_a_archiver

        self._poser("personnalisation/fonds/login.png")
        self._poser("students/photo.jpg")

        noms = {f.nom for f in fichiers_a_archiver(self.stockage, avec_bibliotheque=False)}

        self.assertIn("personnalisation/fonds/login.png", noms)
        self.assertIn("students/photo.jpg", noms)

    def test_la_bibliotheque_reste_dehors_sans_etre_parcourue(self):
        from apps.common.sauvegarde import fichiers_a_archiver

        self._poser("library_docs/TSExp/annale.pdf")
        self._poser("students/photo.jpg")

        noms = {f.nom for f in fichiers_a_archiver(self.stockage, avec_bibliotheque=False)}

        self.assertEqual(noms, {"students/photo.jpg"})

    def test_la_bibliotheque_entre_quand_on_la_demande(self):
        from apps.common.sauvegarde import fichiers_a_archiver

        self._poser("library_docs/TSExp/annale.pdf")

        noms = {f.nom for f in fichiers_a_archiver(self.stockage, avec_bibliotheque=True)}

        self.assertEqual(noms, {"library_docs/TSExp/annale.pdf"})

    def test_la_restauration_repose_le_fichier_a_son_nom(self):
        # Le stockage objet de production est configure pour ne pas ecraser:
        # sans effacement prealable, il renommerait le fichier en
        # « login_a1b2c3.png », et la fiche qui le reference pointerait dans
        # le vide.
        from apps.common.sauvegarde import reposer

        self._poser("personnalisation/fonds/login.png", b"ancienne image")

        reposer("personnalisation/fonds/login.png", b"nouvelle image", self.stockage)

        with self.stockage.open("personnalisation/fonds/login.png") as fichier:
            self.assertEqual(fichier.read(), b"nouvelle image")
        self.assertEqual(
            len(self.stockage.listdir("personnalisation/fonds")[1]),
            1,
            "Le fichier a ete double au lieu d'etre remplace.",
        )

    def test_un_fichier_absent_se_repose_quand_meme(self):
        from apps.common.sauvegarde import reposer

        reposer("etablissements/logos/neuf.png", b"image", self.stockage)

        self.assertTrue(self.stockage.exists("etablissements/logos/neuf.png"))
