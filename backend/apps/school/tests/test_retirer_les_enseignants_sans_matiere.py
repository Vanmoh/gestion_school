"""Ce qu'une commande qui supprime des comptes doit garantir.

`retirer_les_enseignants_sans_matiere` supprime des comptes d'enseignants et,
par cascade, leur paie, leurs pointages, leurs emargements et leurs
surveillances d'epreuves. Elle ne merite la confiance qu'a quatre conditions, et
chacune a sa raison d'etre dans un incident reel:

1. **elle ne fait rien sans qu'on le demande.** La simulation est le mode par
   defaut;
2. **elle ne touche pas aux enseignants que l'ecole a saisis.** La base de
   developpement contenait le compte personnel de son proprietaire parmi les
   sans-matiere: le supprimer au titre du menage aurait ete une faute;
3. **elle refuse par defaut ceux qui portent une fiche de paie.** Une fiche de
   paie est une ecriture comptable, pas un residu;
4. **son inventaire est complet.** Une premiere version ne comptait que
   `collector.data` et oubliait `collector.fast_deletes`: elle annoncait
   quarante-quatre suppressions quand elle en emportait deux mille. Un rapport
   qui annonce moins que ce qu'il fait est pire qu'absent.
"""

from datetime import date
from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherPayroll,
)


class SocleDesSansMatiere(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée du ménage", code="LMEN"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        cls.matiere = Subject.objects.create(
            name="Mathématiques",
            code="MA-LMEN",
            coefficient=Decimal(4),
            classroom=cls.classe,
        )
        # Celui qui enseigne: il ne doit jamais etre touche.
        cls.en_poste = cls._enseignant("lm.prof011")
        TeacherAssignment.objects.create(
            teacher=cls.en_poste, subject=cls.matiere, classroom=cls.classe
        )
        # Un compte de la dotation sans matiere: la cible.
        cls.sans_matiere = cls._enseignant("lm.prof021")
        # Un enseignant saisi par l'ecole, sans matiere lui aussi.
        cls.de_l_ecole = cls._enseignant("sissoko_prof")

    @classmethod
    def _enseignant(cls, identifiant):
        compte = User.objects.create_user(
            username=identifiant,
            password="x",
            role=UserRole.TEACHER,
            first_name="Moussa",
            last_name="TRAORE",
            etablissement=cls.etablissement,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code=identifiant.upper(),
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )

    def _retirer(self, **options):
        sortie = StringIO()
        call_command(
            "retirer_les_enseignants_sans_matiere",
            etablissement=self.etablissement.name,
            stdout=sortie,
            **options,
        )
        return sortie.getvalue()


class LaSimulationEstLeModeParDefautTests(SocleDesSansMatiere):
    def test_sans_appliquer_personne_ne_disparait(self):
        rapport = self._retirer()

        self.assertIn("Simulation", rapport)
        self.assertEqual(Teacher.objects.count(), 3)

    def test_elle_nomme_qui_elle_retirerait(self):
        rapport = self._retirer()

        self.assertIn("lm.prof021", rapport)


class ElleEpargneCeQuiNEstPasAElleTests(SocleDesSansMatiere):
    def test_l_enseignant_en_poste_n_est_jamais_touche(self):
        self._retirer(appliquer=True, forcer=True)

        self.assertTrue(Teacher.objects.filter(pk=self.en_poste.pk).exists())

    def test_l_enseignant_saisi_par_l_ecole_est_garde(self):
        """Le compte personnel du proprietaire de la base en faisait partie."""
        self._retirer(appliquer=True, forcer=True)

        self.assertTrue(Teacher.objects.filter(pk=self.de_l_ecole.pk).exists())

    def test_avec_tous_il_part_aussi(self):
        self._retirer(appliquer=True, forcer=True, tous=True)

        self.assertFalse(Teacher.objects.filter(pk=self.de_l_ecole.pk).exists())

    def test_garder_epargne_un_identifiant_nomme(self):
        self._retirer(appliquer=True, forcer=True, garder="lm.prof021")

        self.assertTrue(Teacher.objects.filter(pk=self.sans_matiere.pk).exists())


class UneFicheDePaieArreteLaMainTests(SocleDesSansMatiere):
    """Une ecriture comptable n'est pas un residu de peuplement."""

    def setUp(self):
        TeacherPayroll.objects.create(
            teacher=self.sans_matiere,
            month=date(2026, 9, 1),
            academic_year=self.annee,
            hourly_rate=Decimal(3000),
            amount=Decimal(300000),
        )

    def test_par_defaut_il_reste(self):
        rapport = self._retirer(appliquer=True, forcer=True)

        self.assertTrue(Teacher.objects.filter(pk=self.sans_matiere.pk).exists())
        self.assertIn("fiche(s) de paie", rapport)

    def test_avec_la_paie_il_part_et_sa_fiche_avec(self):
        self._retirer(appliquer=True, forcer=True, avec_la_paie=True)

        self.assertFalse(Teacher.objects.filter(pk=self.sans_matiere.pk).exists())
        self.assertEqual(TeacherPayroll.objects.count(), 0)

    def test_l_inventaire_annonce_la_fiche_de_paie(self):
        """Le defaut corrige: `fast_deletes` ne figurait pas dans le compte.

        Django y range les suppressions qu'il fait en une requete, sans charger
        les objets. Ne compter que `collector.data` annoncait quarante-quatre
        suppressions pour deux mille reelles.
        """
        rapport = self._retirer(avec_la_paie=True)

        self.assertIn("TeacherPayroll", rapport)


class DesactiverPlutotQueSupprimerTests(SocleDesSansMatiere):
    """Ce qu'on fait d'un enseignant qui s'en va, et c'est reversible."""

    def test_le_compte_reste_mais_perd_l_acces(self):
        self._retirer(appliquer=True, desactiver=True)

        self.sans_matiere.user.refresh_from_db()
        self.assertTrue(Teacher.objects.filter(pk=self.sans_matiere.pk).exists())
        self.assertFalse(self.sans_matiere.user.is_active)

    def test_l_enseignant_en_poste_garde_son_acces(self):
        self._retirer(appliquer=True, desactiver=True)

        self.en_poste.user.refresh_from_db()
        self.assertTrue(self.en_poste.user.is_active)

    def test_la_desactivation_garde_l_historique(self):
        TeacherPayroll.objects.create(
            teacher=self.sans_matiere,
            month=date(2026, 9, 1),
            academic_year=self.annee,
            hourly_rate=Decimal(3000),
            amount=Decimal(300000),
        )

        self._retirer(appliquer=True, desactiver=True, avec_la_paie=True)

        self.assertEqual(TeacherPayroll.objects.count(), 1)
