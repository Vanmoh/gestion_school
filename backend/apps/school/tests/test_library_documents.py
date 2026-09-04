"""La bibliotheque numerique: import du fonds, catalogue, acces.

Le module « Bibliotheque » ne connaissait que l'ouvrage physique (Book,
Borrow): un titre, un ISBN, des exemplaires. Le fonds documentaire -- annales
et brochures rangees par serie et par matiere -- n'avait ni modele ni ecran.

Aucun test ne sort sur le reseau: les pages de la source sont figees en
fixture et le telechargement est remplace par une fonction locale.
"""

import shutil
import tempfile
from io import StringIO
from pathlib import Path
from unittest.mock import patch

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.management import CommandError, call_command
from django.test import override_settings
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.management.commands import import_bkalan
from apps.school.models import (
    Etablissement,
    LibraryCategory,
    LibraryCollection,
    LibraryDocument,
    LibraryDocumentOrigin,
    library_document_path,
)

PAGE = """
<!doctype html><html><body>
<ul class="tree">
<li class="node">
  <button class="folder"><span class="fname">10-eme-CG</span><span class="count">(4)</span></button>
  <ul class="nested">
    <li class="node">
      <button class="folder"><span class="fname">Chimie</span><span class="count">(2)</span></button>
      <ul class="nested">
        <li class="file"><a class="file-link" href="Chimie/BK_cours-CHIMIE.pdf"><span class="fname">BK_cours-CHIMIE.pdf</span></a></li>
        <li class="file"><a class="file-link" href="Chimie/BK_TD-CHIMIE.pdf"><span class="fname">BK_TD-CHIMIE.pdf</span></a></li>
      </ul>
    </li>
    <li class="node">
      <button class="folder"><span class="fname">Mathematiques</span><span class="count">(1)</span></button>
      <ul class="nested">
        <li class="file"><a class="file-link" href="Mathematiques/BK_trigonometrie.pdf"><span class="fname">BK_trigonometrie.pdf</span></a></li>
      </ul>
    </li>
  </ul>
</li>
</ul>
</body></html>
"""

# Chemin accentue: chez la source, ces fichiers repondent 401. Le catalogue
# doit les porter quand meme, sinon ils disparaissent sans laisser de trace.
PAGE_ACCENTS = """
<ul class="tree">
  <li class="file"><a class="file-link" href="Fran%C3%A7ais/BK_R%C3%A9daction.pdf"></a></li>
</ul>
"""


# Parenthese dans le nom: la source repond 401 si elle arrive encodee en
# %28, et 200 si elle passe telle quelle. Onze documents en dependent.
PAGE_PARENTHESES = """
<ul class="tree">
  <li class="file"><a class="file-link" href="Mathematiques/BK_compo-(1).pdf"></a></li>
</ul>
"""


# Crochet dans le nom: meme regle que la parenthese. La RFC 3986 les reserve
# aux adresses IPv6, `quote` les encode donc par defaut -- et la source rend
# un 401.
PAGE_CROCHETS = """
<ul class="tree">
  <li class="file"><a class="file-link" href="Physique/BK_Bac_2023[1].pdf"></a></li>
</ul>
"""


def _pdf(nom="document.pdf", poids=1024):
    """Un PDF minimal mais authentique: la signature y est.

    Le controle du serveur lit les cinq premiers octets, pas l'extension:
    un fichier de test sans « %PDF- » serait refuse comme le serait un .exe
    renomme, et le test passerait pour une raison qui n'est pas la sienne.
    """
    corps = b"%PDF-1.4\n" + b"0" * max(0, poids - 9)
    return SimpleUploadedFile(nom, corps, content_type="application/pdf")


class _StockageTemporaireMixin:
    """Un MEDIA_ROOT jetable par test: rien n'est ecrit dans le depot."""

    def setUp(self):
        super().setUp()
        repertoire = tempfile.mkdtemp(prefix="gs-library-upload-")
        self.addCleanup(shutil.rmtree, repertoire, ignore_errors=True)
        reglage = override_settings(MEDIA_ROOT=repertoire)
        reglage.enable()
        self.addCleanup(reglage.disable)
        self.media_root = Path(repertoire)


class _AmontFactice:
    """Ce que `urlopen` rend: un flux qu'on lit par blocs, puis qu'on ferme.

    Volontairement sans __iter__: la vue ne doit plus iterer l'objet amont,
    et une doublure qui le permettrait laisserait passer un retour a la
    decoupe ligne par ligne.
    """

    def __init__(self, contenu):
        self._contenu = contenu
        self._position = 0
        self.tailles_demandees = []
        self.ferme = False
        self.headers = {
            "Content-Type": "application/pdf",
            "Content-Length": str(len(contenu)),
        }

    def read(self, taille):
        self.tailles_demandees.append(taille)
        morceau = self._contenu[self._position : self._position + taille]
        self._position += len(morceau)
        return morceau

    def close(self):
        self.ferme = True


def _page_figee(contenu=PAGE):
    return lambda url: contenu


class ImportBkalanTests(APITestCase):
    """La commande d'import: catalogue d'abord, fichiers ensuite."""

    def _importer(self, *args, page=PAGE, **kwargs):
        # La sortie de la commande est detournee: le journal d'import n'a rien
        # a faire au milieu des points du runner.
        kwargs.setdefault("stdout", StringIO())
        kwargs.setdefault("stderr", StringIO())
        with patch.object(import_bkalan, "lire_page", _page_figee(page)):
            call_command("import_bkalan", *args, **kwargs)

    def test_the_catalogue_mirrors_the_source_tree(self):
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")

        collection = LibraryCollection.objects.get(code="10-eme-CG")
        self.assertEqual(collection.label, "10ème Commun Général")
        self.assertEqual(
            list(collection.categories.values_list("name", flat=True)),
            ["Chimie", "Mathematiques"],
        )
        self.assertEqual(LibraryDocument.objects.count(), 3)

    def test_the_bk_prefix_leaves_the_title(self):
        """Repete sur 1257 lignes, il n'aide pas a choisir un document."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")

        self.assertTrue(LibraryDocument.objects.filter(title="cours-CHIMIE").exists())
        self.assertFalse(LibraryDocument.objects.filter(title__startswith="BK_").exists())

    def test_the_source_url_is_rebuilt_whole(self):
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")

        document = LibraryDocument.objects.get(title="trigonometrie")
        self.assertEqual(
            document.source_url,
            "https://bkalan.ml/api/files/WhatsApp/10-eme-CG/Mathematiques/BK_trigonometrie.pdf",
        )

    def test_a_bracketed_name_keeps_its_brackets_in_the_url(self):
        """La source refuse %28: encoder la parenthese perdrait le fichier."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul", page=PAGE_PARENTHESES)

        document = LibraryDocument.objects.get()
        self.assertEqual(
            document.source_url,
            "https://bkalan.ml/api/files/WhatsApp/10-eme-CG/Mathematiques/BK_compo-(1).pdf",
        )

    def test_a_bracketed_name_keeps_its_brackets_too(self):
        """%5B valait un 401 au seul document du fonds qui porte un crochet."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul", page=PAGE_CROCHETS)

        document = LibraryDocument.objects.get()
        self.assertEqual(
            document.source_url,
            "https://bkalan.ml/api/files/WhatsApp/10-eme-CG/Physique/BK_Bac_2023[1].pdf",
        )

    def test_a_second_run_creates_nothing(self):
        """`source_url` porte l'unicite: l'import est rejouable."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")

        self.assertEqual(LibraryDocument.objects.count(), 3)
        self.assertEqual(LibraryCategory.objects.count(), 2)

    def test_si_vide_stops_before_touching_the_source(self):
        """Le demarrage du conteneur rejoue la commande a chaque reveil."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")

        def refuser(url):
            raise AssertionError(f"la source ne devait pas etre lue: {url}")

        with patch.object(import_bkalan, "lire_page", refuser):
            call_command(
                "import_bkalan",
                "--serie",
                "10-eme-CG",
                "--catalogue-seul",
                "--si-vide",
                stdout=StringIO(),
                stderr=StringIO(),
            )

        self.assertEqual(LibraryDocument.objects.count(), 3)

    def test_si_vide_imports_when_the_catalogue_is_empty(self):
        self._importer("--serie", "10-eme-CG", "--catalogue-seul", "--si-vide")

        self.assertEqual(LibraryDocument.objects.count(), 3)

    def test_si_vide_looks_only_at_the_series_asked_for(self):
        """Une serie ajoutee plus tard doit encore pouvoir entrer."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")
        self._importer("--serie", "TSExp", "--catalogue-seul", "--si-vide")

        self.assertEqual(
            LibraryDocument.objects.filter(
                category__collection__code="TSExp"
            ).count(),
            3,
        )

    def test_an_unknown_series_is_refused_even_with_si_vide(self):
        """La faute de frappe se voit, au lieu de passer pour un import fait."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")

        with self.assertRaises(CommandError):
            self._importer("--serie", "Terminale-Z", "--catalogue-seul", "--si-vide")

    def test_an_accented_path_still_enters_the_catalogue(self):
        self._importer("--serie", "10-eme-CG", "--catalogue-seul", page=PAGE_ACCENTS)

        document = LibraryDocument.objects.get()
        self.assertEqual(document.category.name, "Français")
        self.assertEqual(document.title, "Rédaction")

    def test_an_unknown_series_is_refused(self):
        with self.assertRaises(CommandError):
            self._importer("--serie", "Terminale-Z", "--catalogue-seul")

    @override_settings(MEDIA_ROOT="/tmp/gs-library-tests")
    def test_the_files_come_down_after_the_catalogue(self):
        def _faux_telechargement(url, chemin, taille_max=0):
            with open(chemin, "wb") as sortie:
                sortie.write(b"%PDF-1.4 contenu")
            return 16

        with patch.object(import_bkalan, "telecharger_fichier", _faux_telechargement):
            self._importer("--serie", "10-eme-CG", "--jobs", "2")

        documents = LibraryDocument.objects.all()
        self.assertEqual(documents.filter(is_downloaded=True).count(), 3)
        for document in documents:
            self.assertEqual(document.size_bytes, 16)
            self.assertIn("library_docs/10-eme-CG/", document.file.name)
            document.file.delete(save=False)

    @override_settings(MEDIA_ROOT="/tmp/gs-library-tests")
    def test_a_file_already_on_the_storage_is_adopted_not_downloaded(self):
        """Le stockage survit a la base: 2 Go de PDF ne se retelechargent pas."""
        self._importer("--serie", "10-eme-CG", "--catalogue-seul")

        document = LibraryDocument.objects.get(title="trigonometrie")
        chemin = Path(settings.MEDIA_ROOT) / library_document_path(
            document, "BK_trigonometrie.pdf"
        )
        chemin.parent.mkdir(parents=True, exist_ok=True)
        contenu = b"%PDF-1.4 pose la sans passer par la base"
        chemin.write_bytes(contenu)

        essais = []

        def _compte(url, cible, taille_max=0):
            essais.append(url)
            raise OSError("le fichier etait deja sur le disque")

        with patch.object(import_bkalan, "telecharger_fichier", _compte):
            self._importer("--serie", "10-eme-CG", "--jobs", "1")

        document.refresh_from_db()
        self.assertTrue(document.is_downloaded)
        self.assertEqual(document.size_bytes, len(contenu))
        self.assertEqual(
            document.file.name, "library_docs/10-eme-CG/Mathematiques/BK_trigonometrie.pdf"
        )
        # Les deux autres sont bien descendus, celui-la n'a pas ete redemande.
        self.assertEqual(len(essais), 2)
        chemin.unlink()

    def test_a_refused_file_is_recorded_not_swallowed(self):
        def _refus(url, chemin, taille_max=0):
            raise OSError("401 Unauthorized")

        with patch.object(import_bkalan, "telecharger_fichier", _refus):
            self._importer("--serie", "10-eme-CG", "--jobs", "1")

        document = LibraryDocument.objects.first()
        self.assertFalse(document.is_downloaded)
        self.assertIn("401", document.import_error)

    def test_the_longest_paths_of_the_fund_fit_in_the_field(self):
        """Les 100 caracteres par defaut coupaient l'import en deux.

        Le chemin recopie l'arborescence de la source; trente-six documents
        du fonds depassent 100 caracteres, le plus long en tient 127. Le PDF
        partait bien sur le stockage, puis la ligne mourait en base sur
        « value too long » -- des gigaoctets sans ligne pour les retrouver.
        Le test ne peut pas naitre d'une insertion: SQLite ne fait pas
        respecter la longueur d'un varchar, seul PostgreSQL la refuse.
        """
        collection = LibraryCollection.objects.create(code="11-eme-Sciences", label="x")
        categorie = LibraryCategory.objects.create(
            collection=collection, name="Physique-Chimie"
        )
        document = LibraryDocument(category=categorie, title="x", source_url="x")
        chemin = library_document_path(
            document,
            "BK_cours-prive-papin-LYLY-EXERCICES-SUR-LES-HYDROCARBURES-ET-COMPOSES-OXYGENES.pdf",
        )

        self.assertGreater(len(chemin), 100)
        self.assertLessEqual(
            len(chemin), LibraryDocument._meta.get_field("file").max_length
        )

    def test_the_progress_line_carries_a_percentage(self):
        """« 476/1257 » ne se divise pas de tete pendant une descente de nuit.

        La ligne compte les fichiers traites et non les seuls reussis: un lot
        entierement refuse restait muet jusqu'au resume final.
        """
        def _refus(url, chemin, taille_max=0):
            raise OSError("401 Unauthorized")

        journal = StringIO()
        with patch.object(import_bkalan, "telecharger_fichier", _refus):
            self._importer("--serie", "10-eme-CG", "--jobs", "1", stdout=journal)

        sortie = journal.getvalue()
        self.assertIn("3/3 (100 %)", sortie)
        self.assertIn("3 en echec", sortie)

    def test_a_recorded_error_is_not_retried_by_default(self):
        """Sinon chaque execution rejoue les 40 fichiers morts a la source."""
        def _refus(url, chemin, taille_max=0):
            raise OSError("401 Unauthorized")

        with patch.object(import_bkalan, "telecharger_fichier", _refus):
            self._importer("--serie", "10-eme-CG", "--jobs", "1")

        essais = []

        def _compte(url, chemin, taille_max=0):
            essais.append(url)
            raise OSError("401 Unauthorized")

        with patch.object(import_bkalan, "telecharger_fichier", _compte):
            self._importer("--serie", "10-eme-CG", "--jobs", "1")
        self.assertEqual(essais, [])

        with patch.object(import_bkalan, "telecharger_fichier", _compte):
            self._importer("--serie", "10-eme-CG", "--jobs", "1", "--retenter-erreurs")
        self.assertEqual(len(essais), 3)


class ImportTailleMaxTests(APITestCase):
    """`--taille-max`: le stockage a la capacite comptee prend la partie legere.

    Le fonds pese ~6,4 Go, mais 86 % des documents tiennent sous 5 Mo pour
    0,93 Go a eux tous: une centaine de gros fichiers -- jusqu'a 127 Mo --
    portent tout le reste. Le seuil permet de rapatrier la partie utile dans
    un stockage gratuit et de laisser le reste au relais.

    Ce qui est ecarte par le seuil n'est pas en echec: c'est la distinction
    que ces tests protegent. Un document note en erreur passerait pour mort a
    la source et sortirait de la file d'attente.
    """

    def setUp(self):
        # Un stockage neuf par test, et non un chemin fixe partage.
        # _adopter_le_disque rattache tout fichier trouve a l'emplacement
        # attendu: un test qui rapatrie trois PDF les fait adopter par les
        # suivants, dont la file d'attente se retrouve vide. Le resultat
        # dependait alors de l'ordre alphabetique des methodes.
        repertoire = tempfile.mkdtemp(prefix="gs-taille-max-")
        self.addCleanup(shutil.rmtree, repertoire, ignore_errors=True)
        reglage = override_settings(MEDIA_ROOT=repertoire)
        reglage.enable()
        self.addCleanup(reglage.disable)

    def _importer(self, *args, page=PAGE, **kwargs):
        kwargs.setdefault("stdout", StringIO())
        kwargs.setdefault("stderr", StringIO())
        with patch.object(import_bkalan, "lire_page", _page_figee(page)):
            call_command("import_bkalan", *args, **kwargs)

    def test_le_document_annonce_trop_gros_n_est_pas_telecharge(self):
        essais = []

        def _telecharger(url, chemin, taille_max=0):
            essais.append(url)
            with open(chemin, "wb") as sortie:
                sortie.write(b"%PDF")
            return 4

        # 8 Mo annonces, seuil a 5: la source n'a meme pas a etre sollicitee.
        with patch.object(import_bkalan, "taille_distante", lambda url: 8 * 1024 * 1024):
            with patch.object(import_bkalan, "telecharger_fichier", _telecharger):
                self._importer("--serie", "10-eme-CG", "--jobs", "1", "--taille-max", "5")

        self.assertEqual(essais, [])
        self.assertEqual(LibraryDocument.objects.filter(is_downloaded=True).count(), 0)

    def test_l_ecart_par_le_seuil_n_est_pas_une_erreur_d_import(self):
        with patch.object(import_bkalan, "taille_distante", lambda url: 8 * 1024 * 1024):
            with patch.object(import_bkalan, "telecharger_fichier", lambda *a, **k: 0):
                self._importer("--serie", "10-eme-CG", "--jobs", "1", "--taille-max", "5")

        # import_error vide: le document reste rapatriable et l'API continue
        # de le relayer, au lieu de le presenter comme illisible.
        self.assertFalse(
            LibraryDocument.objects.exclude(import_error="").exists(),
            "un document ecarte par le seuil ne doit pas etre note en erreur",
        )

    def test_le_document_sous_le_seuil_passe_normalement(self):
        def _telecharger(url, chemin, taille_max=0):
            with open(chemin, "wb") as sortie:
                sortie.write(b"%PDF-1.4 leger")
            return 14

        with patch.object(import_bkalan, "taille_distante", lambda url: 1024):
            with patch.object(import_bkalan, "telecharger_fichier", _telecharger):
                self._importer("--serie", "10-eme-CG", "--jobs", "1", "--taille-max", "5")

        self.assertEqual(LibraryDocument.objects.filter(is_downloaded=True).count(), 3)

    def test_une_source_muette_sur_le_poids_est_coupee_pendant_le_transfert(self):
        """Sans Content-Length, le seuil ne peut etre verifie qu'a l'ecriture."""
        seuils = []

        def _telecharger(url, chemin, taille_max=0):
            seuils.append(taille_max)
            raise import_bkalan._TropGros(url)

        with patch.object(import_bkalan, "taille_distante", lambda url: None):
            with patch.object(import_bkalan, "telecharger_fichier", _telecharger):
                self._importer("--serie", "10-eme-CG", "--jobs", "1", "--taille-max", "5")

        # Le seuil est bien transmis au transfert, en octets.
        self.assertEqual(set(seuils), {5 * 1024 * 1024})
        self.assertEqual(LibraryDocument.objects.filter(is_downloaded=True).count(), 0)
        self.assertFalse(LibraryDocument.objects.exclude(import_error="").exists())

    def test_un_head_refuse_ne_condamne_pas_le_document(self):
        """43 documents repondent deja 401 a la source: le HEAD peut echouer."""

        def _sonde_en_panne(url):
            raise OSError("HEAD refuse")

        def _telecharger(url, chemin, taille_max=0):
            with open(chemin, "wb") as sortie:
                sortie.write(b"%PDF-1.4 leger")
            return 14

        with patch.object(import_bkalan, "taille_distante", _sonde_en_panne):
            with patch.object(import_bkalan, "telecharger_fichier", _telecharger):
                self._importer("--serie", "10-eme-CG", "--jobs", "1", "--taille-max", "5")

        self.assertEqual(LibraryDocument.objects.filter(is_downloaded=True).count(), 3)

    def test_sans_seuil_la_source_n_est_pas_sondee(self):
        """Le HEAD est un aller-retour de plus: inutile quand tout est pris."""
        sondes = []

        def _telecharger(url, chemin, taille_max=0):
            with open(chemin, "wb") as sortie:
                sortie.write(b"%PDF")
            return 4

        def _sonde(url):
            sondes.append(url)
            return 10

        with patch.object(import_bkalan, "taille_distante", _sonde):
            with patch.object(import_bkalan, "telecharger_fichier", _telecharger):
                self._importer("--serie", "10-eme-CG", "--jobs", "1")

        self.assertEqual(sondes, [])


class LibraryDocumentApiTests(APITestCase):
    """Le catalogue vu par l'API, et le fichier lui-meme."""

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.collection = LibraryCollection.objects.create(
            code="TSExp", label="Terminale Sciences Expérimentales", position=5
        )
        cls.maths = LibraryCategory.objects.create(
            collection=cls.collection, name="Mathematiques", position=0
        )
        cls.philo = LibraryCategory.objects.create(
            collection=cls.collection, name="Philosophie", position=1
        )
        cls.suites = LibraryDocument.objects.create(
            category=cls.maths,
            title="Suites-numeriques",
            source_url="https://bkalan.ml/api/files/WhatsApp/TSExp/Mathematiques/BK_Suites.pdf",
        )
        LibraryDocument.objects.create(
            category=cls.philo,
            title="Le-desir",
            source_url="https://bkalan.ml/api/files/WhatsApp/TSExp/Philosophie/BK_Desir.pdf",
        )
        cls.directeur = cls._compte("dir_biblio", UserRole.DIRECTOR)

    @classmethod
    def _compte(cls, username, role):
        return User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=role,
            etablissement=cls.etablissement,
        )

    def test_a_series_carries_its_subjects_and_their_counts(self):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.get("/api/library-collections/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        serie = reponse.data[0]
        self.assertEqual(serie["code"], "TSExp")
        self.assertEqual(serie["document_count"], 2)
        self.assertEqual(
            [(c["name"], c["document_count"]) for c in serie["categories"]],
            [("Mathematiques", 1), ("Philosophie", 1)],
        )

    def test_the_list_filters_by_series_subject_and_words(self):
        self.client.force_authenticate(self.directeur)

        def _titres(requete):
            reponse = self.client.get(f"/api/library-documents/{requete}")
            self.assertEqual(reponse.status_code, status.HTTP_200_OK)
            lignes = reponse.data.get("results", reponse.data)
            return sorted(ligne["title"] for ligne in lignes)

        self.assertEqual(_titres("?collection=TSExp"), ["Le-desir", "Suites-numeriques"])
        self.assertEqual(_titres(f"?category={self.philo.id}"), ["Le-desir"])
        self.assertEqual(_titres("?search=suites"), ["Suites-numeriques"])
        self.assertEqual(_titres("?collection=TLL"), [])

    @override_settings(MEDIA_ROOT="/tmp/gs-library-tests")
    def test_a_repatriated_file_is_served_from_the_storage(self):
        self.suites.file.save("BK_Suites.pdf", ContentFile(b"%PDF-1.4 local"), save=False)
        self.suites.is_downloaded = True
        self.suites.save(update_fields=["file", "is_downloaded"])
        self.addCleanup(self.suites.file.delete, save=False)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(reponse.streaming_content), b"%PDF-1.4 local")

    def test_a_missing_file_is_relayed_from_the_source(self):
        """C'est tout le mode hybride: l'ecran marche avant le rapatriement."""
        amont_factice = _AmontFactice(b"%PDF-1.4 amont")

        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen", return_value=amont_factice) as amont:
            reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(reponse.streaming_content), b"%PDF-1.4 amont")
        amont.assert_called_once()
        # Le flux amont est referme une fois consomme: il vit plus longtemps
        # que la vue, et une connexion oubliee reste comptee chez la source.
        self.assertTrue(amont_factice.ferme)

    def test_le_relais_lit_par_blocs_et_non_ligne_par_ligne(self):
        """Sur du binaire, la decoupe par lignes n'a aucun sens.

        StreamingHttpResponse iterant l'objet amont appelait readline(): un
        PDF sans retour a la ligne partait en un seul bloc, un PDF qui en
        contient beaucoup partait en milliers de morceaux. La vue impose donc
        sa propre taille de lecture.
        """
        amont_factice = _AmontFactice(b"x" * 200_000)

        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen", return_value=amont_factice):
            reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")
        b"".join(reponse.streaming_content)

        # 200 000 octets: trois blocs pleins, un bloc partiel, et une derniere
        # lecture vide qui signale la fin du flux.
        self.assertEqual(
            amont_factice.tailles_demandees,
            [64 * 1024] * 5,
            "la vue doit lire par blocs de 64 Ko, jusqu'a epuisement",
        )

    def test_le_document_relaye_annonce_sa_taille_et_son_cache(self):
        """Sans Content-Length, le client ne peut afficher aucune progression."""
        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen", return_value=_AmontFactice(b"%PDF-1.4 amont")):
            reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")
        b"".join(reponse.streaming_content)

        self.assertEqual(reponse["Content-Length"], "14")
        self.assertIn("private", reponse["Cache-Control"])
        self.assertTrue(reponse["ETag"])

    def test_une_relecture_ne_retraverse_pas_le_reseau(self):
        """Le coeur du gain: rouvrir un document deja lu ne coute rien."""
        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen", return_value=_AmontFactice(b"%PDF-1.4 amont")):
            premiere = self.client.get(f"/api/library-documents/{self.suites.id}/file/")
        b"".join(premiere.streaming_content)

        with patch("apps.school.views.urlopen") as amont:
            seconde = self.client.get(
                f"/api/library-documents/{self.suites.id}/file/",
                HTTP_IF_NONE_MATCH=premiere["ETag"],
            )

        self.assertEqual(seconde.status_code, status.HTTP_304_NOT_MODIFIED)
        amont.assert_not_called()

    def test_le_rapatriement_d_un_document_perime_la_copie_du_client(self):
        """Passer du relais au stockage change la chaine qui sert le fichier."""
        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen", return_value=_AmontFactice(b"%PDF-1.4 amont")):
            avant = self.client.get(f"/api/library-documents/{self.suites.id}/file/")
        b"".join(avant.streaming_content)

        self.suites.file.save("BK_Suites.pdf", ContentFile(b"%PDF-1.4 local"), save=False)
        self.suites.is_downloaded = True
        self.suites.size_bytes = 14
        self.suites.save(update_fields=["file", "is_downloaded", "size_bytes"])
        self.addCleanup(self.suites.file.delete, save=False)

        apres = self.client.get(
            f"/api/library-documents/{self.suites.id}/file/",
            HTTP_IF_NONE_MATCH=avant["ETag"],
        )

        self.assertEqual(apres.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(apres.streaming_content), b"%PDF-1.4 local")

    def test_the_relay_refuses_a_foreign_host(self):
        """Sans cette borne, un source_url modifie ferait un proxy ouvert."""
        self.suites.source_url = "https://exemple.invalide/piege.pdf"
        self.suites.save(update_fields=["source_url"])

        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen") as amont:
            reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        amont.assert_not_called()


@override_settings(LIBRARY_RELAY_SOURCE=False)
class LibraryRelaisFermeTests(APITestCase):
    """Le serveur d'une ecole sans Internet.

    Le relais y echouait de toute facon, mais il echouait mal: `urlopen`
    faisait patienter le lecteur le temps de son delai d'attente avant de
    rendre une erreur technique, et immobilisait pendant ce temps un worker
    qui aurait servi d'autres pages. Ferme, il ne coute plus rien et dit ce
    qu'il faut faire.
    """

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.collection = LibraryCollection.objects.create(
            code="TSExp", label="Terminale Sciences Expérimentales", position=5
        )
        cls.maths = LibraryCategory.objects.create(
            collection=cls.collection, name="Mathematiques", position=0
        )
        cls.suites = LibraryDocument.objects.create(
            category=cls.maths,
            title="Suites-numeriques",
            source_url="https://bkalan.ml/api/files/WhatsApp/TSExp/Mathematiques/BK_Suites.pdf",
        )
        cls.directeur = User.objects.create_user(
            username="dir_hors_ligne",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def test_le_relais_ferme_repond_sans_toucher_au_reseau(self):
        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen") as amont:
            reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")

        self.assertEqual(reponse.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        # L'assertion qui porte le sens: c'est l'appel evite qui rend la main
        # au lecteur tout de suite au lieu de le faire patienter.
        amont.assert_not_called()
        self.assertIn("rapatrie", reponse.data["detail"])

    @override_settings(MEDIA_ROOT="/tmp/gs-library-tests")
    def test_le_relais_ferme_ne_gene_pas_un_document_rapatrie(self):
        self.suites.file.save("BK_Suites.pdf", ContentFile(b"%PDF-1.4 local"), save=False)
        self.suites.is_downloaded = True
        self.suites.save(update_fields=["file", "is_downloaded"])
        self.addCleanup(self.suites.file.delete, save=False)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(reponse.streaming_content), b"%PDF-1.4 local")

    def test_un_document_non_rapatrie_s_annonce_illisible(self):
        """L'ecran grise la ligne avant le clic, il ne l'apprend pas apres."""
        self.client.force_authenticate(self.directeur)

        reponse = self.client.get("/api/library-documents/?collection=TSExp")

        lignes = reponse.data.get("results", reponse.data)
        self.assertEqual([ligne["is_readable"] for ligne in lignes], [False])

    @override_settings(LIBRARY_RELAY_SOURCE=True)
    def test_le_relais_ouvert_laisse_le_document_lisible(self):
        self.client.force_authenticate(self.directeur)

        reponse = self.client.get("/api/library-documents/?collection=TSExp")

        lignes = reponse.data.get("results", reponse.data)
        self.assertEqual([ligne["is_readable"] for ligne in lignes], [True])


class LibraryRedirectionStockageTests(APITestCase):
    """La redirection vers le stockage: active, elle epargne le conteneur.

    Un PDF de 40 Mo relaye par le service consomme sa memoire et son unique
    dixieme de coeur pendant tout le transfert. Redirige, il ne le traverse
    pas. Le reglage reste ferme par defaut: sur le web, la redirection vers
    un autre domaine dependrait du CORS du bucket.
    """

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.directeur = User.objects.create_user(
            username="directeur_redirection",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        collection = LibraryCollection.objects.create(
            code="TSExp", label="Terminale Sciences Experimentales", source_url="https://bkalan.ml/x"
        )
        categorie = LibraryCategory.objects.create(collection=collection, name="Mathematiques")
        cls.document = LibraryDocument.objects.create(
            category=categorie,
            title="Suites",
            source_url="https://bkalan.ml/api/files/WhatsApp/TSExp/Mathematiques/BK_Suites.pdf",
        )

    def setUp(self):
        repertoire = tempfile.mkdtemp(prefix="gs-redirection-")
        self.addCleanup(shutil.rmtree, repertoire, ignore_errors=True)
        reglage = override_settings(MEDIA_ROOT=repertoire)
        reglage.enable()
        self.addCleanup(reglage.disable)

        self.document.file.save("BK_Suites.pdf", ContentFile(b"%PDF-1.4 local"), save=False)
        self.document.is_downloaded = True
        self.document.size_bytes = 14
        self.document.save(update_fields=["file", "is_downloaded", "size_bytes"])
        self.client.force_authenticate(self.directeur)

    def _lire(self):
        return self.client.get(f"/api/library-documents/{self.document.id}/file/")

    @override_settings(LIBRARY_STORAGE_REDIRECT=True)
    def test_une_url_signee_devient_une_redirection(self):
        signee = "https://projet.supabase.co/storage/v1/BK_Suites.pdf?X-Amz-Signature=abc"
        with patch.object(type(self.document.file), "url", property(lambda self: signee)):
            reponse = self._lire()

        self.assertEqual(reponse.status_code, status.HTTP_302_FOUND)
        self.assertEqual(reponse["Location"], signee)

    @override_settings(LIBRARY_STORAGE_REDIRECT=True)
    def test_une_url_nue_n_est_jamais_servie_en_redirection(self):
        """Sans signature, l'adresse resterait valable pour qui l'a vue passer."""
        nue = "https://projet.supabase.co/storage/v1/BK_Suites.pdf"
        with patch.object(type(self.document.file), "url", property(lambda self: nue)):
            reponse = self._lire()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(reponse.streaming_content), b"%PDF-1.4 local")

    @override_settings(LIBRARY_STORAGE_REDIRECT=True)
    def test_un_stockage_sur_disque_sert_le_fichier_comme_avant(self):
        """MEDIA_URL rend un chemin relatif: il ne redirige nulle part."""
        reponse = self._lire()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(reponse.streaming_content), b"%PDF-1.4 local")

    @override_settings(LIBRARY_STORAGE_REDIRECT=False)
    def test_le_reglage_ferme_laisse_le_fichier_passer_par_l_api(self):
        signee = "https://projet.supabase.co/storage/v1/BK_Suites.pdf?X-Amz-Signature=abc"
        with patch.object(type(self.document.file), "url", property(lambda self: signee)):
            reponse = self._lire()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)

    @override_settings(LIBRARY_STORAGE_REDIRECT=True, AWS_QUERYSTRING_EXPIRE=600)
    def test_l_adresse_n_est_pas_gardee_plus_longtemps_que_sa_signature(self):
        """Une adresse cachee au-dela de son expiration mene a un 403."""
        signee = "https://projet.supabase.co/storage/v1/BK_Suites.pdf?X-Amz-Signature=abc"
        with patch.object(type(self.document.file), "url", property(lambda self: signee)):
            reponse = self._lire()

        self.assertEqual(reponse["Cache-Control"], "private, max-age=600")

    @override_settings(LIBRARY_STORAGE_REDIRECT=True)
    def test_un_stockage_en_panne_ne_prive_pas_le_lecteur(self):
        def _casse(self):
            raise ValueError("stockage muet")

        with patch.object(type(self.document.file), "url", property(_casse)):
            reponse = self._lire()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(reponse.streaming_content), b"%PDF-1.4 local")


class LibraryAccessTests(_StockageTemporaireMixin, APITestCase):
    """Qui lit le fonds, qui l'alimente: la matrice, rien d'autre."""

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        cls.collection = LibraryCollection.objects.create(code="TSExp", label="TSExp")
        cls.categorie = LibraryCategory.objects.create(
            collection=cls.collection, name="Mathematiques"
        )
        LibraryDocument.objects.create(
            category=cls.categorie,
            title="Suites",
            source_url="https://bkalan.ml/api/files/WhatsApp/TSExp/Mathematiques/BK_S.pdf",
            origin="import",
        )
        # L'etagere propre a l'ecole: c'est la seule que l'application
        # alimente, le fonds commun n'entre que par la commande d'import.
        cls.etagere = LibraryCollection.objects.create(
            code="Interne", label="Documents de l'école", etablissement=cls.etablissement
        )
        cls.matiere = LibraryCategory.objects.create(
            collection=cls.etagere, name="Reglement"
        )
        cls.comptes = {
            role: User.objects.create_user(
                username=f"biblio_{role}",
                password="Pass1234!",
                role=role,
                etablissement=cls.etablissement,
            )
            for role in (
                UserRole.SUPER_ADMIN,
                UserRole.DIRECTOR,
                UserRole.SUPERVISOR,
                UserRole.TEACHER,
                UserRole.ACCOUNTANT,
                UserRole.PARENT,
                UserRole.STUDENT,
            )
        }

    def _lire(self, role):
        self.client.force_authenticate(self.comptes[role])
        return self.client.get("/api/library-documents/")

    def test_the_whole_school_reads_the_shelf(self):
        """Le fonds n'est pas cloisonne: l'eleve de 11e lit les annales de TSExp."""
        for role in (
            UserRole.SUPER_ADMIN,
            UserRole.DIRECTOR,
            UserRole.SUPERVISOR,
            UserRole.TEACHER,
            UserRole.PARENT,
            UserRole.STUDENT,
        ):
            with self.subTest(role=role):
                self.assertEqual(self._lire(role).status_code, status.HTTP_200_OK)

    def test_the_accountant_has_no_business_here(self):
        self.assertEqual(self._lire(UserRole.ACCOUNTANT).status_code, status.HTTP_403_FORBIDDEN)

    def test_a_student_does_not_add_a_document(self):
        self.client.force_authenticate(self.comptes[UserRole.STUDENT])
        reponse = self.client.post(
            "/api/library-documents/",
            {
                "title": "Faux",
                "category": self.matiere.id,
                "file": _pdf("faux.pdf"),
            },
            format="multipart",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_the_supervisor_adds_but_does_not_delete(self):
        """Ecriture (E) pour le surveillant, suppression reservee a l'administration."""
        self.client.force_authenticate(self.comptes[UserRole.SUPERVISOR])
        ajout = self.client.post(
            "/api/library-documents/",
            {
                "title": "Annales 2026",
                "category": self.matiere.id,
                "file": _pdf("annales-2026.pdf"),
            },
            format="multipart",
        )
        self.assertEqual(ajout.status_code, status.HTTP_201_CREATED, ajout.data)

        retrait = self.client.delete(f"/api/library-documents/{ajout.data['id']}/")
        self.assertEqual(retrait.status_code, status.HTTP_403_FORBIDDEN)


class LibraryUploadTests(_StockageTemporaireMixin, APITestCase):
    """Le depot d'un PDF depuis l'application.

    Le fonds importe restait en lecture seule: un etablissement qui voulait
    diffuser son reglement interieur ou une fiche de revision maison n'avait
    nulle part ou la mettre. Il pose desormais ses propres etageres, a cote
    du fonds commun et sans y toucher.
    """

    @classmethod
    def setUpTestData(cls):
        cls.ecole = Etablissement.objects.create(name="LTOB")
        cls.voisine = Etablissement.objects.create(name="Lycee Askia")

        # Le fonds commun, tel que l'import le laisse.
        cls.commun = LibraryCollection.objects.create(code="TSExp", label="TSExp")
        cls.commun_maths = LibraryCategory.objects.create(
            collection=cls.commun, name="Mathematiques"
        )
        LibraryDocument.objects.create(
            category=cls.commun_maths,
            title="Suites",
            source_url="https://bkalan.ml/api/files/WhatsApp/TSExp/Mathematiques/BK_S.pdf",
            origin=LibraryDocumentOrigin.IMPORT,
        )

        cls.directeur = cls._compte("dir_ltob", UserRole.DIRECTOR, cls.ecole)
        cls.directeur_voisin = cls._compte("dir_askia", UserRole.DIRECTOR, cls.voisine)
        cls.eleve = cls._compte("eleve_ltob", UserRole.STUDENT, cls.ecole)

    @classmethod
    def _compte(cls, username, role, etablissement):
        return User.objects.create_user(
            username=username, password="Pass1234!", role=role, etablissement=etablissement
        )

    def _etagere(self, etablissement, code="Interne"):
        collection = LibraryCollection.objects.create(
            code=code, label="Documents internes", etablissement=etablissement
        )
        return LibraryCategory.objects.create(
            collection=collection, name="Administratif"
        )

    def _deposer(self, categorie, fichier=None, titre="Reglement interieur", **extra):
        charge = {
            "title": titre,
            "category": categorie.id,
            "file": fichier if fichier is not None else _pdf("reglement.pdf"),
        }
        charge.update(extra)
        return self.client.post("/api/library-documents/", charge, format="multipart")

    # --- Le depot lui-meme --------------------------------------------------

    def test_un_pdf_depose_entre_dans_le_fonds_de_son_ecole(self):
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)

        reponse = self._deposer(categorie, _pdf("reglement.pdf", poids=2048))

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        document = LibraryDocument.objects.get(id=reponse.data["id"])
        self.assertEqual(document.etablissement, self.ecole)
        self.assertEqual(document.origin, LibraryDocumentOrigin.UPLOAD)
        self.assertEqual(document.uploaded_by, self.directeur)
        # Pose par le serveur d'apres le fichier, jamais annonce par le client.
        self.assertTrue(document.is_downloaded)
        self.assertEqual(document.size_bytes, 2048)
        self.assertEqual(document.source_url, "")

    def test_le_fichier_depose_se_relit_par_l_api(self):
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)
        depot = self._deposer(categorie, _pdf("reglement.pdf", poids=512))

        lecture = self.client.get(f"/api/library-documents/{depot.data['id']}/file/")

        self.assertEqual(lecture.status_code, status.HTTP_200_OK)
        self.assertEqual(lecture["Content-Type"], "application/pdf")
        self.assertTrue(b"".join(lecture.streaming_content).startswith(b"%PDF-"))

    def test_le_chemin_de_stockage_porte_l_ecole(self):
        """Deux ecoles peuvent deposer leur « reglement.pdf » sans se marcher dessus."""
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)
        depot = self._deposer(categorie)

        document = LibraryDocument.objects.get(id=depot.data["id"])
        self.assertTrue(
            document.file.name.startswith(f"library_docs/etab_{self.ecole.id}/"),
            document.file.name,
        )

    def test_deux_ecoles_deposent_le_meme_nom_sans_collision(self):
        for compte, etablissement in (
            (self.directeur, self.ecole),
            (self.directeur_voisin, self.voisine),
        ):
            self.client.force_authenticate(compte)
            self._deposer(self._etagere(etablissement))

        chemins = set(LibraryDocument.objects.exclude(file="").values_list("file", flat=True))
        self.assertEqual(len(chemins), 2, chemins)

    # --- Ce que le depot refuse ---------------------------------------------

    def test_un_fichier_qui_n_est_pas_un_pdf_est_refuse(self):
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)

        reponse = self._deposer(
            categorie,
            SimpleUploadedFile("notes.txt", b"bonjour", content_type="text/plain"),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("PDF", str(reponse.data["file"]))

    def test_un_executable_renomme_en_pdf_est_refuse(self):
        """L'extension ne prouve rien: c'est la signature du format qui decide."""
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)

        reponse = self._deposer(
            categorie,
            SimpleUploadedFile("piege.pdf", b"MZ\x90\x00 binaire", content_type="application/pdf"),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(LibraryDocument.objects.filter(origin="upload").count(), 0)

    @override_settings(LIBRARY_UPLOAD_MAX_MB=1)
    def test_un_fichier_trop_lourd_est_refuse(self):
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)

        reponse = self._deposer(categorie, _pdf("gros.pdf", poids=2 * 1024 * 1024))

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("1 Mo", str(reponse.data["file"]))

    def test_un_document_sans_fichier_ni_source_est_refuse(self):
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)

        reponse = self.client.post(
            "/api/library-documents/",
            {"title": "Vide", "category": categorie.id},
            format="multipart",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_eleve_ne_depose_rien(self):
        self.client.force_authenticate(self.eleve)
        categorie = self._etagere(self.ecole)

        self.assertEqual(
            self._deposer(categorie).status_code, status.HTTP_403_FORBIDDEN
        )

    # --- Le fonds commun reste intouchable ----------------------------------

    def test_le_fonds_commun_n_accepte_pas_de_depot(self):
        self.client.force_authenticate(self.directeur)

        reponse = self._deposer(self.commun_maths)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("fonds commun", str(reponse.data).lower())

    def test_un_document_du_fonds_commun_ne_se_supprime_pas(self):
        self.client.force_authenticate(self.directeur)
        document = LibraryDocument.objects.get(title="Suites")

        reponse = self.client.delete(f"/api/library-documents/{document.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(LibraryDocument.objects.filter(id=document.id).exists())

    def test_un_document_du_fonds_commun_ne_se_renomme_pas(self):
        self.client.force_authenticate(self.directeur)
        document = LibraryDocument.objects.get(title="Suites")

        reponse = self.client.patch(
            f"/api/library-documents/{document.id}/",
            {"title": "Renomme"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    # --- Cloisonnement entre ecoles -----------------------------------------

    def test_l_ecole_voisine_ne_voit_pas_le_document_depose(self):
        self.client.force_authenticate(self.directeur)
        self._deposer(self._etagere(self.ecole), titre="Reglement LTOB")

        self.client.force_authenticate(self.directeur_voisin)
        titres = [
            ligne["title"]
            for ligne in self.client.get("/api/library-documents/").data["results"]
        ]

        self.assertNotIn("Reglement LTOB", titres)
        # Le fonds commun, lui, reste lisible par les deux.
        self.assertIn("Suites", titres)

    def test_l_ecole_voisine_ne_depose_pas_dans_l_etagere_d_autrui(self):
        categorie = self._etagere(self.ecole)
        self.client.force_authenticate(self.directeur_voisin)

        reponse = self._deposer(categorie)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_etagere_d_une_ecole_ne_s_affiche_pas_chez_la_voisine(self):
        LibraryCollection.objects.create(
            code="Interne", label="Documents internes", etablissement=self.ecole
        )
        self.client.force_authenticate(self.directeur_voisin)

        codes = [
            ligne["code"]
            for ligne in self.client.get("/api/library-collections/").data
        ]

        self.assertEqual(codes, ["TSExp"])

    # --- Le cycle de vie d'un document depose -------------------------------

    def test_le_document_depose_se_renomme_et_change_de_matiere(self):
        self.client.force_authenticate(self.directeur)
        categorie = self._etagere(self.ecole)
        autre = LibraryCategory.objects.create(
            collection=categorie.collection, name="Fiches"
        )
        depot = self._deposer(categorie)

        reponse = self.client.patch(
            f"/api/library-documents/{depot.data['id']}/",
            {"title": "Reglement 2026", "category": autre.id},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        document = LibraryDocument.objects.get(id=depot.data["id"])
        self.assertEqual(document.title, "Reglement 2026")
        self.assertEqual(document.category, autre)

    def test_la_suppression_emporte_le_fichier_du_stockage(self):
        self.client.force_authenticate(self.directeur)
        depot = self._deposer(self._etagere(self.ecole))
        document = LibraryDocument.objects.get(id=depot.data["id"])
        chemin = self.media_root / document.file.name
        self.assertTrue(chemin.exists())

        reponse = self.client.delete(f"/api/library-documents/{document.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(chemin.exists())

    def test_le_remplacement_du_fichier_efface_l_ancien(self):
        self.client.force_authenticate(self.directeur)
        depot = self._deposer(self._etagere(self.ecole))
        ancien = self.media_root / LibraryDocument.objects.get(id=depot.data["id"]).file.name

        reponse = self.client.patch(
            f"/api/library-documents/{depot.data['id']}/",
            {"file": _pdf("reglement.pdf", poids=4096)},
            format="multipart",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        document = LibraryDocument.objects.get(id=depot.data["id"])
        self.assertEqual(document.size_bytes, 4096)
        self.assertFalse(ancien.exists())

    # --- Les etageres de l'ecole --------------------------------------------

    def test_l_ecole_cree_sa_serie_et_sa_matiere(self):
        self.client.force_authenticate(self.directeur)

        serie = self.client.post(
            "/api/library-collections/",
            {"code": "Interne", "label": "Documents de l'école"},
            format="json",
        )
        self.assertEqual(serie.status_code, status.HTTP_201_CREATED, serie.data)
        self.assertFalse(serie.data["is_commun"])

        matiere = self.client.post(
            "/api/library-categories/",
            {"collection": serie.data["id"], "name": "Administratif"},
            format="json",
        )

        self.assertEqual(matiere.status_code, status.HTTP_201_CREATED, matiere.data)
        self.assertEqual(
            LibraryCollection.objects.get(id=serie.data["id"]).etablissement, self.ecole
        )

    def test_deux_ecoles_nomment_leur_serie_pareil(self):
        """« Interne » chez l'une n'empeche pas « Interne » chez l'autre."""
        for compte in (self.directeur, self.directeur_voisin):
            self.client.force_authenticate(compte)
            reponse = self.client.post(
                "/api/library-collections/",
                {"code": "Interne", "label": "Documents internes"},
                format="json",
            )
            self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_une_matiere_ne_s_ajoute_pas_au_fonds_commun(self):
        self.client.force_authenticate(self.directeur)

        reponse = self.client.post(
            "/api/library-categories/",
            {"collection": self.commun.id, "name": "Matiere pirate"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
