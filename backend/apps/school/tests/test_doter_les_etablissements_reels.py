"""Ce que la commande de dotation doit tenir, et qu'aucun test ne gardait.

`doter_les_etablissements_reels` monte une ecole entiere: classes, matieres,
eleves, enseignants, emploi du temps, notes, frais, discipline, paie,
surveillance. Quinze cents lignes sans filet, alors qu'elle promet trois choses
qui se cassent silencieusement.

**Le sigle distingue deux ecoles homonymes.** « Lycee Technique Oumar Bah
(LTOB) » et « Lycee Oumar Bah (LOBK) » se sont deja confondus: le second avait
recu les cinq classes du premier, alors qu'il en compte treize. Une inclusion de
chaine suffit a refaire l'erreur, et rien ne l'aurait signalee -- une ecole
peuplee a l'air peuplee.

**Le tirage ne depend pas du processus.** `random.Random(chaine)` est stable,
`hash(chaine)` ne l'est pas: Python le randomise a chaque demarrage. Un seul
`hash()` oublie dans la commande, et « meme graine, meme ecole » devient faux
sans qu'aucune erreur ne soit levee.

**Les consignes chiffrees sont exactes.** Un eleve sur quatre n'a pas solde sa
scolarite, et aucun n'a d'inscription impayee. « A peu pres 25 % » n'est pas la
consigne, et un tirage par eleve derive: il avait donne 28 %.
"""

from decimal import Decimal
from io import StringIO

from django.core.management import call_command
from django.db.models import Sum
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.school.management.commands.doter_les_etablissements_reels import Command
from apps.school.management.commands.insert_classes import ESTABLISSEMENT_CLASSES
from apps.school.models import (
    ClassRoom,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    FeeType,
    Payment,
    StockItem,
    Student,
    StudentFee,
    Subject,
    Teacher,
    TeacherScheduleSlot,
)


class LeSigleDistingueDeuxEcolesHomonymesTests(TestCase):
    """Le defaut corrige, et la seule barriere qui l'empeche de revenir."""

    def _classes_de(self, nom, code=""):
        """L'ecole n'est pas sauvee: `_classes_de` ne lit que son nom et son code.

        Elle ne peut pas l'etre: `9999_insert_etablissements` a deja insere les
        quatre, et le nom est unique. Decrire sans ecrire evite la collision et
        rend ces cinq tests independants de la base.
        """
        return Command()._classes_de(
            Etablissement(name=nom, code=code), ESTABLISSEMENT_CLASSES
        )

    def test_le_lycee_technique_recoit_ses_cinq_classes(self):
        self.assertEqual(
            len(self._classes_de("Lycée Technique Oumar Bah (LTOB)", "LT")), 5
        )

    def test_le_lycee_oumar_bah_recoit_ses_treize_classes(self):
        """Le cas qui avait echoue: treize classes, et non les cinq de l'autre."""
        self.assertEqual(len(self._classes_de("Lycée Oumar Bah (LOBK)", "LO")), 13)

    def test_les_deux_ecoles_ne_recoivent_pas_la_meme_liste(self):
        """La formulation qui survit a un changement d'effectif.

        Si demain le LTOB gagne une classe, les deux tests ci-dessus se
        rectifient; celui-ci dit ce qui compte vraiment et ne bougera pas.
        """
        technique = self._classes_de("Lycée Technique Oumar Bah (LTOB)", "LT")
        lobk = self._classes_de("Lycée Oumar Bah (LOBK)", "LO")

        self.assertNotEqual(set(technique), set(lobk))

    def test_une_ecole_inconnue_n_est_pas_devinee(self):
        """Mieux vaut ignorer une ecole que lui donner le programme d'une autre."""
        self.assertIsNone(self._classes_de("Lycée de Ségou", "LSEG"))

    def test_l_ancien_nom_reste_reconnu(self):
        """Une base non migree ne doit pas se retrouver sans classes."""
        self.assertEqual(
            len(self._classes_de("Lycée Technique Oumar Bah (LOBK)", "LT2")), 13
        )


class LeNomDeLaClasseDonneSonProgrammeTests(TestCase):
    """Deduire la filiere du nom, sans tabuler quarante-deux listes."""

    def _codes(self, nom_de_classe):
        return {code for _, code, _ in Command()._curriculum_de(nom_de_classe)}

    def test_la_gestion_et_l_electromecanique_ne_font_pas_le_meme_programme(self):
        self.assertNotEqual(self._codes("11ème CG"), self._codes("2ème Année EM1"))

    def test_le_sigle_doit_etre_un_mot_entier(self):
        """« 11ème S » ne doit pas etre lu dans « SES », ni l'inverse.

        C'est la raison d'etre de la sentinelle `(?<![A-Z])...(?![A-Z])`: sans
        elle, un sigle court se retrouve dans tous les longs.
        """
        self.assertNotEqual(self._codes("11ème SES"), self._codes("11ème S"))

    def test_une_classe_du_fondamental_recoit_le_programme_du_fondamental(self):
        self.assertTrue(self._codes("5ème Année"))

    def test_le_tronc_commun_est_dans_chaque_filiere(self):
        commun = self._codes("11ème CG") & self._codes("11ème CT") & self._codes(
            "2ème Année EM1"
        )
        self.assertTrue(commun, "aucune matiere commune entre trois filieres")


class LAleaNeDependPasDuProcessusTests(TestCase):
    """« Meme graine, meme ecole » -- y compris d'un lancement a l'autre.

    Ces valeurs sont figees en dur exprès. Un test qui compare deux appels dans
    le meme processus passerait meme avec `hash()`, puisque la randomisation est
    fixee au demarrage. Seule une valeur ecrite ici constate la stabilite entre
    processus.
    """

    def test_un_tirage_est_reproductible_dans_le_meme_processus(self):
        premier = Command._alea(2026, "notes", 17).random()
        second = Command._alea(2026, "notes", 17).random()

        self.assertEqual(premier, second)

    def test_deux_objets_differents_tirent_differemment(self):
        self.assertNotEqual(
            Command._alea(2026, "notes", 17).random(),
            Command._alea(2026, "notes", 18).random(),
        )

    def test_la_graine_change_le_tirage(self):
        self.assertNotEqual(
            Command._alea(2026, "notes", 17).random(),
            Command._alea(2027, "notes", 17).random(),
        )

    def test_le_tirage_est_stable_d_un_processus_a_l_autre(self):
        """La valeur attendue vient d'un autre processus que celui-ci.

        Si elle change, c'est qu'un `hash()` s'est glisse dans la chaine de
        tirage -- ou que `random.Random` a change d'algorithme, ce que Python ne
        fait pas sans le dire.
        """
        tirage = Command._alea(2026, "temoin", 1)

        self.assertEqual(tirage.randrange(1000000), 816826)


class UneEcoleMonteeDeBoutEnBoutTests(TestCase):
    """Le montage reel, sur la plus petite ecole et deux eleves par classe.

    Deux eleves suffisent: ce qu'on verifie ici, ce sont des proprietes de la
    commande, pas des volumes. Les notes sont ecartees -- elles pesent trois
    mille lignes pour ne rien prouver de plus.
    """

    @classmethod
    def setUpTestData(cls):
        # Celle que les migrations ont inseree, et non une copie: son nom est
        # unique, et c'est elle que la commande sait reconnaitre.
        cls.etablissement = Etablissement.objects.get(
            name="Lycée Technique Oumar Bah (LTOB)"
        )
        call_command(
            "doter_les_etablissements_reels",
            etablissement=cls.etablissement.name,
            eleves_par_classe=4,
            sans_notes=True,
            forcer=True,
            stdout=StringIO(),
        )

    def _du_et_regle(self, **filtres):
        """Deux requetes separees, jamais jointes.

        Joindre les frais et leurs paiements dans un meme `annotate` multiplie
        les lignes, et `distinct=True` sur un `Sum` dedoublonne les montants
        egaux: deux facons de se mentir sur une caisse.
        """
        du = {
            eleve: montant or Decimal(0)
            for eleve, montant in StudentFee.objects.filter(
                student__etablissement=self.etablissement, **filtres
            )
            .values_list("student_id")
            .annotate(s=Sum("amount_due"))
        }
        regle = {
            eleve: montant or Decimal(0)
            for eleve, montant in Payment.objects.filter(
                fee__student__etablissement=self.etablissement,
                is_cancelled=False,
                **{f"fee__{champ}": valeur for champ, valeur in filtres.items()},
            )
            .values_list("fee__student_id")
            .annotate(s=Sum("amount"))
        }
        return du, regle

    def test_chaque_classe_a_son_effectif(self):
        classes = ClassRoom.objects.filter(etablissement=self.etablissement)
        self.assertEqual(classes.count(), 5)
        for classe in classes:
            self.assertEqual(Student.objects.filter(classroom=classe).count(), 4)

    def test_aucun_enseignant_ne_reste_sans_heures(self):
        """Un enseignant sans heures ne peut rien faire dans l'application.

        Il n'a pas de cours a l'emploi du temps, donc pas de notes a saisir, pas
        de pointage et une fiche de paie a zero. Huit sur dix-sept se sont
        retrouves dans ce cas avant que les creneaux passent de trois a six.
        """
        sans_heures = Teacher.objects.filter(
            etablissement=self.etablissement
        ).exclude(id__in=TeacherScheduleSlot.objects.values("assignment__teacher_id"))

        self.assertEqual(list(sans_heures), [])

    def test_chaque_matiere_a_un_volume_horaire(self):
        """Sans `weekly_slots`, la generation d'emploi du temps n'a rien a placer."""
        sans_volume = Subject.objects.filter(
            classroom__etablissement=self.etablissement, weekly_slots=0
        )

        self.assertEqual(sans_volume.count(), 0)

    def test_toutes_les_inscriptions_sont_reglees(self):
        """La consigne est nette: aucun impaye sur l'inscription."""
        du, regle = self._du_et_regle(fee_type=FeeType.REGISTRATION)

        impayees = [e for e, montant in du.items() if regle.get(e, Decimal(0)) < montant]

        self.assertEqual(impayees, [])
        self.assertEqual(len(du), Student.objects.filter(
            etablissement=self.etablissement
        ).count())

    def test_un_quart_exactement_n_a_pas_solde_sa_scolarite(self):
        """Exactement, et non « a peu pres »: un tirage par eleve derivait a 28 %."""
        effectif = Student.objects.filter(etablissement=self.etablissement).count()
        du, regle = self._du_et_regle()

        non_soldes = sum(
            1 for e, montant in du.items() if regle.get(e, Decimal(0)) < montant
        )

        self.assertEqual(non_soldes, effectif // 4)

    def test_l_encadrement_est_nomme(self):
        """Sans directeur ni comptable, l'ecole n'a personne pour l'ouvrir."""
        roles = set(
            User.objects.filter(etablissement=self.etablissement).values_list(
                "role", flat=True
            )
        )

        self.assertLessEqual(
            {
                UserRole.DIRECTOR,
                UserRole.CENSOR,
                UserRole.ACCOUNTANT,
                UserRole.SUPERVISOR,
                UserRole.PROMOTER,
            },
            roles,
        )

    def test_le_stock_porte_une_seule_alerte_de_seuil(self):
        """Une seule, et c'est la preuve que les entrees ont ete comptees.

        Un `movement_type` mal orthographie -- « IN » au lieu de « in » --
        ramenait chaque article a zero, et les quatre passaient sous leur seuil.
        Quatre alertes au lieu d'une, sans qu'aucune erreur ne soit levee.
        """
        articles = list(StockItem.objects.filter(etablissement=self.etablissement))

        self.assertTrue(articles)
        sous_seuil = [a for a in articles if a.quantity < a.minimum_threshold]
        self.assertEqual(len(sous_seuil), 1)

    def test_quelques_epreuves_restent_a_pourvoir(self):
        """L'onglet « Surveillance » n'a de sens que s'il reste du travail."""
        epreuves = ExamPlanning.objects.filter(
            classroom__etablissement=self.etablissement
        )
        pourvues = ExamInvigilation.objects.filter(
            planning__classroom__etablissement=self.etablissement
        ).values("planning_id").distinct().count()

        self.assertTrue(epreuves.exists())
        self.assertGreater(pourvues, 0)
        self.assertLess(pourvues, epreuves.count())


class LaCommandeRelanceeNeDoublRienTests(TestCase):
    """L'idempotence, verifiee par un second passage complet.

    C'est la propriete la plus facile a perdre: un generateur d'alea partage
    avance selon ce qui existe deja, et le second passage tombe sur d'autres
    valeurs -- donc cree de nouvelles lignes au lieu de retrouver les anciennes.
    """

    def test_un_second_passage_ne_cree_rien(self):
        etablissement = Etablissement.objects.get(
            name="Lycée Technique Oumar Bah (LTOB)"
        )
        appel = dict(
            etablissement=etablissement.name,
            eleves_par_classe=4,
            sans_notes=True,
            forcer=True,
        )
        call_command("doter_les_etablissements_reels", stdout=StringIO(), **appel)

        avant = {
            "eleves": Student.objects.count(),
            "enseignants": Teacher.objects.count(),
            "matieres": Subject.objects.count(),
            "creneaux": TeacherScheduleSlot.objects.count(),
            "frais": StudentFee.objects.count(),
            "paiements": Payment.objects.count(),
            "comptes": User.objects.count(),
        }

        call_command("doter_les_etablissements_reels", stdout=StringIO(), **appel)

        self.assertEqual(
            avant,
            {
                "eleves": Student.objects.count(),
                "enseignants": Teacher.objects.count(),
                "matieres": Subject.objects.count(),
                "creneaux": TeacherScheduleSlot.objects.count(),
                "frais": StudentFee.objects.count(),
                "paiements": Payment.objects.count(),
                "comptes": User.objects.count(),
            },
        )
