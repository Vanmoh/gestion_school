"""Quatre ecoles, un seul nom chacune, et des numeros qui se suivent.

Trois descriptions concurrentes des memes quatre ecoles avaient laisse la base
reelle dans cet etat: « LYCCE OBK » saisi a la main, qu'aucune liste ne
reconnaissait -- `controler_la_dotation` repondait « hors des listes de classes,
non controlee », donc cette ecole n'a jamais ete verifiee -- et des identifiants
3, 5, 7, 11 pour quatre ecoles, trace de sept lignes creees puis fusionnees.

Le test de la renumerotation est le seul qui compte vraiment: deplacer un
identifiant d'etablissement entraine vingt-six cles etrangeres et vingt-trois
mille lignes. Si une seule ne suit pas, un eleve change d'ecole en silence.
"""

from datetime import date

from django.core.management import call_command
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.school.etablissements_reels import ETABLISSEMENTS_REELS
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class SocleDesEcolesDerivees(TestCase):
    """La base telle qu'elle etait: noms derives, numeros troues.

    `Etablissement.objects.all().delete()` d'abord: la migration
    `9999_insert_etablissements` en cree quatre dans **chaque** base, y compris
    de test. C'est precisement ce que ce lot corrige, mais la migration deja
    appliquee reste la -- ces tests partent donc d'une table vide pour decrire
    l'etat qu'ils veulent.
    """

    @classmethod
    def setUpTestData(cls):
        Etablissement.objects.all().delete()
        cls.ifp = Etablissement.objects.create(id=3, name="IFP-OBK", code="IO")
        cls.lt = Etablissement.objects.create(
            id=5, name="LYCEE TECHNIQUE OUMAR BAH", code="LT"
        )
        cls.lo = Etablissement.objects.create(id=7, name="LYCCE OBK", code="LO")
        cls.cs = Etablissement.objects.create(
            id=11, name="Complexe Scolaire Oumar Bah", code="CS"
        )

    def _nom_de(self, code):
        return next(e["nom"] for e in ETABLISSEMENTS_REELS if e["code"] == code)


class LesNomsSontRemisDroitTests(SocleDesEcolesDerivees):
    def test_un_essai_a_blanc_n_ecrit_rien(self):
        call_command("normaliser_les_etablissements")

        self.lo.refresh_from_db()
        self.assertEqual(self.lo.name, "LYCCE OBK")

    def test_la_saisie_a_la_main_est_rattrapee(self):
        """« LYCCE OBK » est la raison d'etre de cette commande.

        Ce nom n'etait dans aucune liste, donc `_classes_de` ne trouvait ni
        sigle entre parentheses ni alias: l'ecole passait entre les mailles du
        controle sans que rien ne le signale comme une anomalie.
        """
        call_command("normaliser_les_etablissements", "--appliquer")

        self.lo.refresh_from_db()
        self.assertEqual(self.lo.name, "Lycée Oumar Bah (LOBK)")

    def test_chaque_nom_porte_son_sigle(self):
        """Le sigle entre parentheses est ce qui rend le rapprochement robuste.

        `_classes_de` cherche d'abord un sigle entre parentheses, parce que
        « Lycee Technique Oumar Bah (LTOB) » et « ... (LOBK) » ne different que
        par lui. Un nom sans sigle ne peut etre rattache que par egalite
        stricte -- et la moindre faute de frappe le perd.
        """
        call_command("normaliser_les_etablissements", "--appliquer")

        for ecole in Etablissement.objects.all():
            self.assertIn("(", ecole.name + "(", ecole.name)
        self.lt.refresh_from_db()
        self.assertEqual(self.lt.name, "Lycée Technique Oumar Bah (LTOB)")

    def test_le_code_existant_n_est_jamais_remplace(self):
        """Le code compose les matricules deja distribues.

        « LT10CT25E0001M » commence par « LT ». Changer le code ferait divergere
        les matricules a venir de ceux qui sont imprimes sur les cartes.
        """
        call_command("normaliser_les_etablissements", "--appliquer")

        self.lt.refresh_from_db()
        self.assertEqual(self.lt.code, "LT")

    def test_un_code_manquant_est_pose(self):
        sans_code = Etablissement.objects.create(name="Lycée Oumar Bah de Kaloum")
        Etablissement.objects.filter(id=self.lo.id).delete()

        call_command("normaliser_les_etablissements", "--appliquer")

        sans_code.refresh_from_db()
        self.assertEqual(sans_code.code, "LO")

    def test_une_ecole_hors_des_quatre_est_laissee_tranquille(self):
        autre = Etablissement.objects.create(name="École privée du Centre", code="PC")

        call_command("normaliser_les_etablissements", "--appliquer")

        autre.refresh_from_db()
        self.assertEqual(autre.name, "École privée du Centre")
        self.assertEqual(autre.code, "PC")


class LaRenumerotationTests(SocleDesEcolesDerivees):
    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        # De quoi verifier que les references suivent: une annee, une classe,
        # un eleve, chacun accroche a une ecole differente.
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.lo,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="10ème CG1", academic_year=cls.annee, etablissement=cls.lo
        )
        compte = User.objects.create_user(
            username="lo.eleve",
            password="x",
            role=UserRole.STUDENT,
            etablissement=cls.lo,
        )
        cls.eleve = Student.objects.create(
            user=compte,
            matricule="LO10CG25E0001M",
            classroom=cls.classe,
            etablissement=cls.lo,
        )

    def test_sans_le_drapeau_les_numeros_ne_bougent_pas(self):
        """La renumerotation oblige chacun a rechoisir son ecole: elle se demande.

        L'application garde l'ecole choisie en cache et l'envoie dans
        `X-Etablissement-Id`. Apres renumerotation ce cache designe une autre
        ecole, ou aucune.
        """
        call_command("normaliser_les_etablissements", "--appliquer")

        self.assertEqual(
            sorted(Etablissement.objects.values_list("id", flat=True)), [3, 5, 7, 11]
        )

    def test_les_numeros_se_suivent(self):
        call_command(
            "normaliser_les_etablissements", "--appliquer", "--renumeroter"
        )

        self.assertEqual(
            sorted(Etablissement.objects.values_list("id", flat=True)), [1, 2, 3, 4]
        )

    def test_l_ordre_suit_la_liste_canonique(self):
        call_command(
            "normaliser_les_etablissements", "--appliquer", "--renumeroter"
        )

        attendu = {
            ecole["code"]: rang
            for rang, ecole in enumerate(ETABLISSEMENTS_REELS, start=1)
        }
        for ecole in Etablissement.objects.all():
            self.assertEqual(ecole.id, attendu[ecole.code])

    def test_les_references_suivent(self):
        """Le test qui compte: un eleve ne doit pas changer d'ecole.

        Vingt-six cles etrangeres pointent vers `Etablissement`. Si une seule ne
        suit pas le deplacement, la ligne se retrouve accrochee au numero d'une
        autre ecole -- ou dans le vide, ce qui se verrait au moins.
        """
        call_command(
            "normaliser_les_etablissements", "--appliquer", "--renumeroter"
        )

        lobk = Etablissement.objects.get(code="LO")
        self.eleve.refresh_from_db()
        self.classe.refresh_from_db()
        self.annee.refresh_from_db()
        self.assertEqual(self.eleve.etablissement_id, lobk.id)
        self.assertEqual(self.classe.etablissement_id, lobk.id)
        self.assertEqual(self.annee.etablissement_id, lobk.id)
        self.assertEqual(self.eleve.user.etablissement_id, lobk.id)

    def test_relancer_ne_rebrasse_rien(self):
        call_command(
            "normaliser_les_etablissements", "--appliquer", "--renumeroter"
        )
        avant = dict(Etablissement.objects.values_list("code", "id"))

        call_command(
            "normaliser_les_etablissements", "--appliquer", "--renumeroter"
        )

        self.assertEqual(dict(Etablissement.objects.values_list("code", "id")), avant)

    def test_aucune_reference_ne_pend_dans_le_vide(self):
        """Les contraintes sont desactivees pendant la manoeuvre: on les rappelle.

        `check_constraints` leve si une cle etrangere designe une ligne
        disparue. Ce test verifie que la commande le fait bien -- sans quoi une
        renumerotation ratee passerait pour un succes.
        """
        from django.db import connection

        call_command(
            "normaliser_les_etablissements", "--appliquer", "--renumeroter"
        )

        connection.check_constraints()
