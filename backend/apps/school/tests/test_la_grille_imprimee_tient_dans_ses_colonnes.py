"""La grille d'emploi du temps imprimée ne déborde plus de ses colonnes.

Le PDF écrivait chaque séance d'un seul trait — « DESSINTE (Mahamadou
CAMARA) » — avec `pdf.cell()`, qui ne renvoie pas à la ligne et ne coupe pas
non plus: ce qui dépassait était peint **par-dessus la colonne du lendemain**.
Sur la capture d'un 10ème CT, le mardi se lisait « DESSINTE (Mahamadou
CAMARAEM-2 (Aminata SYLLA) », deux séances superposées.

Une garde existait, mais mesurait des caractères pour une colonne mesurée en
millimètres: `if len(text) > 65`. À Helvetica 8, une colonne de 42 mm tient
une trentaine de caractères. La garde ne s'est donc jamais déclenchée — et
quand elle se serait déclenchée, elle aurait tronqué un nom d'enseignant.

Ces tests mesurent avec le métreur de fpdf, celui-là même qui pose le texte
dans la page. Ils ne relisent pas le PDF produit: l'extraction de position par
pypdf varie d'une version à l'autre, et pypdf n'est pas une dépendance
déclarée du projet.
"""

from datetime import date, time

from django.test import SimpleTestCase, TestCase
from fpdf import FPDF
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
)
from apps.school.views import TeacherScheduleSlotViewSet


def _metreur():
    """Le même Helvetica, à la même taille, que celui qui imprime la grille."""
    regle = FPDF(orientation="L", unit="mm", format="A4")
    regle.add_page()
    regle.set_font("Helvetica", "", TeacherScheduleSlotViewSet.PDF_FONT_SIZE)
    return regle


class _Creneau:
    """Juste ce que `_slot_pdf_lines` lit d'un créneau."""

    class _Matiere:
        def __init__(self, code):
            self.code = code

    class _Enseignant:
        def __init__(self, nom, code):
            self.user = None
            self.employee_code = code
            self._nom = nom

    class _Affectation:
        def __init__(self, subject, teacher):
            self.subject = subject
            self.teacher = teacher

    def __init__(self, code_matiere, nom_enseignant, salle=""):
        matiere = self._Matiere(code_matiere)
        enseignant = self._Enseignant(nom_enseignant, "ENS-000")
        self.assignment = self._Affectation(matiere, enseignant)
        self.room = salle


class _ViewSetAuNomLisible(TeacherScheduleSlotViewSet):
    """`_teacher_name` lit `teacher.user`; ici le nom est posé directement."""

    @staticmethod
    def _teacher_name(teacher):
        return getattr(teacher, "_nom", "")


class LaSeanceSEcritSurPlusieursLignesTests(SimpleTestCase):
    def test_matiere_enseignant_et_salle_sont_trois_lignes(self):
        texte = _ViewSetAuNomLisible._slot_pdf_lines(
            _Creneau("DESSINTE", "Mahamadou CAMARA", salle="B12")
        )

        self.assertEqual(texte, "DESSINTE\nMahamadou CAMARA\nSalle B12")

    def test_sans_salle_il_n_y_a_pas_de_ligne_vide(self):
        texte = _ViewSetAuNomLisible._slot_pdf_lines(
            _Creneau("EPS-2", "Maimouna TANGARA")
        )

        self.assertEqual(texte, "EPS-2\nMaimouna TANGARA")

    def test_deux_seances_dans_la_meme_case_sont_separees(self):
        texte = TeacherScheduleSlotViewSet._pdf_cell_text(
            ["PH-2\nCoumba SANGARE", "SN-2\nOumou DIALLO"]
        )

        self.assertEqual(texte, "PH-2\nCoumba SANGARE\n\nSN-2\nOumou DIALLO")


class LaLargeurDesColonnesTests(SimpleTestCase):
    """Les séances de la capture, mesurées dans la colonne qui les reçoit."""

    SEANCES = [
        ("DESSINTE", "Mahamadou CAMARA"),
        ("ECONOMIE", "Alassane CONDE"),
        ("CHINOISA", "Seydou KONATE"),
        ("STATISTI", "Fatim NIANG"),
        ("PHYSIQUE", "Aminata SYLLA"),
        ("EPS-2", "Maimouna TANGARA"),
        ("INFO-2", "Alassane CONDE"),
    ]

    def test_chaque_ligne_tient_dans_la_colonne_de_son_jour(self):
        regle = _metreur()
        utile = TeacherScheduleSlotViewSet.largeur_utile_du_jour()

        for code, enseignant in self.SEANCES:
            texte = _ViewSetAuNomLisible._slot_pdf_lines(_Creneau(code, enseignant))
            for ligne in texte.split("\n"):
                with self.subTest(ligne=ligne):
                    self.assertLessEqual(
                        regle.get_string_width(ligne),
                        utile,
                        f"« {ligne} » dépasse la colonne de "
                        f"{TeacherScheduleSlotViewSet.PDF_COL_WIDTHS[1]} mm",
                    )

    def test_l_ancienne_ecriture_d_un_seul_trait_ne_tenait_pas(self):
        """Sans quoi le test ci-dessus ne prouverait rien.

        C'est la ligne que l'ancien code posait, et elle déborde: la refonte
        corrige un défaut réel, pas un défaut supposé.
        """
        regle = _metreur()
        utile = TeacherScheduleSlotViewSet.largeur_utile_du_jour()

        self.assertGreater(
            regle.get_string_width("DESSINTE (Mahamadou CAMARA)"),
            utile,
        )

    def test_l_horaire_tient_dans_sa_colonne(self):
        regle = _metreur()
        _, droite, _, gauche = TeacherScheduleSlotViewSet.PDF_CELL_PADDING
        utile = TeacherScheduleSlotViewSet.PDF_COL_WIDTHS[0] - droite - gauche

        self.assertLessEqual(regle.get_string_width("08:00-09:00"), utile)

    def test_les_colonnes_tiennent_dans_la_page(self):
        page = FPDF(orientation="L", unit="mm", format="A4")
        page.add_page()
        disponible = page.w - page.l_margin - page.r_margin

        self.assertLessEqual(sum(TeacherScheduleSlotViewSet.PDF_COL_WIDTHS), disponible)

    def test_un_nom_trop_long_se_replie_au_lieu_de_deborder(self):
        """Le cas qu'aucune liste de noms réels ne couvre.

        L'ancien code aurait écrit ce nom par-dessus le jour suivant, ou
        l'aurait amputé. `table()` le replie, et chaque bout tient.
        """
        regle = _metreur()
        utile = TeacherScheduleSlotViewSet.largeur_utile_du_jour()
        texte = _ViewSetAuNomLisible._slot_pdf_lines(
            _Creneau("MATHEMATIQUES-APPLIQUEES", "Mohamed Lamine Abdoulaye TRAORE")
        )

        lignes = regle.multi_cell(
            w=utile, text=texte, dry_run=True, output="LINES"
        )

        self.assertGreater(len(lignes), 2)
        for ligne in lignes:
            with self.subTest(ligne=ligne):
                self.assertLessEqual(regle.get_string_width(ligne), utile)


class LaHauteurDesLignesTests(SimpleTestCase):
    """La grille remplit sa feuille sans jamais faire flotter le texte."""

    # Ce qui reste sous le bloc de titre d'une A4 paysage, en pratique.
    RESTANT = 148.0

    def test_une_grille_clairsemee_s_arrete_au_plafond(self):
        """Six creneaux pourraient s'etaler sur 20 mm de ligne: on refuse.

        Le texte flotterait au milieu du vide. Mieux vaut une grille dense et
        du blanc en bas de page qu'une grille distendue.
        """
        self.assertEqual(
            TeacherScheduleSlotViewSet.hauteur_de_ligne(self.RESTANT, 6), 7.0
        )

    def test_une_grille_chargee_s_arrete_au_plancher(self):
        """Vingt creneaux ne tiennent pas: l'interligne ne descend pas pour
        autant sous le lisible, la table passe en seconde page avec son
        en-tete repetee."""
        self.assertEqual(
            TeacherScheduleSlotViewSet.hauteur_de_ligne(self.RESTANT, 20), 4.5
        )

    def test_sans_creneau_la_hauteur_reste_definie(self):
        self.assertEqual(
            TeacherScheduleSlotViewSet.hauteur_de_ligne(self.RESTANT, 0), 4.5
        )

    def test_l_interligne_ne_grandit_jamais_quand_les_creneaux_augmentent(self):
        hauteurs = [
            TeacherScheduleSlotViewSet.hauteur_de_ligne(self.RESTANT, n)
            for n in range(1, 25)
        ]

        self.assertEqual(hauteurs, sorted(hauteurs, reverse=True))

    def test_entre_les_bornes_la_grille_tient_sur_une_page(self):
        """Le calcul n'est pas qu'un bornage: la ou il decide vraiment, le
        tableau qu'il produit rentre dans la hauteur donnee."""
        haut, _, bas, _ = TeacherScheduleSlotViewSet.PDF_CELL_PADDING

        for creneaux in range(1, 25):
            with self.subTest(creneaux=creneaux):
                inter = TeacherScheduleSlotViewSet.hauteur_de_ligne(
                    self.RESTANT, creneaux
                )
                if inter in (4.5, 7.0):
                    continue  # borne atteinte: la hauteur n'est plus le juge
                total = (1 + 2 * creneaux) * inter + (creneaux + 1) * (haut + bas)
                self.assertLessEqual(total, self.RESTANT + 0.01)


class LaGrilleImprimeeTests(APITestCase):
    """Le PDF part toujours, et il porte le nom entier de l'enseignant."""

    def setUp(self):
        self.admin = User.objects.create_user(
            username="admin_grille_imprimee",
            password="admin12345",
            role=UserRole.SUPER_ADMIN,
        )
        self.client.force_authenticate(self.admin)

        annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.classe = ClassRoom.objects.create(name="10eme CT", academic_year=annee)

        enseignant = Teacher.objects.create(
            user=User.objects.create_user(
                username="camara_grille",
                password="teacher12345",
                role=UserRole.TEACHER,
                first_name="Mahamadou",
                last_name="CAMARA",
            ),
            employee_code="ENS-900",
            hire_date=date(2020, 1, 10),
            salary_base=1000,
        )
        affectation = TeacherAssignment.objects.create(
            teacher=enseignant,
            subject=Subject.objects.create(
                name="Dessin industriel", code="DESSINTE", coefficient=1
            ),
            classroom=self.classe,
        )
        TeacherScheduleSlot.objects.create(
            assignment=affectation,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(9, 0),
            room="B12",
        )

    def test_le_pdf_est_toujours_produit(self):
        reponse = self.client.get(
            "/api/teacher-schedule-slots/export_pdf/", {"classroom": self.classe.id}
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse["Content-Type"], "application/pdf")
        self.assertTrue(reponse.content.startswith(b"%PDF"))

    def test_une_classe_sans_horaire_le_dit_au_lieu_de_planter(self):
        vide = ClassRoom.objects.create(
            name="10eme vide", academic_year=self.classe.academic_year
        )

        reponse = self.client.get(
            "/api/teacher-schedule-slots/export_pdf/", {"classroom": vide.id}
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertTrue(reponse.content.startswith(b"%PDF"))


class LeTableurGardeSonFormatTests(TestCase):
    """La refonte vise le PDF seul: Excel renvoie à la ligne tout seul.

    `_build_class_matrix` accepte désormais un libellé au choix. Sans
    argument, elle rend celui d'avant — sinon l'export Excel changerait de
    forme sans que personne l'ait demandé.
    """

    def test_sans_libelle_choisi_la_matrice_rend_la_ligne_unique(self):
        creneau = _Creneau("DESSINTE", "Mahamadou CAMARA", salle="B12")
        creneau.day_of_week = "MON"
        creneau.start_time = time(8, 0)
        creneau.end_time = time(9, 0)

        matrice = _ViewSetAuNomLisible._build_class_matrix([creneau])

        self.assertEqual(
            matrice["08:00-09:00"]["MON"],
            ["DESSINTE (Mahamadou CAMARA) [B12]"],
        )
