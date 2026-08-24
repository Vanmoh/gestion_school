"""La bibliotheque numerique: import du fonds, catalogue, acces.

Le module « Bibliotheque » ne connaissait que l'ouvrage physique (Book,
Borrow): un titre, un ISBN, des exemplaires. Le fonds documentaire -- annales
et brochures rangees par serie et par matiere -- n'avait ni modele ni ecran.

Aucun test ne sort sur le reseau: les pages de la source sont figees en
fixture et le telechargement est remplace par une fonction locale.
"""

from io import StringIO
from pathlib import Path
from unittest.mock import patch

from django.conf import settings
from django.core.files.base import ContentFile
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
        def _faux_telechargement(url, chemin):
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

        def _compte(url, cible):
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
        def _refus(url, chemin):
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
        def _refus(url, chemin):
            raise OSError("401 Unauthorized")

        journal = StringIO()
        with patch.object(import_bkalan, "telecharger_fichier", _refus):
            self._importer("--serie", "10-eme-CG", "--jobs", "1", stdout=journal)

        sortie = journal.getvalue()
        self.assertIn("3/3 (100 %)", sortie)
        self.assertIn("3 en echec", sortie)

    def test_a_recorded_error_is_not_retried_by_default(self):
        """Sinon chaque execution rejoue les 40 fichiers morts a la source."""
        def _refus(url, chemin):
            raise OSError("401 Unauthorized")

        with patch.object(import_bkalan, "telecharger_fichier", _refus):
            self._importer("--serie", "10-eme-CG", "--jobs", "1")

        essais = []

        def _compte(url, chemin):
            essais.append(url)
            raise OSError("401 Unauthorized")

        with patch.object(import_bkalan, "telecharger_fichier", _compte):
            self._importer("--serie", "10-eme-CG", "--jobs", "1")
        self.assertEqual(essais, [])

        with patch.object(import_bkalan, "telecharger_fichier", _compte):
            self._importer("--serie", "10-eme-CG", "--jobs", "1", "--retenter-erreurs")
        self.assertEqual(len(essais), 3)


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

        class _Amont:
            headers = {"Content-Type": "application/pdf", "Content-Length": "15"}

            def __iter__(self):
                return iter([b"%PDF-1.4 amont"])

        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen", return_value=_Amont()) as amont:
            reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(b"".join(reponse.streaming_content), b"%PDF-1.4 amont")
        amont.assert_called_once()

    def test_the_relay_refuses_a_foreign_host(self):
        """Sans cette borne, un source_url modifie ferait un proxy ouvert."""
        self.suites.source_url = "https://exemple.invalide/piege.pdf"
        self.suites.save(update_fields=["source_url"])

        self.client.force_authenticate(self.directeur)
        with patch("apps.school.views.urlopen") as amont:
            reponse = self.client.get(f"/api/library-documents/{self.suites.id}/file/")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        amont.assert_not_called()


class LibraryAccessTests(APITestCase):
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
                "category": self.categorie.id,
                "source_url": "https://bkalan.ml/api/files/WhatsApp/TSExp/x.pdf",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_the_supervisor_adds_but_does_not_delete(self):
        """Ecriture (E) pour le surveillant, suppression reservee a l'administration."""
        self.client.force_authenticate(self.comptes[UserRole.SUPERVISOR])
        ajout = self.client.post(
            "/api/library-documents/",
            {
                "title": "Annales 2026",
                "category": self.categorie.id,
                "source_url": "https://bkalan.ml/api/files/WhatsApp/TSExp/Mathematiques/BK_2026.pdf",
            },
            format="json",
        )
        self.assertEqual(ajout.status_code, status.HTTP_201_CREATED)

        retrait = self.client.delete(f"/api/library-documents/{ajout.data['id']}/")
        self.assertEqual(retrait.status_code, status.HTTP_403_FORBIDDEN)
