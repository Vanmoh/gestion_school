"""La carte scolaire est un document officiel: rien n'y doit etre invente.

Elle affichait le telephone et l'etage d'un etablissement precis des que le
sien n'en avait pas — ce qui etait le cas de trois ecoles sur quatre. Elle
portait aussi deux numeros concurrents, dont la cle primaire en base, et un
QR absent la rendait invverifiable. Ces tests fixent ce qui ne doit pas
revenir.
"""

import io
import os
import tempfile
from datetime import date
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from django.test import RequestFactory, SimpleTestCase, override_settings
from PIL import Image
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.card_verification import signature_valide, signer
from apps.reports.views import (
    CARD_FORMATS,
    _build_student_cards_pdf,
    _ecourte,
    _etat_du_qr,
    _grille_a4,
    _media_local,
    _menage_du_cache_media,
    _school_acronym,
    _school_identity_for_student,
    _verify_base_url,
)
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class AcronymeTests(SimpleTestCase):
    def test_it_uses_initials_instead_of_cutting_mid_word(self):
        """`name[:16]` donnait « COMPLEXE SCOLAIR »."""
        self.assertEqual(_school_acronym("Complexe Scolaire Oumar Bah"), "CSOB")

    def test_it_ignores_linking_words(self):
        self.assertEqual(_school_acronym("Groupe Scolaire les Hirondelles"), "GSH")

    def test_a_short_name_is_left_alone(self):
        """Abreger « LTOB » n'aurait aucun sens."""
        self.assertEqual(_school_acronym("LTOB"), "LTOB")
        self.assertEqual(_school_acronym("IFP-OBK"), "IFP-OBK")

    def test_two_initials_fall_back_to_the_full_name(self):
        """« LP » ne distingue rien."""
        self.assertEqual(_school_acronym("Lycee de la Paix"), "LYCEE DE LA PAIX")


class TroncatureTests(SimpleTestCase):
    def test_a_cut_value_is_marked(self):
        """Sans marque, « Mamadou Ouali » se lit comme un nom complet."""
        self.assertEqual(_ecourte("Mamadou Oualiyou Diallo", 17), "Mamadou Oualiy...")

    def test_a_short_value_is_untouched(self):
        self.assertEqual(_ecourte("Diarra", 17), "Diarra")


class SignatureCarteTests(SimpleTestCase):
    def test_a_signature_matches_only_its_student_and_year(self):
        signature = signer(42, "2025-2026")

        self.assertTrue(signature_valide(42, "2025-2026", signature))
        self.assertFalse(signature_valide(43, "2025-2026", signature))
        self.assertFalse(signature_valide(42, "2024-2025", signature))

    def test_an_empty_signature_is_refused(self):
        self.assertFalse(signature_valide(42, "2025-2026", ""))


class CarteScolaireTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        # Sans telephone ni adresse, comme trois des quatre ecoles reelles.
        cls.etablissement = Etablissement.objects.create(name="Complexe Scolaire Oumar Bah")
        cls.classroom = ClassRoom.objects.create(
            name="10eme A", academic_year=cls.year, etablissement=cls.etablissement
        )
        cls.directeur = User.objects.create_user(
            username="directeur_carte",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        eleve_user = User.objects.create_user(
            username="eleve_carte",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        cls.eleve = Student.objects.create(
            user=eleve_user,
            classroom=cls.classroom,
            etablissement=cls.etablissement,
            gender="F",
            birth_date=date(2010, 5, 4),
        )

    def setUp(self):
        self.client.force_authenticate(self.directeur)

    def test_a_school_without_a_phone_borrows_no_one_elses(self):
        """Le repli faisait imprimer le telephone du LTOB sur 171 cartes."""
        identite = _school_identity_for_student(self.eleve)

        self.assertEqual(identite["name"], "Complexe Scolaire Oumar Bah")
        self.assertEqual(identite["phone"], "")
        self.assertEqual(identite["level"], "")
        self.assertEqual(identite["short"], "CSOB")

    def test_the_card_is_produced_in_both_formats(self):
        for card_format in CARD_FORMATS:
            with self.subTest(card_format=card_format):
                response = self.client.get(
                    f"/api/reports/student-card/{self.eleve.id}/",
                    {"card_format": card_format},
                    HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
                )
                self.assertEqual(response.status_code, status.HTTP_200_OK)
                self.assertEqual(response["Content-Type"], "application/pdf")
                self.assertTrue(response.content.startswith(b"%PDF"))

    def test_the_download_header_survives_an_accented_class_name(self):
        """Les en-tetes HTTP n'admettent pas d'octets non-ASCII.

        « cartes_1ère_Année_EM2.pdf » y partait tel quel. La RFC 6266 demande
        un repli ASCII et une forme encodee.
        """
        classe = ClassRoom.objects.create(
            name="1ère Année EM2",
            academic_year=self.year,
            etablissement=self.etablissement,
        )
        Student.objects.filter(pk=self.eleve.pk).update(classroom=classe)

        response = self.client.get(
            f"/api/reports/student-cards/class/{classe.id}/",
            {"layout_mode": "a4_6up"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        entete = response["Content-Disposition"]
        entete.encode("ascii")  # leve UnicodeEncodeError si un accent subsiste
        self.assertIn("1ere_Annee_EM2", entete)
        self.assertIn("filename*=UTF-8''", entete)

    def test_an_unknown_format_is_refused_rather_than_silently_replaced(self):
        """Une planche imprimee au mauvais format ne se rattrape pas."""
        response = self.client.get(
            f"/api/reports/student-card/{self.eleve.id}/",
            {"card_format": "a3"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_the_wallet_sheet_holds_more_cards_than_the_a6_one(self):
        """Une planche A4 tient 8 cartes CR80 contre 2 au format A6."""
        eleves = [self.eleve] * 10
        pages = {}
        for card_format in ("a6", "cr80"):
            pdf = _build_student_cards_pdf(
                eleves,
                school=_school_identity_for_student(self.eleve),
                logo_path=None,
                layout_mode="a4",
                card_format=card_format,
            )
            pages[card_format] = pdf.pages_count

        self.assertLess(pages["cr80"], pages["a6"])

    def test_a_nine_up_sheet_no_longer_shrinks_the_card(self):
        """« 9 par page » faisait entrer neuf cartes en les reduisant.

        La grille etait imposee, puis la carte redimensionnee pour y entrer:
        au format bancaire elle sortait a 70 % de sa taille, libelles a 4,7
        points. Les deux anciennes valeurs restent acceptees, mais elles
        produisent desormais la meme planche que « a4 ».
        """
        eleves = [self.eleve] * 9
        pages = {}
        for layout_mode in ("a4", "a4_6up", "a4_9up"):
            pdf = _build_student_cards_pdf(
                eleves,
                school=_school_identity_for_student(self.eleve),
                logo_path=None,
                layout_mode=layout_mode,
                card_format="cr80",
            )
            pages[layout_mode] = pdf.pages_count

        # Huit par feuille a taille reelle: neuf eleves tiennent sur deux
        # planches, pas sur une seule obtenue en retrecissant les cartes.
        self.assertEqual(pages, {"a4": 2, "a4_6up": 2, "a4_9up": 2})

    def test_the_school_logo_is_actually_drawn(self):
        """Il traversait trois fonctions sans jamais etre pose sur la carte."""
        with tempfile.TemporaryDirectory() as dossier:
            logo = Path(dossier) / "logo.jpg"
            Image.new("RGB", (120, 120), (20, 70, 136)).save(logo)

            planches = {}
            for chemin in (None, str(logo)):
                pdf = _build_student_cards_pdf(
                    [self.eleve],
                    school=_school_identity_for_student(self.eleve),
                    logo_path=chemin,
                    layout_mode="standard",
                    card_format="cr80",
                )
                planches[bool(chemin)] = len(pdf.image_cache.images)

        # La signature et le tampon de l'etablissement sont deja sur la
        # carte: c'est l'image en plus qui prouve que le logo y arrive.
        self.assertEqual(planches[True], planches[False] + 1)

    def test_the_single_card_is_composed_for_its_real_width(self):
        """La carte etait dessinee a 4 mm des bords d'une page a son format.

        Elle sortait donc a 77,6 x 46 mm au lieu de 85,6 x 54 -- un liseré
        blanc dans le porte-badge. Et comme les corps de police se choisissent
        par paliers de largeur, la carte bancaire passait sous la barre des
        85 mm: elle etait composee dans les corps du format reduit, valeurs
        coupees a vingt-quatre caracteres.
        """
        Student.objects.filter(pk=self.eleve.pk).update(
            matricule="CSOB-2025-INSCRIPTION-0147"
        )
        eleve = Student.objects.select_related("user", "classroom").get(
            pk=self.eleve.pk
        )

        pdf = _build_student_cards_pdf(
            [eleve],
            school=_school_identity_for_student(eleve),
            logo_path=None,
            layout_mode="standard",
            card_format="cr80",
        )
        pdf.set_compression(False)

        self.assertIn(b"CSOB-2025-INSCRIPTION-0147", bytes(pdf.output()))

    def test_the_card_asks_to_be_given_back(self):
        """Rien n'indiquait a qui rapporter une carte trouvee dans la cour."""
        pdf = _build_student_cards_pdf(
            [self.eleve],
            school=_school_identity_for_student(self.eleve),
            logo_path=None,
            layout_mode="standard",
            card_format="cr80",
        )
        pdf.set_compression(False)

        self.assertIn(b"restituer", bytes(pdf.output()))

    def test_the_check_announces_what_the_sheet_will_look_like(self):
        """Quarante cadres « PHOTO » vides se constatent avant la decoupe."""
        response = self.client.get(
            f"/api/reports/student-cards/class/{self.classroom.id}/verification/",
            {"card_format": "cr80"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["effectif"], 1)
        self.assertEqual(response.data["sans_photo"], 1)
        self.assertEqual(response.data["cartes_par_planche"], 8)
        self.assertEqual(len(response.data["noms_sans_photo"]), 1)

    def test_the_check_refuses_an_unknown_format_like_the_printing_does(self):
        response = self.client.get(
            f"/api/reports/student-cards/class/{self.classroom.id}/verification/",
            {"card_format": "a3"},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class VerificationCarteTests(APITestCase):
    """La page scannee ne doit reveler aucune identite.

    Une carte perdue et ramassee par un inconnu ne doit rien lui apprendre sur
    l'eleve: ni son nom, ni sa date de naissance, ni sa classe.
    """

    @classmethod
    def setUpTestData(cls):
        cls.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.etablissement = Etablissement.objects.create(name="LTOB")
        user = User.objects.create_user(
            username="eleve_verif",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
            first_name="Alimata",
            last_name="Diarra",
        )
        cls.eleve = Student.objects.create(
            user=user,
            etablissement=cls.etablissement,
            gender="F",
            birth_date=date(2010, 5, 4),
        )

    def _verifier(self, annee, signature, student_id=None):
        cible = student_id if student_id is not None else self.eleve.id
        return self.client.get(f"/api/reports/carte/{cible}/{annee}/{signature}/")

    def test_a_valid_card_is_recognised_without_logging_in(self):
        """Celui qui controle au portail n'a pas de compte."""
        response = self._verifier("2025-2026", signer(self.eleve.id, "2025-2026"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("Carte valide", response.content.decode())

    def test_it_never_shows_the_student_identity(self):
        response = self._verifier("2025-2026", signer(self.eleve.id, "2025-2026"))
        page = response.content.decode()

        self.assertNotIn("Alimata", page)
        self.assertNotIn("Diarra", page)
        self.assertNotIn("04/05/2010", page)

    def test_a_forged_signature_is_rejected(self):
        response = self._verifier("2025-2026", "0" * 16)

        self.assertIn("Carte non reconnue", response.content.decode())

    def test_a_card_from_a_past_year_is_shown_as_expired(self):
        """Sans echeance, la carte de 2019 ressemblait a celle de cette annee."""
        response = self._verifier("2019-2020", signer(self.eleve.id, "2019-2020"))

        self.assertIn("Carte expiree", response.content.decode())

    def test_an_archived_student_card_is_revoked(self):
        Student.objects.filter(pk=self.eleve.pk).update(is_archived=True)

        response = self._verifier("2025-2026", signer(self.eleve.id, "2025-2026"))

        self.assertIn("Carte revoquee", response.content.decode())

    def test_an_unknown_student_reveals_nothing(self):
        """Les identifiants ne doivent pas s'enumerer."""
        response = self._verifier("2025-2026", signer(999999, "2025-2026"), student_id=999999)

        self.assertIn("Carte non reconnue", response.content.decode())


class MediaEnStockageObjetTests(SimpleTestCase):
    """Un fichier qui ne vit que dans le bucket doit arriver jusqu'au PDF.

    Les trois resolveurs de media n'interrogeaient que le disque local:
    `field.path`, puis MEDIA_ROOT. En production les fichiers sont dans un
    bucket, ou `path()` n'existe pas et ou MEDIA_ROOT ne contient rien. Photo
    d'eleve, logo, signature et tampon manquaient donc a tous les PDF --
    cartes, certificats, bulletins, recus -- sans qu'aucune erreur ne le
    signale: l'absence se lit comme « l'ecole n'en a pas ».
    """

    class _StockageDistant:
        def __init__(self, contenu: bytes, *, lisible: bool = True):
            self.contenu = contenu
            self.lisible = lisible

        def path(self, name):
            raise NotImplementedError("Le stockage objet n'a pas de chemin local.")

        def open(self, name, mode="rb"):
            if not self.lisible:
                raise OSError("bucket injoignable")
            return io.BytesIO(self.contenu)

    class _ChampDistant:
        def __init__(self, nom, stockage):
            self.name = nom
            self.storage = stockage

        def __bool__(self):
            return True

        @property
        def path(self):
            raise NotImplementedError("Le stockage objet n'a pas de chemin local.")

    def test_a_file_that_lives_only_in_the_bucket_is_brought_back(self):
        contenu = b"\x89PNG\r\n\x1a\n" + uuid4().bytes
        champ = self._ChampDistant(
            f"etablissements/{uuid4().hex}.png", self._StockageDistant(contenu)
        )

        chemin = _media_local(champ)

        self.assertIsNotNone(chemin)
        self.assertEqual(Path(chemin).read_bytes(), contenu)

    def test_the_second_call_reuses_the_downloaded_copy(self):
        """Soixante cartes ne doivent pas declencher soixante telechargements."""
        champ = self._ChampDistant(
            f"etablissements/{uuid4().hex}.png", self._StockageDistant(b"logo")
        )

        premier = _media_local(champ)
        champ.storage.lisible = False
        second = _media_local(champ)

        self.assertEqual(premier, second)

    def test_the_cache_does_not_grow_without_end(self):
        """Le disque du conteneur est petit, et partage avec l'application."""
        with tempfile.TemporaryDirectory() as dossier:
            cache = Path(dossier)
            for rang in range(10):
                fichier = cache / f"media_{rang}.bin"
                fichier.write_bytes(b"x" * 1000)
                os.utime(fichier, (rang, rang))

            with patch("apps.reports.views.PLAFOND_CACHE_MEDIA", 4000):
                _menage_du_cache_media(cache)

            restants = sorted(chemin.name for chemin in cache.iterdir())

        # On descend a la moitie du plafond, et ce sont les plus anciens qui
        # partent: s'arreter pile sous la barre ferait recommencer le menage
        # au telechargement suivant.
        self.assertEqual(restants, ["media_8.bin", "media_9.bin"])

    def test_an_unreachable_bucket_costs_the_logo_not_the_document(self):
        champ = self._ChampDistant(
            f"etablissements/{uuid4().hex}.png",
            self._StockageDistant(b"", lisible=False),
        )

        self.assertIsNone(_media_local(champ))


class QrDeLaCarteTests(SimpleTestCase):
    """Un QR grave sur du carton ne se corrige plus.

    Il etait bati sur l'adresse de la requete alors que PUBLIC_BASE_URL
    existe depuis le lien public des bulletins. Une planche tiree depuis
    l'application servie en reseau local portait « http://192.168.1.25:8000 »
    et n'ouvrait rien hors du Wi-Fi de l'ecole.
    """

    def _requete_en_reseau_local(self):
        return RequestFactory().get("/", HTTP_HOST="192.168.1.25:8000")

    @override_settings(PUBLIC_BASE_URL="", ALLOWED_HOSTS=["*"])
    def test_a_lan_address_prints_no_qr_at_all(self):
        requete = self._requete_en_reseau_local()

        self.assertEqual(_verify_base_url(requete), "")

        actif, motif = _etat_du_qr(requete)
        self.assertFalse(actif)
        self.assertIn("PUBLIC_BASE_URL", motif)

    @override_settings(PUBLIC_BASE_URL="https://ecole.example.com", ALLOWED_HOSTS=["*"])
    def test_the_configured_address_wins_over_the_request(self):
        requete = self._requete_en_reseau_local()

        self.assertEqual(_verify_base_url(requete), "https://ecole.example.com")
        self.assertEqual(_etat_du_qr(requete), (True, ""))


class PlancheATailleReelleTests(SimpleTestCase):
    """Une carte se decoupe et se glisse dans un porte-badge.

    Ses millimetres sont sa raison d'etre: au format bancaire, « 6 par page »
    l'agrandissait de 8 % et elle n'entrait plus nulle part.
    """

    def test_the_wallet_card_fits_eight_times_on_a_sheet(self):
        cols, rows, marge, gap = _grille_a4(*CARD_FORMATS["cr80"])

        self.assertEqual((cols, rows), (2, 4))
        self.assertLessEqual(
            (2 * marge) + (cols * CARD_FORMATS["cr80"][0]) + ((cols - 1) * gap),
            210.0,
        )
        self.assertLessEqual(
            (2 * marge) + (rows * CARD_FORMATS["cr80"][1]) + ((rows - 1) * gap),
            297.0,
        )

    def test_the_a6_card_fits_twice(self):
        self.assertEqual(_grille_a4(*CARD_FORMATS["a6"])[:2], (1, 2))
