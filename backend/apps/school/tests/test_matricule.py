"""Le matricule eleve: son format, sa sequence, ses cas limites.

Le format `RC15CG25E3566F` -- ecole, classe, annee, type, sequence, genre --
existait deja et fonctionnait dans le cas nominal. Deux defauts le
trahissaient: l'eleve dont le genre n'etait pas renseigne recevait un
« GS-2025-00001 » etranger au format, et le code de l'ecole etait derive de
son nom, donc mouvant.
"""

from datetime import date

from django.test import TestCase
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school import matricule as service
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class _EcoleMixin:
    @classmethod
    def _ecole(cls, nom, code=""):
        etablissement = Etablissement.objects.create(name=nom, code=code)
        annee = AcademicYear.objects.create(
            name=f"2025-2026 {nom[:6]}",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=etablissement,
        )
        classe = ClassRoom.objects.create(
            name="11ème CG", academic_year=annee, etablissement=etablissement
        )
        return etablissement, annee, classe

    @classmethod
    def _eleve(cls, username, classe, etablissement, genre="M", matricule=""):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=etablissement,
        )
        return Student.objects.create(
            user=user,
            classroom=classe,
            etablissement=etablissement,
            gender=genre,
            matricule=matricule,
        )


class FormatDuMatriculeTests(_EcoleMixin, TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.ecole, cls.annee, cls.classe = cls._ecole("Rive Ouest Collège", code="RC15")

    def test_le_matricule_suit_le_format_convenu(self):
        eleve = self._eleve("m1", self.classe, self.ecole, genre="M")

        self.assertEqual(eleve.matricule, "RC1511CG25E0001M")
        self.assertTrue(service.est_conforme(eleve.matricule))

    def test_le_code_de_l_ecole_vient_de_son_champ_et_non_de_son_nom(self):
        """Renommer l'ecole ne doit plus changer le prefixe de ses matricules."""
        eleve = self._eleve("m2", self.classe, self.ecole)
        self.assertTrue(eleve.matricule.startswith("RC15"))

        self.ecole.name = "Établissement Rebaptisé"
        self.ecole.save(update_fields=["name"])
        suivant = self._eleve("m3", self.classe, self.ecole)

        self.assertTrue(suivant.matricule.startswith("RC15"))

    def test_le_genre_manquant_ne_casse_plus_le_format(self):
        """Il produisait « GS-2025-00001 », etranger au format.

        L'inscription exige desormais le genre, mais des fiches anciennes en
        manquent encore: le service doit leur produire un matricule conforme
        -- c'est ce dont la migration de regularisation se sert.
        """
        eleve = self._eleve("m4", self.classe, self.ecole, genre="M")
        Student.objects.filter(pk=eleve.pk).update(gender=None)
        eleve.refresh_from_db()

        produit = service.generer(eleve)

        self.assertTrue(service.est_conforme(produit), produit)
        self.assertTrue(produit.endswith("N"))
        self.assertTrue(produit.startswith("RC1511CG25E"))

    def test_le_genre_termine_le_matricule(self):
        garcon = self._eleve("m5", self.classe, self.ecole, genre="M")
        fille = self._eleve("m6", self.classe, self.ecole, genre="F")

        self.assertTrue(garcon.matricule.endswith("M"))
        self.assertTrue(fille.matricule.endswith("F"))

    def test_la_sequence_avance_d_un_eleve_a_l_autre(self):
        premier = self._eleve("m7", self.classe, self.ecole)
        second = self._eleve("m8", self.classe, self.ecole)

        self.assertTrue(premier.matricule.endswith("0001M"))
        self.assertTrue(second.matricule.endswith("0002M"))

    def test_la_sequence_repart_du_plus_grand_et_non_du_dernier_cree(self):
        """Un matricule impose a la main ne doit pas etre repris par le suivant."""
        self._eleve("m9", self.classe, self.ecole)
        self._eleve("m10", self.classe, self.ecole, matricule="RC1511CG25E9000M")

        suivant = self._eleve("m11", self.classe, self.ecole)

        self.assertTrue(suivant.matricule.endswith("9001M"), suivant.matricule)

    def test_un_matricule_saisi_a_la_main_est_conserve(self):
        eleve = self._eleve(
            "m12", self.classe, self.ecole, matricule="RC1511CG25E4242M"
        )

        self.assertEqual(eleve.matricule, "RC1511CG25E4242M")

    def test_deux_ecoles_aux_memes_initiales_ne_se_marchent_pas_dessus(self):
        """Le champ `code` les separe la ou les initiales les confondaient."""
        autre, _, classe_autre = self._ecole("Rive Occidentale", code="RO22")

        ici = self._eleve("m13", self.classe, self.ecole)
        la_bas = self._eleve("m14", classe_autre, autre)

        self.assertTrue(ici.matricule.startswith("RC15"))
        self.assertTrue(la_bas.matricule.startswith("RO22"))

    def test_sans_code_l_ecole_retombe_sur_ses_initiales(self):
        """Le repli d'avant, garde le temps que chaque fiche recoive son code."""
        sans_code, _, classe = self._ecole("Lycée Technique", code="")

        eleve = self._eleve("m15", classe, sans_code)

        self.assertTrue(eleve.matricule.startswith("LT"), eleve.matricule)


class CodeDeClasseTests(TestCase):
    """« 11ème CG » vaut « 11CG »: l'ordinal ne rentre pas dans le code."""

    def test_les_formes_courantes_se_reduisent(self):
        class _Classe:
            def __init__(self, name):
                self.name = name

        for nom, attendu in (
            ("11ème CG", "11CG"),
            ("10ème CT", "10CT"),
            ("6e A", "6A"),
            ("Terminale S", "TERMINAL"),
            ("", "XX"),
        ):
            with self.subTest(nom=nom):
                self.assertEqual(service.code_classe(_Classe(nom)), attendu)

    def test_une_classe_absente_ne_fait_pas_echouer_la_generation(self):
        self.assertEqual(service.code_classe(None), "XX")

    def test_le_mot_generique_cede_la_place_a_la_filiere(self):
        """Cinq classes de premiere annee recevaient toutes « 1ANNEE »."""
        class _Classe:
            def __init__(self, name):
                self.name = name

        codes = {
            service.code_classe(_Classe(nom))
            for nom in (
                "1ère Année DB1",
                "1ère Année DB2",
                "1ère Année EM1",
                "1ère Année EM2",
                "1ère Année TC",
            )
        }

        self.assertEqual(codes, {"1DB1", "1DB2", "1EM1", "1EM2", "1TC"})

    def test_une_classe_sans_filiere_garde_le_generique_abrege(self):
        """« 3ème Année » ne peut pas se reduire au seul chiffre du rang."""
        class _Classe:
            name = "3ème Année"

        self.assertEqual(service.code_classe(_Classe()), "3AN")

    def test_deux_filieres_proches_ne_se_confondent_plus(self):
        """La troncature a six caracteres les rendait identiques."""
        class _Classe:
            def __init__(self, name):
                self.name = name

        self.assertNotEqual(
            service.code_classe(_Classe("12ème TSECO1")),
            service.code_classe(_Classe("12ème TSECO2")),
        )

    def test_la_parenthese_ne_rentre_pas_dans_le_code(self):
        class _Classe:
            name = "9ème Année (DEF)"

        self.assertEqual(service.code_classe(_Classe()), "9DEF")


class ConformiteTests(TestCase):
    def test_le_format_de_reference_est_reconnu(self):
        self.assertTrue(service.est_conforme("RC15CG25Q3566F"))

    def test_les_formes_etrangeres_sont_refusees(self):
        for valeur in ("", "ABC", "GS-2025-00001", "RC15CG25E3566", "12345"):
            with self.subTest(valeur=valeur):
                self.assertFalse(service.est_conforme(valeur))


class MatriculeApiTests(_EcoleMixin, APITestCase):
    """Ce que l'API accepte quand le matricule est saisi a la main."""

    @classmethod
    def setUpTestData(cls):
        cls.ecole, cls.annee, cls.classe = cls._ecole("Rive Ouest", code="RC15")
        cls.direction = User.objects.create_user(
            username="dir_matricule",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.ecole,
        )

    def _inscrire(self, **extra):
        """L'inscription reelle: un compte d'abord, la fiche eleve ensuite."""
        self.client.force_authenticate(self.direction)
        self._compteur = getattr(self, "_compteur", 0) + 1
        compte = User.objects.create_user(
            username=f"eleve_api_{self._compteur}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.ecole,
            first_name="Awa",
            last_name="Traore",
        )
        charge = {
            "user": compte.id,
            "classroom": self.classe.id,
            "gender": "F",
        }
        charge.update(extra)
        return self.client.post(
            "/api/students/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.ecole.id),
        )

    def test_une_inscription_sans_matricule_en_recoit_un_conforme(self):
        reponse = self._inscrire()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertTrue(
            service.est_conforme(reponse.data["matricule"]), reponse.data["matricule"]
        )

    def test_un_matricule_hors_format_est_refuse(self):
        reponse = self._inscrire(matricule="n-importe-quoi")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("matricule", reponse.data)

    def test_un_matricule_conforme_est_accepte_tel_quel(self):
        reponse = self._inscrire(matricule="RC1511CG25E7777F")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(reponse.data["matricule"], "RC1511CG25E7777F")


class GenreObligatoireTests(_EcoleMixin, TestCase):
    """Le genre entre dans le matricule: sans lui, il prenait une autre forme.

    L'API l'exigeait deja a l'inscription, mais l'import academique et les
    commandes de peuplement creaient des eleves sans genre -- et c'est de la
    que venaient les « GS-2025-00001 ».
    """

    @classmethod
    def setUpTestData(cls):
        cls.ecole, cls.annee, cls.classe = cls._ecole("École Genre", code="EG")

    def _creer(self, username, **champs):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.ecole,
        )
        return Student.objects.create(
            user=user, classroom=self.classe, etablissement=self.ecole, **champs
        )

    def test_une_inscription_avec_genre_porte_sa_lettre(self):
        eleve = self._creer("avec_genre", gender="F")

        self.assertTrue(eleve.matricule.endswith("F"))

    def test_une_fiche_sans_genre_recoit_quand_meme_un_matricule_conforme(self):
        """Le format tient sans le genre: c'est ce qui ferme la porte aux « GS- ».

        Le genre est exige aux deux portes d'inscription -- l'ecran et
        l'import --, pas au modele: l'y mettre bloquerait tout chargement de
        sauvegarde et toute reprise de donnees.
        """
        eleve = self._creer("sans_genre", gender=None)

        self.assertTrue(service.est_conforme(eleve.matricule), eleve.matricule)
        self.assertTrue(eleve.matricule.endswith("N"))


class RegularisationTests(_EcoleMixin, TestCase):
    """Ce que la migration 0051 fait aux fiches deja en base."""

    @classmethod
    def setUpTestData(cls):
        cls.ecole, cls.annee, cls.classe = cls._ecole("École Reprise", code="ER")

    def _eleve_ancien(self, username, matricule, genre=None):
        """Une fiche telle que l'ancien generateur pouvait la laisser."""
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.ecole,
        )
        eleve = Student.objects.create(
            user=user,
            classroom=self.classe,
            etablissement=self.ecole,
            gender="M",
            matricule="ER11CG25E9999M",
        )
        Student.objects.filter(pk=eleve.pk).update(matricule=matricule, gender=genre)
        eleve.refresh_from_db()
        return eleve

    def test_un_matricule_hors_format_est_reconnu(self):
        ancien = self._eleve_ancien("gs_ancien", "GS-2025-00001", genre=None)

        self.assertFalse(service.est_conforme(ancien.matricule))

    def test_le_tirage_du_genre_est_reproductible(self):
        """Deux copies de la meme base doivent se correspondre.

        Un tirage franc donnerait des matricules differents a chaque
        execution de la migration.
        """
        import random

        premier = [random.Random(pk).choice(["M", "F"]) for pk in range(1, 30)]
        second = [random.Random(pk).choice(["M", "F"]) for pk in range(1, 30)]

        self.assertEqual(premier, second)
        # Et le tirage repartit les deux genres plutot que d'en choisir un.
        self.assertEqual(set(premier), {"M", "F"})

    def test_la_regeneration_produit_un_matricule_conforme(self):
        ancien = self._eleve_ancien("gs_regen", "GS-2025-00002", genre="F")

        ancien.matricule = service.generer(ancien)

        self.assertTrue(service.est_conforme(ancien.matricule), ancien.matricule)
        self.assertTrue(ancien.matricule.startswith("ER11CG25E"))
        self.assertTrue(ancien.matricule.endswith("F"))
