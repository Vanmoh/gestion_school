"""Le bilan d'un trimestre: conserve, et calcule comme le bulletin.

Deux defauts se repondaient ici, invisibles tant qu'on ne comparait pas un
bulletin a un classement.

Le premier: `StudentAcademicHistory` ne portait pas de periode. La cloture du
T2 ecrasait la ligne du T1, et un bulletin du premier trimestre reimprime en
juin affichait le rang du second.

Le second: le classement ne comptait pas la conduite, que le bulletin compte
avec un coefficient. Un eleve pouvait donc etre classe derriere un camarade
dont le bulletin affichait une moyenne inferieure a la sienne -- ce que les
familles lisent, et qui se plaide mal au secretariat.
"""

from datetime import date
from decimal import Decimal
from io import StringIO

from django.core.management import CommandError, call_command
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.reports.views import _build_bulletin_payload
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamResult,
    ExamSession,
    Grade,
    Student,
    StudentAcademicHistory,
    Subject,
    recalculate_term_ranking,
)


class DecorDeClasse:
    """Le decor commun: une classe, une matiere coef 2, deux eleves.

    Un mixin et non une classe de test parente: en heriter ferait rejouer
    tous ses tests dans chaque sous-classe.
    """

    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee du Bilan")
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.classe = ClassRoom.objects.create(
            name="6A",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        self.maths = Subject.objects.create(name="Maths", coefficient=Decimal("2"))

        self.premier = self._eleve("B001", "Awa", conduite="18")
        self.second = self._eleve("B002", "Bala", conduite="18")

    def _eleve(self, matricule, prenom, conduite="18"):
        user = User.objects.create_user(
            username=f"eleve_{matricule}",
            password="eleve12345",
            role=UserRole.STUDENT,
            first_name=prenom,
            last_name="Test",
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=user,
            matricule=matricule,
            classroom=self.classe,
            etablissement=self.etablissement,
            conduite=Decimal(conduite),
            birth_date=date(2010, 5, 4),
            gender=Student.Gender.FEMALE,
        )

    def _note(self, eleve, valeur, term="T1"):
        return Grade.objects.create(
            student=eleve,
            subject=self.maths,
            classroom=self.classe,
            academic_year=self.annee,
            term=term,
            value=Decimal(str(valeur)),
        )

    def _bilan(self, eleve, term):
        return StudentAcademicHistory.objects.get(
            student=eleve,
            academic_year=self.annee,
            classroom=self.classe,
            term=term,
        )


class BilanParTrimestreTests(DecorDeClasse, TestCase):
    # ----- conservation des periodes -----------------------------------

    def test_la_cloture_du_deuxieme_trimestre_n_ecrase_pas_le_premier(self):
        self._note(self.premier, 16, term="T1")
        self._note(self.second, 8, term="T1")
        recalculate_term_ranking(self.classe, self.annee, "T1")

        # Le rapport de force s'inverse au deuxieme trimestre.
        self._note(self.premier, 6, term="T2")
        self._note(self.second, 18, term="T2")
        recalculate_term_ranking(self.classe, self.annee, "T2")

        self.assertEqual(self._bilan(self.premier, "T1").rank, 1)
        self.assertEqual(self._bilan(self.second, "T1").rank, 2)
        self.assertEqual(self._bilan(self.premier, "T2").rank, 2)
        self.assertEqual(self._bilan(self.second, "T2").rank, 1)

    def test_le_bulletin_reimprime_porte_le_rang_de_son_trimestre(self):
        self._note(self.premier, 16, term="T1")
        self._note(self.second, 8, term="T1")
        recalculate_term_ranking(self.classe, self.annee, "T1")

        self._note(self.premier, 6, term="T2")
        self._note(self.second, 18, term="T2")
        recalculate_term_ranking(self.classe, self.annee, "T2")

        bulletin_t1 = _build_bulletin_payload(
            student=self.premier,
            academic_year_id=self.annee.id,
            normalized_term="T1",
        )
        self.assertEqual(bulletin_t1["rank"], 1)

        bulletin_t2 = _build_bulletin_payload(
            student=self.premier,
            academic_year_id=self.annee.id,
            normalized_term="T2",
        )
        self.assertEqual(bulletin_t2["rank"], 2)

    def test_un_trimestre_sans_bilan_n_emprunte_pas_le_rang_d_un_autre(self):
        """Mieux vaut pas de rang qu'un rang qui vient d'ailleurs."""
        self._note(self.premier, 16, term="T1")
        recalculate_term_ranking(self.classe, self.annee, "T1")

        self._note(self.premier, 12, term="T3")
        bulletin_t3 = _build_bulletin_payload(
            student=self.premier,
            academic_year_id=self.annee.id,
            normalized_term="T3",
        )
        self.assertIsNone(bulletin_t3["rank"])

    # ----- un seul calcul pour deux ecrans ------------------------------

    def test_la_moyenne_du_classement_est_celle_du_bulletin(self):
        self._note(self.premier, 15, term="T1")
        recalculate_term_ranking(self.classe, self.annee, "T1")

        bulletin = _build_bulletin_payload(
            student=self.premier,
            academic_year_id=self.annee.id,
            normalized_term="T1",
        )
        bilan = self._bilan(self.premier, "T1")

        # Maths 15 (coef 2) et conduite 18 (coef 2): (30 + 36) / 4 = 16,50.
        self.assertEqual(float(bilan.average), 16.5)
        self.assertEqual(bulletin["average"], float(bilan.average))

    def test_la_conduite_pese_sur_le_classement_comme_sur_le_bulletin(self):
        """Deux eleves a egalite de notes: la conduite les departage.

        Avant, elle ne comptait que sur le bulletin: le classement les
        laissait dans l'ordre de leur cle primaire.
        """
        self.second.conduite = Decimal("8")
        self.second.save(update_fields=["conduite", "updated_at"])

        self._note(self.premier, 12, term="T1")
        self._note(self.second, 12, term="T1")
        recalculate_term_ranking(self.classe, self.annee, "T1")

        self.assertEqual(self._bilan(self.premier, "T1").rank, 1)
        self.assertEqual(self._bilan(self.second, "T1").rank, 2)

    def test_le_coefficient_de_conduite_se_regle_par_etablissement(self):
        self.etablissement.conduite_coefficient = Decimal("0")
        self.etablissement.save(update_fields=["conduite_coefficient", "updated_at"])

        self._note(self.premier, 15, term="T1")
        recalculate_term_ranking(self.classe, self.annee, "T1")

        # A coefficient nul, la conduite est notee mais ne pese plus: la
        # moyenne redevient celle des seules matieres.
        self.assertEqual(float(self._bilan(self.premier, "T1").average), 15.0)

        bulletin = _build_bulletin_payload(
            student=self.premier,
            academic_year_id=self.annee.id,
            normalized_term="T1",
        )
        self.assertEqual(bulletin["average"], 15.0)

    def test_la_composition_compte_dans_le_classement(self):
        session = ExamSession.objects.create(
            title="Composition T1",
            term="T1",
            academic_year=self.annee,
            start_date=date(2026, 1, 10),
            end_date=date(2026, 1, 11),
        )
        self._note(self.premier, 10, term="T1")
        ExamResult.objects.create(
            session=session,
            student=self.premier,
            subject=self.maths,
            score=Decimal("20"),
        )
        recalculate_term_ranking(self.classe, self.annee, "T1")

        # Devoirs 10 et composition 20 font 15 pour la matiere, puis
        # (15*2 + 18*2)/4 = 16,50 avec la conduite.
        self.assertEqual(float(self._bilan(self.premier, "T1").average), 16.5)

    def test_la_moyenne_de_classe_compte_les_compositions(self):
        """Les deux colonnes du bulletin doivent se comparer.

        « Moyenne classe » ne portait que sur les notes de classe, quand la
        note de l'eleve en face combinait devoirs et composition: deux
        nombres de nature differente, presentes cote a cote.
        """
        session = ExamSession.objects.create(
            title="Composition T1",
            term="T1",
            academic_year=self.annee,
            start_date=date(2026, 1, 10),
            end_date=date(2026, 1, 11),
        )
        for eleve, devoir, composition in (
            (self.premier, 10, 20),
            (self.second, 8, 12),
        ):
            self._note(eleve, devoir, term="T1")
            ExamResult.objects.create(
                session=session,
                student=eleve,
                subject=self.maths,
                score=Decimal(str(composition)),
            )

        bulletin = _build_bulletin_payload(
            student=self.premier,
            academic_year_id=self.annee.id,
            normalized_term="T1",
        )
        ligne_maths = next(
            ligne for ligne in bulletin["rows"] if ligne["subject"] == "Maths"
        )

        # Notes finales: 15 pour le premier, 10 pour le second -> 12,50.
        # L'ancien calcul, sur les seuls devoirs, donnait 9,00.
        self.assertEqual(ligne_maths["note_finale"], 15.0)
        self.assertEqual(ligne_maths["moyenne_classe"], 12.5)

    def test_le_bilan_d_annee_cohabite_avec_les_bilans_trimestriels(self):
        """La promotion ecrit sur l'annee entiere, la cloture sur T1/T2/T3."""
        self._note(self.premier, 15, term="T1")
        recalculate_term_ranking(self.classe, self.annee, "T1")

        StudentAcademicHistory.objects.create(
            student=self.premier,
            academic_year=self.annee,
            classroom=self.classe,
            term=StudentAcademicHistory.ANNEE_ENTIERE,
            average=Decimal("13.00"),
            rank=1,
        )

        self.assertEqual(
            StudentAcademicHistory.objects.filter(
                student=self.premier, academic_year=self.annee
            ).count(),
            2,
        )
        self.assertEqual(float(self._bilan(self.premier, "T1").average), 16.5)
        self.assertEqual(
            float(self._bilan(self.premier, StudentAcademicHistory.ANNEE_ENTIERE).average),
            13.0,
        )


class RecalculerRangsCommandTests(DecorDeClasse, TestCase):
    """La commande de reprise, pour les annees closes avant la migration 0057.

    Ces annees n'ont en base qu'une ligne par eleve, sans periode. La
    commande recree les bilans trimestriels a partir des notes, qui, elles,
    sont toujours la.
    """

    def _appeler(self, **options):
        sortie = StringIO()
        call_command("recalculer_rangs", stdout=sortie, **options)
        return sortie.getvalue()

    def test_elle_recree_les_bilans_trimestriels_manquants(self):
        self._note(self.premier, 15, term="T1")
        self._note(self.second, 9, term="T1")
        self.assertFalse(
            StudentAcademicHistory.objects.filter(term="T1").exists()
        )

        self._appeler(etab_id=self.etablissement.id)

        self.assertEqual(float(self._bilan(self.premier, "T1").average), 16.5)
        self.assertEqual(self._bilan(self.premier, "T1").rank, 1)
        self.assertEqual(self._bilan(self.second, "T1").rank, 2)

    def test_elle_laisse_intact_le_bilan_de_l_annee(self):
        """La ligne heritee reste: c'est elle qui sert a la promotion."""
        self._note(self.premier, 15, term="T1")
        StudentAcademicHistory.objects.create(
            student=self.premier,
            academic_year=self.annee,
            classroom=self.classe,
            term=StudentAcademicHistory.ANNEE_ENTIERE,
            average=Decimal("11.00"),
            rank=3,
        )

        self._appeler(etab_id=self.etablissement.id)

        annee = self._bilan(self.premier, StudentAcademicHistory.ANNEE_ENTIERE)
        self.assertEqual(float(annee.average), 11.0)
        self.assertEqual(annee.rank, 3)

    def test_un_trimestre_sans_note_n_est_pas_classe_a_zero(self):
        self._note(self.premier, 15, term="T1")

        sortie = self._appeler(etab_id=self.etablissement.id)

        self.assertFalse(StudentAcademicHistory.objects.filter(term="T2").exists())
        self.assertIn("2 sans note", sortie)

    def test_la_simulation_n_ecrit_rien(self):
        self._note(self.premier, 15, term="T1")

        sortie = self._appeler(etab_id=self.etablissement.id, dry_run=True)

        self.assertIn("[simulation]", sortie)
        self.assertFalse(StudentAcademicHistory.objects.filter(term="T1").exists())

    def test_elle_refuse_un_trimestre_qui_n_existe_pas(self):
        with self.assertRaises(CommandError):
            self._appeler(terms="T1,T9")
