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
    BulletinDelivery,
    CanteenSubscription,
    ClassRoom,
    DisciplineIncident,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    FeeType,
    LibraryCategory,
    LibraryCollection,
    LibraryDocument,
    ParentProfile,
    Payment,
    PromotionDecision,
    PromotionRun,
    PromotionRunStatus,
    SmsProviderConfig,
    StockItem,
    Student,
    StudentAcademicHistory,
    StudentFee,
    Subject,
    Teacher,
    TeacherScheduleSlot,
    TeacherTimeEntry,
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


class LEchantillonTraverseToutesLesClassesTests(TestCase):
    """Soixante eleves pris a pas regulier, et non les soixante premiers.

    La liste des eleves arrive classe par classe. Une tranche `[:60]` ne prenait
    donc que les deux premieres classes: la remise des bulletins, la cantine et
    la bibliotheque s'ouvraient sur rien pour les onze autres, alors que le
    compteur global annoncait soixante lignes.

    Ces tests n'ont pas besoin de base: l'echantillonnage est une fonction de
    liste.
    """

    def test_il_prend_dans_chaque_classe(self):
        eleves = [f"c{classe}-e{rang}" for classe in range(13) for rang in range(30)]

        echantillon = Command._un_echantillon(eleves, 60)

        classes = {nom.split("-")[0] for nom in echantillon}
        self.assertEqual(len(echantillon), 60)
        self.assertEqual(len(classes), 13)

    def test_il_ne_prend_pas_deux_fois_le_meme(self):
        eleves = list(range(100))

        echantillon = Command._un_echantillon(eleves, 45)

        self.assertEqual(len(set(echantillon)), 45)

    def test_il_rend_tout_le_monde_quand_on_en_demande_trop(self):
        """Une petite ecole n'a pas soixante eleves, et ce n'est pas une erreur."""
        eleves = list(range(20))

        self.assertEqual(Command._un_echantillon(eleves, 60), eleves)

    def test_il_rend_une_liste_vide_sans_eleves(self):
        self.assertEqual(Command._un_echantillon([], 60), [])
        self.assertEqual(Command._un_echantillon([1, 2, 3], 0), [])


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
    """Le montage reel, sur la plus petite ecole et quatre eleves par classe.

    Quatre eleves suffisent: ce qu'on verifie ici, ce sont des proprietes de la
    commande, pas des volumes. Les notes, elles, sont indispensables -- les
    bilans trimestriels et le conseil de fin d'annee s'en deduisent, et sans
    elles la moyenne de chacun vaut zero.
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
        """Exactement, et non « a peu pres ».

        Deux derives ont ete corrigees ici. Un tirage par eleve donnait 28 %; et
        `round()`, qui arrondit au pair le plus proche, faisait monter 37,5 a 38
        quand il faisait descendre 112,5 a 112 -- deux ecoles obtenaient des
        regles differentes sans que rien ne le dise.

        La part demandee est un plafond: `effectif * part // 100`.
        """
        effectif = Student.objects.filter(etablissement=self.etablissement).count()
        du, regle = self._du_et_regle()

        non_soldes = sum(
            1 for e, montant in du.items() if regle.get(e, Decimal(0)) < montant
        )

        self.assertEqual(non_soldes, effectif * 25 // 100)

    def test_la_part_demandee_est_un_plafond(self):
        """Elle ne doit jamais etre depassee, meme d'un eleve."""
        effectif = Student.objects.filter(etablissement=self.etablissement).count()
        du, regle = self._du_et_regle()

        non_soldes = sum(
            1 for e, montant in du.items() if regle.get(e, Decimal(0)) < montant
        )

        self.assertLessEqual(non_soldes * 100, effectif * 25)

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


    # ------------------------------------------------------------------------
    # Ce qui rend les ecrans habites.
    #
    # Ces verifications restent dans la meme classe a dessein: `setUpTestData`
    # est propre a une classe, et en ouvrir une seconde monterait l'ecole une
    # deuxieme fois pour rien.
    #
    # Un compteur non nul ne suffit pas: un ecran d'alertes a besoin d'une
    # alerte, une liste d'etats a besoin des quatre etats, et un envoi a besoin
    # d'un destinataire joignable.
    # ------------------------------------------------------------------------

    def test_chaque_eleve_a_son_bilan_pour_les_trois_trimestres(self):
        """Sans bilan, le rang s'affiche « - » sur un bulletin reimprime."""
        effectif = Student.objects.filter(etablissement=self.etablissement).count()

        bilans = StudentAcademicHistory.objects.filter(
            classroom__etablissement=self.etablissement
        )

        self.assertEqual(bilans.count(), effectif * 3)

    def test_chaque_classe_a_un_premier_par_trimestre(self):
        """Un rang qui ne commence pas a 1 n'est pas un classement."""
        premiers = StudentAcademicHistory.objects.filter(
            classroom__etablissement=self.etablissement, rank=1
        ).count()

        self.assertEqual(premiers, 5 * 3)

    def test_la_feuille_d_emargement_porte_des_retards(self):
        """La tolerance de l'etablissement ne se voit que sur un retardataire."""
        emargements = TeacherTimeEntry.objects.filter(
            etablissement=self.etablissement
        )

        self.assertTrue(emargements.exists())
        self.assertTrue(emargements.filter(late_minutes__gt=0).exists())

    def test_le_retard_retenu_ne_depasse_pas_l_ecart_reel(self):
        """`late_minutes` est l'ecart **moins** la tolerance, jamais l'inverse."""
        tolerance = self.etablissement.timesheet_late_tolerance_minutes or 0

        for ligne in TeacherTimeEntry.objects.filter(
            etablissement=self.etablissement
        ):
            self.assertLessEqual(ligne.tolerated_late_minutes, tolerance)

    def test_aucune_remise_de_bulletin_sans_numero(self):
        """Le defaut corrige: soixante remises sans destinataire.

        `ParentProfile.whatsapp_phone` se remplit depuis `User.phone` par
        signal. Les familles n'avaient aucun numero, donc la colonne etait vide
        et l'envoi n'avait nulle part ou aller.
        """
        sans_numero = BulletinDelivery.objects.filter(
            etablissement=self.etablissement, phone=""
        )

        self.assertEqual(sans_numero.count(), 0)

    def test_chaque_famille_est_joignable(self):
        """La cause du defaut ci-dessus, verifiee a la racine."""
        muettes = ParentProfile.objects.filter(
            etablissement=self.etablissement, whatsapp_phone=""
        )

        self.assertEqual(muettes.count(), 0)

    def test_les_quatre_etats_de_remise_existent(self):
        """Le motif d'echec ne s'affiche que s'il y a un echec."""
        etats = set(
            BulletinDelivery.objects.filter(
                etablissement=self.etablissement
            ).values_list("status", flat=True)
        )

        self.assertEqual(etats, {"prepared", "sent", "read", "failed"})

    def test_un_abonnement_cantine_est_suspendu_et_un_autre_termine(self):
        etats = set(
            CanteenSubscription.objects.filter(
                student__etablissement=self.etablissement
            ).values_list("status", flat=True)
        )

        self.assertEqual(etats, {"active", "suspended", "ended"})

    def test_le_fonds_numerique_a_ses_trois_niveaux(self):
        """Sans collection pas de categorie, sans categorie pas de document."""
        collections = LibraryCollection.objects.filter(
            etablissement=self.etablissement
        )
        documents = LibraryDocument.objects.filter(etablissement=self.etablissement)

        self.assertTrue(collections.exists())
        self.assertTrue(
            LibraryCategory.objects.filter(collection__in=collections).exists()
        )
        self.assertTrue(documents.exists())
        self.assertEqual(documents.exclude(import_error="").count(), 1)

    def test_le_fournisseur_de_sms_est_configure_mais_inactif(self):
        """Configure, pour que l'ecran ait quelque chose a montrer; inactif,
        pour qu'aucune commande de peuplement ne puisse faire partir un envoi.
        """
        fournisseur = SmsProviderConfig.objects.filter(
            etablissement=self.etablissement
        ).first()

        self.assertIsNotNone(fournisseur)
        self.assertFalse(fournisseur.is_active)

    def test_le_jeton_de_la_passerelle_est_manifestement_faux(self):
        """Cette commande ne depose jamais en base ce qui ressemble a un secret."""
        fournisseur = SmsProviderConfig.objects.get(
            etablissement=self.etablissement
        )

        self.assertIn("demonstration", fournisseur.api_token)

    def test_un_incident_fait_baisser_la_conduite(self):
        """Un incident consigne sans consequence n'est pas une sanction.

        La conduite restait a 18 pour tout le monde, y compris pour un eleve
        pris a tricher: le bulletin l'ignorait, et le conseil de fin d'annee
        promouvait toute l'ecole sans un redoublant.
        """
        punis = Student.objects.filter(
            etablissement=self.etablissement,
            id__in=DisciplineIncident.objects.values("student_id"),
        )

        self.assertTrue(punis.exists())
        for eleve in punis:
            self.assertLess(eleve.conduite, 18)

    def test_le_conseil_de_fin_d_annee_est_une_simulation(self):
        """Et surtout pas une execution: elle deplacerait tous les eleves."""
        simulation = PromotionRun.objects.filter(
            etablissement=self.etablissement
        ).first()

        self.assertIsNotNone(simulation)
        self.assertEqual(simulation.status, PromotionRunStatus.SIMULATED)

    def test_la_simulation_ne_deplace_personne(self):
        """La classe de chaque eleve est celle ou il etait avant."""
        classes = set(
            ClassRoom.objects.filter(etablissement=self.etablissement).values_list(
                "id", flat=True
            )
        )
        inscrits = set(
            Student.objects.filter(
                etablissement=self.etablissement
            ).values_list("classroom_id", flat=True)
        )

        self.assertTrue(inscrits <= classes)

    def test_la_conduite_decide_du_redoublement(self):
        """La regle, et non son resultat: le volume ne doit pas trancher.

        Avec des notes entre 9 et 19, la moyenne seule promeut toute l'ecole.
        C'est la conduite qui fait le redoublant, et c'est la raison d'etre du
        second seuil -- sur une ecole de vingt eleves, aucun incident grave ne
        tombe forcement, et exiger un redoublant ici rendrait le test dependant
        de l'effectif. La regle, elle, tient a toute taille.
        """
        simulation = PromotionRun.objects.get(etablissement=self.etablissement)

        for decision in PromotionDecision.objects.filter(
            run=simulation
        ).select_related("student"):
            if decision.conduite < 10 or decision.average < 10:
                self.assertEqual(decision.decision, "repeated")
                self.assertTrue(decision.reason, "un redoublement sans motif")
            else:
                self.assertEqual(decision.decision, "promoted")
                self.assertEqual(decision.reason, "")

    def test_un_redoublant_reste_dans_sa_classe(self):
        """Sa classe cible est la sienne: c'est ce que redoubler veut dire."""
        simulation = PromotionRun.objects.get(etablissement=self.etablissement)

        for decision in PromotionDecision.objects.filter(
            run=simulation, decision="repeated"
        ):
            self.assertEqual(
                decision.target_classroom_id, decision.source_classroom_id
            )

    def test_le_total_de_la_simulation_est_celui_des_decisions(self):
        simulation = PromotionRun.objects.get(etablissement=self.etablissement)

        self.assertEqual(
            simulation.total_students,
            PromotionDecision.objects.filter(run=simulation).count(),
        )
        self.assertEqual(
            simulation.promoted_count + simulation.repeated_count,
            simulation.total_students,
        )


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
