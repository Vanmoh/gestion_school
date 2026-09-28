"""Ce qu'une fusion de matieres doit garantir avant qu'on la lance.

`fusionner_les_matieres_en_double` supprime des matieres et des notes. C'est la
seule commande du depot dans ce cas, et elle ne merite la confiance que si trois
choses sont verifiees plutot que crues:

1. **elle ne fait rien sans qu'on le demande.** La simulation est le mode par
   defaut, et elle doit etre reellement sans effet;
2. **aucun eleve ne perd sa seule note.** Une suppression seche en perdait cent
   vingt-six sur la base de developpement: des eleves n'avaient de moyenne dans
   cette matiere que sur le doublon. Fusionner veut dire deplacer d'abord;
3. **elle reste dans son perimetre.** Les classes hors des listes de
   `insert_classes`, et les autres annees scolaires, ne sont pas son affaire.
"""

from datetime import date
from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.school.management.commands.fusionner_les_matieres_en_double import (
    Command as Fusion,
    cle_de_matiere,
)
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Grade,
    Student,
    Subject,
)


class LeRapprochementDesNomsTests(TestCase):
    """Deux ecritures d'une meme matiere doivent se rejoindre, pas plus."""

    def test_les_variantes_d_une_matiere_se_rejoignent(self):
        for variante in (
            "Mathématiques",
            "Mathématique (Math)",
            "MATHEMATIQUES",
            "Mathematique",
        ):
            with self.subTest(variante=variante):
                self.assertEqual(
                    cle_de_matiere(variante), cle_de_matiere("Mathématiques")
                )

    def test_deux_matieres_differentes_ne_se_rejoignent_pas(self):
        self.assertNotEqual(
            cle_de_matiere("Physique-Chimie"), cle_de_matiere("Mathématiques")
        )

    def test_le_sigle_entre_parentheses_ne_distingue_pas(self):
        self.assertEqual(
            cle_de_matiere("Éducation Civique et Morale"),
            cle_de_matiere("Education civique et morale (ECM)"),
        )

    def test_un_chiffre_distingue_deux_matieres(self):
        """Le defaut qui a interrompu la premiere execution reelle.

        « Langue vivante 1 » et « Langue vivante 2 » sont deux langues
        differentes. La cle jetait les chiffres, et la fusion allait les reduire
        a une seule -- seule une contrainte de base l'a arretee, par chance.
        """
        self.assertNotEqual(
            cle_de_matiere("Langue vivante 1"), cle_de_matiere("Langue vivante 2")
        )

    def test_les_niveaux_et_groupes_restent_distincts(self):
        for gauche, droite in (
            ("Mathématiques 3e", "Mathématiques 4e"),
            ("Anglais LV1", "Anglais LV2"),
            ("Atelier groupe 1", "Atelier groupe 2"),
        ):
            with self.subTest(couple=(gauche, droite)):
                self.assertNotEqual(cle_de_matiere(gauche), cle_de_matiere(droite))

    def test_l_ordre_des_mots_ne_compte_pas(self):
        """« Histoire-Geo » et « Geo-Histoire » designent la meme matiere."""
        self.assertEqual(
            cle_de_matiere("Histoire-Géographie"),
            cle_de_matiere("Géographie et Histoire"),
        )


class SocleDUneClasseEnDoubleTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        # Une ecole que `insert_classes` nomme, sinon la commande l'ignore --
        # et c'est justement ce qu'on veut aussi verifier.
        cls.etablissement = Etablissement.objects.get(
            name="Lycée Technique Oumar Bah (LTOB)"
        )
        cls.annee, _ = AcademicYear.objects.update_or_create(
            name="2025-2026",
            etablissement=cls.etablissement,
            defaults={
                "start_date": date(2025, 9, 1),
                "end_date": date(2026, 7, 31),
                "is_active": True,
            },
        )
        cls.classe = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        # « Celle du programme » se reconnait a son code suffixe.
        cls.gardee = Subject.objects.create(
            name="Mathématiques",
            code=f"MA-{cls.classe.id}",
            coefficient=Decimal(4),
            classroom=cls.classe,
            weekly_slots=3,
        )
        cls.doublon = Subject.objects.create(
            name="Mathématique (Math)",
            code="MATH_CG",
            coefficient=Decimal(3),
            classroom=cls.classe,
            weekly_slots=2,
        )
        cls.seule = Subject.objects.create(
            name="Physique-Chimie",
            code="PC_CG",
            coefficient=Decimal(2),
            classroom=cls.classe,
            weekly_slots=2,
        )

    def _eleve(self, suffixe):
        compte = User.objects.create_user(
            username=f"eleve.{suffixe}",
            password="x",
            role=UserRole.STUDENT,
            first_name="Awa",
            last_name="TRAORE",
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=compte,
            matricule=f"LT{suffixe}",
            classroom=self.classe,
            etablissement=self.etablissement,
        )

    def _noter(self, eleve, matiere, trimestre, valeur):
        return Grade.objects.create(
            student=eleve,
            subject=matiere,
            classroom=self.classe,
            academic_year=self.annee,
            term=trimestre,
            value=Decimal(valeur),
            homework_scores=[valeur, valeur, valeur],
        )

    def _fusionner(self, **options):
        sortie = StringIO()
        call_command(
            "fusionner_les_matieres_en_double",
            etablissement=self.etablissement.name,
            stdout=sortie,
            **options,
        )
        return sortie.getvalue()


class LaSimulationNeTouchePasALaBaseTests(SocleDUneClasseEnDoubleTests):
    def test_sans_appliquer_rien_ne_disparait(self):
        eleve = self._eleve("001")
        self._noter(eleve, self.doublon, "T1", 12)

        rapport = self._fusionner()

        self.assertIn("Simulation", rapport)
        self.assertTrue(Subject.objects.filter(pk=self.doublon.pk).exists())
        self.assertEqual(Grade.objects.count(), 1)

    def test_elle_annonce_ce_qu_elle_ferait(self):
        eleve = self._eleve("002")
        self._noter(eleve, self.doublon, "T1", 12)

        rapport = self._fusionner()

        self.assertIn("Mathématique (Math)", rapport)
        self.assertIn("1 notes", rapport)


class AucunEleveNePerdSaSeuleNoteTests(SocleDUneClasseEnDoubleTests):
    """Le point qui a fait rejeter la premiere version de la commande."""

    def test_une_note_sans_equivalent_est_deplacee(self):
        eleve = self._eleve("010")
        note = self._noter(eleve, self.doublon, "T1", 14)

        self._fusionner(appliquer=True, forcer=True)

        note.refresh_from_db()
        self.assertEqual(note.subject_id, self.gardee.pk)
        self.assertEqual(note.value, Decimal(14))

    def test_une_note_qui_a_son_equivalent_est_supprimee(self):
        """Celle de la matiere gardee fait foi: elle couvre tous les eleves."""
        eleve = self._eleve("011")
        self._noter(eleve, self.gardee, "T1", 18)
        self._noter(eleve, self.doublon, "T1", 9)

        self._fusionner(appliquer=True, forcer=True)

        notes = Grade.objects.filter(student=eleve, term="T1")
        self.assertEqual(notes.count(), 1)
        self.assertEqual(notes.first().value, Decimal(18))

    def test_chaque_eleve_garde_une_note_par_trimestre(self):
        """La formulation qui compte, quelle que soit la repartition d'origine."""
        premier = self._eleve("012")
        second = self._eleve("013")
        self._noter(premier, self.gardee, "T1", 15)
        self._noter(premier, self.doublon, "T2", 11)
        self._noter(second, self.doublon, "T1", 13)
        self._noter(second, self.doublon, "T2", 16)

        self._fusionner(appliquer=True, forcer=True)

        for eleve in (premier, second):
            for trimestre in ("T1", "T2"):
                with self.subTest(eleve=eleve.matricule, trimestre=trimestre):
                    self.assertTrue(
                        Grade.objects.filter(
                            student=eleve, subject=self.gardee, term=trimestre
                        ).exists()
                    )


class LesResultatsDExamenSuiventLeursDeuxContraintesTests(
    SocleDUneClasseEnDoubleTests
):
    """`ExamResult` porte deux unicites, et la seconde m'avait echappe.

    (epreuve, eleve) quand l'epreuve existe; (session, eleve, matiere) quand il
    n'y en a pas. Reporter la matiere d'un resultat sans epreuve peut heurter la
    seconde, et c'est ce qui a interrompu la fusion apres quatre matieres sur
    deux cent cinquante-neuf.
    """

    def _session(self, trimestre="T1"):
        from apps.school.models import ExamSession

        session, _ = ExamSession.objects.get_or_create(
            title=f"Composition {trimestre}",
            term=trimestre,
            academic_year=self.annee,
            defaults={
                "start_date": date(2025, 12, 1),
                "end_date": date(2025, 12, 7),
            },
        )
        return session

    def _resultat(self, session, eleve, matiere, note):
        from apps.school.models import ExamResult

        return ExamResult.objects.create(
            session=session,
            student=eleve,
            subject=matiere,
            score=Decimal(note),
        )

    def test_un_resultat_sans_equivalent_est_reporte(self):
        from apps.school.models import ExamResult

        eleve = self._eleve("020")
        session = self._session()
        resultat = self._resultat(session, eleve, self.doublon, 13)

        self._fusionner(appliquer=True, forcer=True)

        resultat.refresh_from_db()
        self.assertEqual(resultat.subject_id, self.gardee.pk)
        self.assertEqual(ExamResult.objects.count(), 1)

    def test_un_resultat_en_conflit_est_supprime_et_non_reporte(self):
        """Celui de la matiere gardee fait foi, et la fusion ne s'arrete pas."""
        from apps.school.models import ExamResult

        eleve = self._eleve("021")
        session = self._session()
        self._resultat(session, eleve, self.gardee, 17)
        self._resultat(session, eleve, self.doublon, 8)

        self._fusionner(appliquer=True, forcer=True)

        restants = ExamResult.objects.filter(student=eleve, session=session)
        self.assertEqual(restants.count(), 1)
        self.assertEqual(restants.first().score, Decimal(17))
        self.assertFalse(Subject.objects.filter(pk=self.doublon.pk).exists())

    def test_la_fusion_va_jusqu_au_bout_malgre_un_conflit(self):
        """Une paire en conflit ne doit pas emporter les suivantes."""
        eleve = self._eleve("022")
        session = self._session()
        self._resultat(session, eleve, self.gardee, 15)
        self._resultat(session, eleve, self.doublon, 6)

        autre = Subject.objects.create(
            name="Anglais",
            code=f"AN-{self.classe.id}",
            coefficient=Decimal(2),
            classroom=self.classe,
        )
        en_double = Subject.objects.create(
            name="Anglais (LV)",
            code="AN_CG",
            coefficient=Decimal(2),
            classroom=self.classe,
        )
        self._noter(eleve, en_double, "T1", 12)

        self._fusionner(appliquer=True, forcer=True)

        self.assertFalse(Subject.objects.filter(pk=en_double.pk).exists())
        self.assertTrue(Subject.objects.filter(pk=autre.pk).exists())


class CeQuElleNeTouchePasTests(SocleDUneClasseEnDoubleTests):
    def test_la_matiere_du_programme_est_celle_qui_reste(self):
        """Elle seule porte les notes de tous les eleves."""
        self._fusionner(appliquer=True, forcer=True)

        self.assertTrue(Subject.objects.filter(pk=self.gardee.pk).exists())
        self.assertFalse(Subject.objects.filter(pk=self.doublon.pk).exists())

    def test_une_matiere_seule_de_son_nom_reste(self):
        """Sans doublon, il n'y a rien a fusionner."""
        self._fusionner(appliquer=True, forcer=True)

        self.assertTrue(Subject.objects.filter(pk=self.seule.pk).exists())

    def test_une_classe_hors_des_listes_n_est_pas_touchee(self):
        """Une classe d'essai n'est pas l'affaire de cette commande."""
        essai = ClassRoom.objects.create(
            name="Classe d'essai",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        premiere = Subject.objects.create(
            name="Anglais", code="AN-essai-1", classroom=essai, coefficient=Decimal(2)
        )
        seconde = Subject.objects.create(
            name="Anglais (LV1)", code="AN-essai-2", classroom=essai,
            coefficient=Decimal(2),
        )

        self._fusionner(appliquer=True, forcer=True)

        self.assertTrue(Subject.objects.filter(pk=premiere.pk).exists())
        self.assertTrue(Subject.objects.filter(pk=seconde.pk).exists())

    def test_une_autre_annee_scolaire_n_est_pas_touchee(self):
        suivante = AcademicYear.objects.create(
            name="2026-2027",
            etablissement=self.etablissement,
            start_date=date(2026, 9, 1),
            end_date=date(2027, 7, 31),
            is_active=False,
        )
        classe = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=suivante,
            etablissement=self.etablissement,
        )
        premiere = Subject.objects.create(
            name="Mathématiques", code=f"MA-{classe.id}", classroom=classe,
            coefficient=Decimal(4),
        )
        seconde = Subject.objects.create(
            name="Mathématique (Math)", code="MATH_SUIV", classroom=classe,
            coefficient=Decimal(3),
        )

        self._fusionner(appliquer=True, forcer=True)

        self.assertTrue(Subject.objects.filter(pk=premiere.pk).exists())
        self.assertTrue(Subject.objects.filter(pk=seconde.pk).exists())
