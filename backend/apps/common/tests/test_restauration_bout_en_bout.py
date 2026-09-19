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
from django.test import TransactionTestCase

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

    def test_une_sauvegarde_muette_est_declaree_interrompue_elle_aussi(self):
        # Le symptome signale: une archive figee sur « Lecture de la base »
        # a 1 %, indefiniment. Le processus etait tue par la memoire, et
        # rien ne le disait.
        from django.utils import timezone

        vue = BackupArchiveViewSet()
        ecriture = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            created_by=self.admin,
            status=BackupArchive.Status.RUNNING,
            build_phase="Lecture de la base",
            build_progress=1,
        )
        BackupArchive.objects.filter(pk=ecriture.pk).update(
            updated_at=timezone.now() - vue.SILENCE_AVANT_ABANDON * 2
        )

        vue._verifier_les_restaurations_bloquees(BackupArchive.objects.all())

        ecriture.refresh_from_db()
        self.assertEqual(ecriture.status, BackupArchive.Status.FAILED)
        self.assertEqual(ecriture.build_phase, "Interrompue")
        self.assertIn("sauvegarde ne repond plus", ecriture.restore_log)

    def test_une_sauvegarde_qui_avance_est_laissee_tranquille(self):
        vue = BackupArchiveViewSet()
        ecriture = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            created_by=self.admin,
            status=BackupArchive.Status.RUNNING,
            build_phase="Medias (12/40)",
            build_progress=42,
        )

        vue._verifier_les_restaurations_bloquees(BackupArchive.objects.all())

        ecriture.refresh_from_db()
        self.assertEqual(ecriture.status, BackupArchive.Status.RUNNING)

    def test_la_lecture_de_la_base_annonce_la_table_en_cours(self):
        # Le symptome signale: une sauvegarde figee sur « Lecture de la base »
        # a 1 %. La phase ne bougeait pas de tout le parcours, et rien ne
        # distinguait un travail en cours d'un processus mort.
        vue = BackupArchiveViewSet()
        phases = []

        reel = vue._set_restore_progress
        vue._set_restore_progress = lambda ref, **kw: (
            phases.append(kw.get("phase") or ""),
            reel(ref, **kw),
        )[1]

        sauvegarde = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            created_by=self.admin,
            status=BackupArchive.Status.PENDING,
        )
        with tempfile.TemporaryDirectory() as dossier:
            vue._serialize_global_vers(
                Path(dossier) / "data.json", backup=sauvegarde
            )

        lectures = [phase for phase in phases if phase.startswith("Lecture : ")]
        self.assertGreater(len(lectures), 5, phases)
        self.assertEqual(len(lectures), len(set(lectures)))

    def test_les_donnees_partent_dans_un_fichier_et_non_en_memoire(self):
        # La base entiere tenait en memoire quatre fois: une chaine JSON par
        # table, les memes donnees reconverties, leur concatenation, puis
        # cette chaine gardee pendant la compression. Sur 512 Mo, le systeme
        # tuait le processus.
        import json

        vue = BackupArchiveViewSet()
        with tempfile.TemporaryDirectory() as dossier:
            fichier = Path(dossier) / "data.json"
            lignes = vue._serialize_global_vers(fichier)

            self.assertTrue(fichier.exists())
            contenu = json.loads(fichier.read_text(encoding="utf-8"))

        self.assertIsInstance(contenu, list)
        self.assertEqual(len(contenu), lignes)
        modeles = {entree["model"] for entree in contenu}
        self.assertIn("school.student", modeles)
        self.assertIn("accounts.user", modeles)

    def test_une_selection_vide_produit_un_tableau_vide_lisible(self):
        # Les lots sont cousus bout a bout dans un seul tableau: sans rien a
        # coudre, le fichier doit rester du JSON valide et non une chaine
        # tronquee que la restauration refuserait.
        import json

        from apps.school.models import Student

        vue = BackupArchiveViewSet()
        with tempfile.TemporaryDirectory() as dossier:
            fichier = Path(dossier) / "vide.json"
            with fichier.open("w", encoding="utf-8") as flux:
                lignes = vue._ecrire_les_donnees(
                    flux, [Student.objects.none()]
                )
            contenu = json.loads(fichier.read_text(encoding="utf-8"))

        self.assertEqual(lignes, 0)
        self.assertEqual(contenu, [])

    def test_les_lots_se_cousent_sans_perdre_de_ligne(self):
        # Le decoupage en lots est ce qui borne la memoire: il ne doit rien
        # perdre ni rien dupliquer a la couture.
        import json

        from apps.school.models import Student

        vue = BackupArchiveViewSet()
        attendu = Student.objects.count()
        self.assertGreater(attendu, 0)

        with tempfile.TemporaryDirectory() as dossier:
            fichier = Path(dossier) / "lots.json"
            with fichier.open("w", encoding="utf-8") as flux:
                # Un lot d'une seule ligne force autant de coutures que de
                # lignes: c'est le cas le plus exposé.
                vue.TAILLE_DE_LOT = 1
                try:
                    lignes = vue._ecrire_les_donnees(
                        flux, [Student.objects.all().order_by("pk")]
                    )
                finally:
                    del vue.TAILLE_DE_LOT
            contenu = json.loads(fichier.read_text(encoding="utf-8"))

        self.assertEqual(lignes, attendu)
        self.assertEqual(len(contenu), attendu)


class AvancementHorsTransactionTests(TransactionTestCase):
    """Le « fige a 28 % ».

    La restauration nettoie puis charge dans une seule transaction -- il le
    faut, sinon un echec en cours de chargement laisserait la base videe.
    Mais tout ce qui est ecrit dans une transaction reste invisible aux
    autres connexions jusqu'au commit: l'ecran, qui interroge sur sa propre
    connexion, lisait la derniere valeur commitee -- 28 -- pendant toute la
    duree du travail. Et si le processus mourait, la transaction etait
    annulee et cette valeur restait la pour toujours.
    """

    def test_l_avancement_survit_a_une_transaction_annulee(self):
        from django.db import connection, transaction

        if connection.vendor == "sqlite":
            self.skipTest(
                "SQLite verrouille la base pendant une transaction en "
                "ecriture: une seconde connexion ne peut pas y ecrire. La "
                "production tourne sur PostgreSQL, ou c'est le cas nominal."
            )

        vue = BackupArchiveViewSet()
        archive = BackupArchive.objects.create(
            scope=BackupArchive.Scope.GLOBAL,
            status=BackupArchive.Status.RUNNING,
            restore_phase="Donnees preparees",
            restore_progress=28,
        )
        self.addCleanup(
            lambda: BackupArchive.objects.filter(pk=archive.pk).delete()
        )

        try:
            with transaction.atomic():
                vue._set_restore_progress(
                    archive, progress=62, phase="Chargement des donnees"
                )
                raise RuntimeError("le processus meurt ici")
        except RuntimeError:
            pass

        archive.refresh_from_db()
        self.assertEqual(archive.restore_progress, 62)
        self.assertEqual(archive.restore_phase, "Chargement des donnees")
