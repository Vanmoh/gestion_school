"""Importe le fonds documentaire BKalan dans la bibliotheque numerique.

Neuf pages, une par serie du secondaire malien, listent des PDF ranges par
matiere. La commande fait deux choses distinctes, dans cet ordre:

1. le catalogue -- les series, les matieres et les documents entrent en base
   en quelques secondes, et l'ecran est utilisable immediatement: tant qu'un
   PDF n'est pas rapatrie, l'API relaie la source;
2. le rapatriement -- les fichiers sont telecharges vers le stockage de
   l'application, ce qui rend le fonds independant de bkalan.ml.

Elle est rejouable: `source_url` porte l'unicite, une seconde execution ne
cree aucun doublon et ne retelecharge que ce qui manque. Un fichier deja
range au bon endroit dans le stockage est adopte tel quel, meme si la base
ne le connait plus -- les media survivent souvent a la base.

    manage.py import_bkalan --catalogue-seul     # les 1257 entrees
    manage.py import_bkalan                      # + les fichiers manquants
    manage.py import_bkalan --serie TSExp        # une seule serie
    manage.py import_bkalan --taille-max 5       # seulement les PDF <= 5 Mo
    manage.py import_bkalan --catalogue-seul --si-vide   # au demarrage

Le fonds pese environ 6,4 Go, mais sa moitie basse est minuscule: 86 % des
documents tiennent sous 5 Mo et ne font ensemble que 0,93 Go, tandis qu'une
centaine de gros fichiers -- jusqu'a 127 Mo piece -- portent le reste. D'ou
`--taille-max`: un stockage a la capacite comptee prend la partie legere, un
disque local prend tout. Ce qui depasse le seuil reste relaye depuis la
source, exactement comme avant son rapatriement.
"""

from __future__ import annotations

import os
import tempfile
from concurrent.futures import ThreadPoolExecutor
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote
from urllib.request import Request, urlopen

from django.core.exceptions import SuspiciousOperation
from django.core.files import File
from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils.text import get_valid_filename

from apps.school.models import (
    LibraryCategory,
    LibraryCollection,
    LibraryDocument,
    library_document_path,
)

BASE_URL = "https://bkalan.ml/api/files/WhatsApp"

# La source compare le chemin brut: une parenthese encodee en %28 lui vaut un
# 401, alors que le meme fichier repond 200 si la parenthese passe telle
# quelle. On ne code donc que ce que l'URL exige -- espaces et accents.
#
# Les crochets suivent la meme regle: `BK_Bac_2023_Tsexp[1].pdf` repond 401 en
# %5B et 200 tel quel. Ils ne figuraient pas ici parce que la RFC 3986 les
# reserve aux adresses IPv6 -- reserve dont la source ne sait rien.
SAFE_URL = "/()[]!*'~$&+,;=:@"

# Code sur le site -> libelle affiche. L'ordre est celui de la scolarite, pas
# celui du site: c'est ainsi que l'ecran presente les series.
SERIES = (
    ("10-eme-CG", "10ème Commun Général"),
    ("11-eme-Sciences", "11ème Sciences"),
    ("11-eme-SES", "11ème SES"),
    ("11-eme-Lettres", "11ème Lettres"),
    ("TSE", "Terminale Sciences Exactes"),
    ("TSExp", "Terminale Sciences Expérimentales"),
    ("TSEco", "Terminale Sciences Économiques"),
    ("TSS", "Terminale Sciences Sociales"),
    ("TLL", "Terminale Lettres-Langues"),
)


class _ParseurDocs(HTMLParser):
    """Releve les liens PDF d'une page docs.html, dans l'ordre d'affichage.

    La matiere n'est pas lue sur les dossiers de l'arbre mais sur le premier
    segment du lien: les deux disent la meme chose, et le lien reste juste
    meme si la mise en page change.
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.liens = []

    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        attributs = dict(attrs)
        href = attributs.get("href") or ""
        if href.lower().endswith(".pdf"):
            self.liens.append(href)


def lire_page(url):
    """Contenu HTML d'une page de serie. Point d'injection des tests."""
    with urlopen(url, timeout=60) as reponse:  # noqa: S310 - hote fixe
        return reponse.read().decode("utf-8", errors="replace")


def taille_distante(url):
    """Poids annonce par la source, ou None si elle ne le dit pas.

    Une requete HEAD coute un aller-retour, contre plusieurs dizaines de
    megaoctets pour decouvrir la meme chose en telechargeant. Point
    d'injection des tests, comme lire_page et telecharger_fichier.
    """
    requete = Request(url, method="HEAD")
    with urlopen(requete, timeout=30) as reponse:  # noqa: S310 - hote fixe
        annonce = reponse.headers.get("Content-Length")
    try:
        return int(annonce) if annonce is not None else None
    except (TypeError, ValueError):
        return None


class _TropGros(Exception):
    """Le fichier depasse le seuil demande: transfert interrompu."""


def telecharger_fichier(url, chemin, taille_max=0):
    """Ecrit le PDF distant dans `chemin`. Point d'injection des tests.

    Le seuil est verifie pendant l'ecriture et pas seulement avant: la source
    n'annonce pas toujours Content-Length, et un fichier de 127 Mo qu'on
    croyait petit ne doit pas descendre en entier avant d'etre ecarte.
    """
    with urlopen(url, timeout=180) as amont, open(chemin, "wb") as sortie:  # noqa: S310
        taille = 0
        while True:
            morceau = amont.read(64 * 1024)
            if not morceau:
                break
            taille += len(morceau)
            if taille_max and taille > taille_max:
                raise _TropGros(url)
            sortie.write(morceau)
    return taille


def documents_de_page(html):
    """[(matiere, nom de fichier, chemin relatif)] tels que la page les liste."""
    parseur = _ParseurDocs()
    parseur.feed(html)

    resultat = []
    for href in parseur.liens:
        segments = [unquote(part) for part in href.split("/") if part]
        if len(segments) < 2:
            # Un PDF pose a la racine n'a pas de matiere: on le range a part
            # plutot que de le perdre.
            resultat.append(("Autres", segments[-1] if segments else href, href))
            continue
        resultat.append((segments[0], segments[-1], href))
    return resultat


def titre_lisible(nom_fichier):
    """« BK_BAC-2019-SUJET.pdf » -> « BAC-2019-SUJET ».

    Le prefixe BK_ est la marque du collecteur, repetee sur 1257 lignes: elle
    n'aide pas a choisir un document. Le reste du nom est conserve tel quel,
    les tirets compris -- le reecrire abimerait « TSExp » ou « N°1 ».
    """
    nom = nom_fichier
    if nom.lower().endswith(".pdf"):
        nom = nom[:-4]
    if nom.startswith("BK_"):
        nom = nom[3:]
    return nom.strip() or nom_fichier


class Command(BaseCommand):
    help = "Importe les documents BKalan dans la bibliotheque numerique."

    def add_arguments(self, parser):
        parser.add_argument(
            "--serie",
            action="append",
            dest="series",
            help="Code de serie a traiter (repetable). Toutes par defaut.",
        )
        parser.add_argument(
            "--catalogue-seul",
            action="store_true",
            help="Cree les entrees sans telecharger les fichiers.",
        )
        parser.add_argument(
            "--jobs",
            type=int,
            default=4,
            help="Telechargements simultanes (4 par defaut).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=0,
            help="S'arrete apres N telechargements. 0 = sans limite.",
        )
        parser.add_argument(
            "--taille-max",
            type=float,
            default=0,
            dest="taille_max",
            metavar="MO",
            help=(
                "Ne rapatrie que les documents jusqu'a ce poids, en Mo. "
                "Au-dela, le document reste relaye depuis la source. "
                "0 (defaut) ne pose aucune limite."
            ),
        )
        parser.add_argument(
            "--retenter-erreurs",
            action="store_true",
            help="Retelecharge les documents marques en erreur.",
        )
        parser.add_argument(
            "--si-vide",
            action="store_true",
            help="Ne fait rien si les series visees sont deja cataloguees.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="N'ecrit rien: annonce ce que l'import ferait.",
        )
        parser.add_argument("--base-url", default=BASE_URL)

    def handle(self, *args, **options):
        codes = options.get("series") or [code for code, _ in SERIES]
        connus = dict(SERIES)
        inconnus = [code for code in codes if code not in connus]
        if inconnus:
            raise CommandError(
                f"Serie inconnue: {', '.join(inconnus)}. "
                f"Connues: {', '.join(connus)}."
            )

        # Le demarrage du conteneur rejoue la commande (entrypoint.sh), et
        # Render reveille le service bien plus souvent qu'il ne le deploie.
        # L'import est rejouable, mais relire neuf pages chez la source a
        # chaque reveil ne changerait rien a la base. Un catalogue present
        # dit que la premiere passe a eu lieu: cela suffit a s'arreter.
        if options["si_vide"] and LibraryDocument.objects.filter(
            category__collection__code__in=codes
        ).exists():
            self.stdout.write("Catalogue deja en place: rien a faire (--si-vide).")
            return

        self.base_url = options["base_url"].rstrip("/")
        self.dry_run = options["dry_run"]

        # Le rang d'affichage suit la scolarite (SERIES) et non l'ordre des
        # options: --serie TLL n'a pas a faire passer TLL en tete de l'ecran.
        rang = {code: index for index, (code, _) in enumerate(SERIES)}

        total_documents = 0
        for code in codes:
            total_documents += self._cataloguer(code, connus[code], rang[code])

        self.stdout.write(
            self.style.SUCCESS(f"Catalogue: {total_documents} documents references.")
        )

        if options["catalogue_seul"]:
            self.stdout.write("Rapatriement ignore (--catalogue-seul).")
            return
        if self.dry_run:
            self.stdout.write("Rapatriement ignore (--dry-run).")
            return

        self._rapatrier(
            codes=codes,
            jobs=max(1, options["jobs"]),
            limite=max(0, options["limit"]),
            retenter=options["retenter_erreurs"],
            taille_max=int(max(0.0, options["taille_max"]) * 1024 * 1024),
        )

    # --- Catalogue ---------------------------------------------------------

    def _cataloguer(self, code, libelle, position):
        url = f"{self.base_url}/{code}/docs.html"
        try:
            html = lire_page(url)
        except (HTTPError, URLError) as exc:
            self.stderr.write(self.style.ERROR(f"{code}: page illisible ({exc})"))
            return 0

        entrees = documents_de_page(html)
        if self.dry_run:
            matieres = {matiere for matiere, _, _ in entrees}
            self.stdout.write(
                f"{code}: {len(entrees)} documents, {len(matieres)} matieres (dry-run)"
            )
            return len(entrees)

        with transaction.atomic():
            collection, _ = LibraryCollection.objects.update_or_create(
                code=code,
                defaults={"label": libelle, "source_url": url, "position": position},
            )

            rangs = {}
            for matiere, nom_fichier, href in entrees:
                if matiere not in rangs:
                    rangs[matiere] = len(rangs)
                categorie, _ = LibraryCategory.objects.update_or_create(
                    collection=collection,
                    name=matiere,
                    defaults={"position": rangs[matiere]},
                )
                LibraryDocument.objects.update_or_create(
                    source_url=f"{self.base_url}/{code}/{quote(href, safe=SAFE_URL)}",
                    defaults={"category": categorie, "title": titre_lisible(nom_fichier)},
                )

        self.stdout.write(f"{code}: {len(entrees)} documents, {len(rangs)} matieres")
        return len(entrees)

    # --- Rapatriement ------------------------------------------------------

    def _rapatrier(self, codes, jobs, limite, retenter, taille_max=0):
        a_faire = LibraryDocument.objects.filter(
            category__collection__code__in=codes, is_downloaded=False
        ).select_related("category", "category__collection")
        if not retenter:
            a_faire = a_faire.filter(import_error="")
        a_faire = list(a_faire.order_by("id"))

        adoptes = self._adopter_le_disque(a_faire)
        if adoptes:
            self.stdout.write(
                f"{adoptes} fichiers deja sur le stockage: adoptes, pas retelecharges."
            )
        a_faire = [document for document in a_faire if not document.is_downloaded]

        # La limite compte les telechargements, pas les adoptions: --limit 10
        # doit ramener dix fichiers du reseau, pas dix moins ceux qui etaient
        # deja la.
        if limite:
            a_faire = a_faire[:limite]

        if not a_faire:
            self.stdout.write("Rien a rapatrier: tout est deja en place.")
            return

        total = len(a_faire)
        borne = (
            f", jusqu'a {taille_max / 1048576:.0f} Mo piece" if taille_max else ""
        )
        self.stdout.write(
            f"Rapatriement de {total} fichiers ({jobs} en parallele{borne})..."
        )

        reussis = 0
        echecs = 0
        ignores = 0
        octets = 0

        def annoncer():
            """Une ligne d'avancement tous les vingt-cinq fichiers traites.

            Elle compte les traites et non les reussis: un lot ou la source
            refuse un fichier sur deux avancait par sauts de cinquante, et un
            lot entierement refuse restait muet jusqu'au resume final. Le
            pourcentage evite d'avoir a diviser de tete pendant une descente
            qui dure des heures.
            """
            traites = reussis + echecs + ignores
            if traites % 25 and traites != total:
                return
            trop_gros = f", {ignores} trop gros" if ignores else ""
            self.stdout.write(
                f"  {traites}/{total} ({traites * 100 // total} %), "
                f"{octets / 1e6:.0f} Mo, {echecs} en echec{trop_gros}"
            )

        # Les fichiers descendent en parallele, mais l'ecriture en base reste
        # sur ce fil: partager une connexion Django entre threads est le
        # meilleur moyen de corrompre une transaction.
        with ThreadPoolExecutor(max_workers=jobs) as executeur:
            for document, chemin, taille, erreur, trop_gros in executeur.map(
                lambda doc: self._telecharger(doc, taille_max), a_faire
            ):
                if trop_gros:
                    # Ni succes ni echec: le document reste relaye, et une
                    # execution ulterieure sans seuil le prendra. L'ecrire
                    # dans import_error le ferait passer pour mort a la
                    # source, ce qu'il n'est pas.
                    ignores += 1
                    annoncer()
                    continue
                if erreur:
                    echecs += 1
                    document.import_error = erreur[:255]
                    document.save(update_fields=["import_error", "updated_at"])
                    annoncer()
                    continue
                try:
                    nom = unquote(document.source_url.rsplit("/", 1)[-1])
                    with open(chemin, "rb") as flux:
                        document.file.save(nom, File(flux), save=False)
                    document.size_bytes = taille
                    document.is_downloaded = True
                    document.import_error = ""
                    document.save(
                        update_fields=[
                            "file",
                            "size_bytes",
                            "is_downloaded",
                            "import_error",
                            "updated_at",
                        ]
                    )
                    reussis += 1
                    octets += taille
                finally:
                    os.unlink(chemin)

                annoncer()

        self.stdout.write(
            self.style.SUCCESS(
                f"Rapatriement: {reussis} fichiers ({octets / 1e6:.0f} Mo), {echecs} en echec."
            )
        )
        if ignores:
            self.stdout.write(
                f"{ignores} documents au-dela de {taille_max / 1048576:.0f} Mo: "
                "laisses a la source, relayes par l'API. Relancer sans "
                "--taille-max les rapatriera."
            )
        if echecs:
            self.stdout.write(
                "Les echecs sont conserves dans import_error; "
                "relancer avec --retenter-erreurs pour les reprendre."
            )

    def _adopter_le_disque(self, documents):
        """Rattache les fichiers deja presents a l'emplacement attendu.

        Le stockage survit a la base: une base recreee, un dump restaure sans
        les media, un rapatriement interrompu laissent des gigaoctets de PDF
        que plus aucune ligne ne reclame. Sans cette passe, la commande les
        retelechargerait pour les ecrire juste a cote, sous le nom suffixe que
        Django donne aux collisions -- deux fois le disque, deux fois le
        reseau, et un doublon par document.

        Un fichier vide n'est pas adopte: il ne prouve rien, et le
        telechargement le remplacera.
        """
        adoptes = 0
        for document in documents:
            nom = get_valid_filename(unquote(document.source_url.rsplit("/", 1)[-1]))
            chemin = library_document_path(document, nom)
            try:
                if not default_storage.exists(chemin):
                    continue
                taille = default_storage.size(chemin)
            except (OSError, SuspiciousOperation):
                continue
            if not taille:
                continue

            document.file.name = chemin
            document.size_bytes = taille
            document.is_downloaded = True
            document.import_error = ""
            document.save(
                update_fields=[
                    "file",
                    "size_bytes",
                    "is_downloaded",
                    "import_error",
                    "updated_at",
                ]
            )
            adoptes += 1
        return adoptes

    def _telecharger(self, document, taille_max=0):
        """(document, chemin temporaire, taille, erreur, trop_gros).

        Tourne dans un thread. `trop_gros` distingue le document ecarte par
        le seuil de celui que la source refuse: le premier reste rapatriable,
        le second est note en base comme illisible.
        """
        if taille_max:
            annoncee = self._taille_annoncee(document.source_url)
            # Une source muette sur le poids ne fait pas ecarter le document:
            # le telechargement ci-dessous s'arretera de lui-meme au seuil.
            if annoncee is not None and annoncee > taille_max:
                return document, "", annoncee, "", True

        descripteur, chemin = tempfile.mkstemp(suffix=".pdf")
        os.close(descripteur)
        try:
            taille = telecharger_fichier(document.source_url, chemin, taille_max)
        except _TropGros:
            os.unlink(chemin)
            return document, "", 0, "", True
        except (HTTPError, URLError, OSError) as exc:
            os.unlink(chemin)
            return document, "", 0, f"{type(exc).__name__}: {exc}", False
        if not taille:
            os.unlink(chemin)
            return document, "", 0, "Fichier vide a la source", False
        return document, chemin, taille, "", False

    @staticmethod
    def _taille_annoncee(url):
        """Poids annonce, ou None si la source se tait ou refuse la question.

        Un HEAD en echec ne condamne pas le document: 43 fichiers du fonds
        repondent deja 401 sur leur propre serveur, et rien ne dit que les
        autres acceptent tous cette methode. Le telechargement tranchera.
        """
        try:
            return taille_distante(url)
        except (HTTPError, URLError, OSError):
            return None
