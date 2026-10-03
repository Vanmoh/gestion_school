/// Les trois tableaux de bord d'encadrement: comptable, censeur, surveillant.
///
/// Ce qu'ils montraient: des **comptes de lignes**. « Paiements enregistrés :
/// 4 165 », « Frais élèves », « Dépenses » — pour un comptable. Le nombre de
/// lignes d'une table ne lui dit rien ; « 93,0 % de recouvrement, 5 040 000
/// FCFA restants » lui dit tout.
///
/// Et ils les obtenaient en rapatriant les lignes pour les compter: 450 élèves
/// et 2 131 absences téléchargés pour afficher deux nombres. L'intercepteur
/// recolle les pages, donc les totaux étaient justes — mais cinq allers-retours
/// et quelques mégaoctets de JSON par affichage.
///
/// Ils lisent désormais `/dashboard/`, qui agrège côté serveur, garde une
/// minute de cache, et **ne rend à chaque rôle que ce que la matrice lui
/// accorde** (voir `portee_du_tableau_de_bord.py`). Le comptable reçoit
/// l'argent sans les notes, le censeur le pédagogique sans la caisse, le
/// surveillant l'assiduité des élèves et rien d'autre.
///
/// C'est cette restriction qui rend le partage possible: un seul appel sert
/// trois écrans sans qu'aucun ne voie le domaine du voisin.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/montant.dart';
import '../../../core/providers/navigation_intents.dart';
import '../domain/dashboard_stats.dart';
import 'dashboard_cartes.dart';
import 'dashboard_controller.dart';

/// L'ossature commune aux trois: en-tête, une rangée nommée, « À traiter ».
///
/// Les trois lisent la même source et parlent la même langue que l'écran de la
/// direction: `CarteChiffre` avec une phrase par chiffre, les couleurs du
/// thème, et l'année nommée en clair.
class _TableauDEncadrement extends ConsumerWidget {
  const _TableauDEncadrement({
    required this.rangee,
    required this.cartes,
    required this.lignes,
  });

  /// Le titre de la rangée: « L'argent », « L'école », « L'assiduité ».
  final String rangee;

  final List<Widget> Function(DashboardStats) cartes;
  final List<ActionATraiter> Function(DashboardStats) lignes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compteurs = ref.watch(dashboardStatsProvider);

    Future<void> actualiser() async {
      ref.invalidate(dashboardStatsProvider);
      try {
        await ref.read(dashboardStatsProvider.future);
      } catch (_) {
        // Le geste de tirage reste vif même serveur éteint.
      }
    }

    void ouvrir(String cle) {
      ref.read(adminShellNavigationKeyProvider.notifier).state = cle;
    }

    return RefreshIndicator(
      onRefresh: actualiser,
      child: compteurs.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        ),
        // `Panne` est deja une page defilante: l'envelopper dans un second
        // `ListView` donnait une hauteur non bornee, et l'ecran de panne
        // plantait au lieu d'afficher son message -- une page muette, c'est-a-
        // dire exactement ce que cet ecran existe pour eviter.
        error: (erreur, _) => Panne(erreur: erreur, onReessayer: actualiser),
        data: (stats) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            EnTete(stats: stats, onActualiser: actualiser),
            const SizedBox(height: 24),
            Rangee(titre: rangee, cartes: cartes(stats)),
            const SizedBox(height: 20),
            ATraiter(lignes: lignes(stats), onOuvrirModule: ouvrir),
          ],
        ),
      ),
    );
  }
}

/// Le comptable: l'argent, et rien que l'argent.
///
/// La matrice met `grades` et `attendance` à « - » pour lui, donc la charge
/// utile ne porte ni moyenne générale ni absences — il ne pourrait pas les
/// afficher même en les demandant.
class AccountantDashboardPage extends StatelessWidget {
  const AccountantDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TableauDEncadrement(
      rangee: 'L\'argent',
      cartes: (stats) => [
        CarteChiffre(
          libelle: 'Recouvrement',
          valeur: _taux(stats.collectionRate),
          phrase: stats.feesOutstanding > 0
              ? '${montantEnFrancs(stats.feesOutstanding)} restent à encaisser'
              : 'Tout l\'échéancier est soldé',
          icone: Icons.savings_outlined,
          jauge: stats.feesDue > 0 ? stats.collectionRate / 100 : null,
        ),
        CarteChiffre(
          libelle: 'Encaissé ce mois-ci',
          valeur: montantAbrege(stats.monthlyRevenue),
          unite: 'FCFA',
          phrase: (stats.monthlyExpenses + stats.monthlyExpensesPending) > 0
              ? '${montantEnFrancs(stats.monthlyExpenses + stats.monthlyExpensesPending)} de charges sur le mois'
              : 'aucune charge enregistrée ce mois-ci',
          icone: Icons.payments_outlined,
        ),
        CarteChiffre(
          libelle: 'Dépenses à valider',
          valeur: montantAbrege(stats.yearExpensesPending),
          unite: 'FCFA',
          phrase: stats.yearExpensesPendingCount == 0
              ? 'Aucune charge en attente de signature'
              : '${stats.yearExpensesPendingCount} '
                    '${stats.yearExpensesPendingCount == 1 ? "ligne attend" : "lignes attendent"}'
                    ' une signature',
          icone: Icons.approval_outlined,
          alerte: stats.yearExpensesPendingCount > 0,
        ),
        CarteChiffre(
          libelle: 'Masse salariale',
          valeur: montantAbrege(stats.payrollTotal),
          unite: 'FCFA',
          phrase: stats.payrollCount == 0
              ? 'aucune fiche de paie sur l\'année'
              : '${stats.payrollCount} '
                    '${stats.payrollCount == 1 ? "fiche" : "fiches"} de paie',
          icone: Icons.badge_outlined,
        ),
      ],
      lignes: (stats) => [
        // Sa propre file d'attente d'abord: c'est lui qui prépare ces
        // validations, et les voir ailleurs ne sert à personne.
        if (stats.yearExpensesPendingCount > 0)
          ActionATraiter(
            titre:
                '${stats.yearExpensesPendingCount} '
                '${stats.yearExpensesPendingCount == 1 ? "dépense attend" : "dépenses attendent"}'
                ' une validation',
            detail: montantEnFrancs(stats.yearExpensesPending),
            icone: Icons.approval_outlined,
            module: 'finance',
            urgent: true,
          ),
        if (stats.studentsUnpaid > 0)
          ActionATraiter(
            titre:
                '${stats.studentsUnpaid} '
                '${stats.studentsUnpaid == 1 ? "élève a" : "élèves ont"}'
                ' un reste à payer',
            detail: montantEnFrancs(stats.feesOutstanding),
            icone: Icons.receipt_long_outlined,
            module: 'finance',
          ),
      ],
    );
  }
}

/// Le censeur: le pédagogique et le service des enseignants.
///
/// `finance` est à « - » pour lui: ni recouvrement ni impayés dans sa charge
/// utile, alors que l'ancien écran les lui montrait. En revanche `payroll` est
/// à « E » — il valide des paies — et `teacher_timesheet` aussi: l'assiduité
/// des enseignants est son domaine.
class CensorDashboardPage extends StatelessWidget {
  const CensorDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TableauDEncadrement(
      rangee: 'L\'école',
      cartes: (stats) => [
        CarteChiffre(
          libelle: 'Moyenne générale',
          valeur: _note(stats.generalAverage),
          unite: '/ 20',
          phrase: stats.gradesCount == 0
              ? 'aucune note saisie sur l\'année'
              : 'sur ${stats.gradesCount} '
                    '${stats.gradesCount == 1 ? "note" : "notes"} saisies',
          icone: Icons.school_outlined,
        ),
        CarteChiffre(
          libelle: 'Bulletins remis',
          valeur: '${stats.bulletinsDelivered}',
          unite: 'sur ${stats.bulletinsTotal}',
          phrase: stats.bulletinsFailed > 0
              ? '${stats.bulletinsFailed} '
                    '${stats.bulletinsFailed == 1 ? "envoi a échoué" : "envois ont échoué"}'
              : stats.bulletinsTotal == 0
              ? 'aucun bulletin préparé'
              : 'aucun envoi en échec',
          icone: Icons.description_outlined,
          jauge: stats.partDesBulletins,
          alerte: stats.bulletinsFailed > 0,
        ),
        CarteChiffre(
          libelle: 'Assiduité enseignants',
          valeur: '${stats.teacherAbsences}',
          unite: 'absences',
          phrase: stats.teacherLate == 0
              ? 'aucun retard relevé'
              : '${stats.teacherLate} '
                    '${stats.teacherLate == 1 ? "retard" : "retards"} également',
          icone: Icons.how_to_reg_outlined,
          alerte: stats.teacherAbsences > 0,
        ),
        CarteChiffre(
          libelle: 'Effectif de l\'année',
          valeur: '${stats.students}',
          unite: stats.students == 1 ? 'élève' : 'élèves',
          phrase:
              '${stats.classrooms} ${stats.classrooms == 1 ? "classe" : "classes"}'
              ' · ${stats.teachers} '
              '${stats.teachers == 1 ? "enseignant" : "enseignants"}',
          icone: Icons.groups_outlined,
        ),
      ],
      lignes: (stats) {
        final manquants = stats.bulletinsTotal - stats.bulletinsDelivered;
        return [
          if (manquants > 0)
            ActionATraiter(
              titre:
                  '$manquants '
                  '${manquants == 1 ? "bulletin n’est pas remis" : "bulletins ne sont pas remis"}',
              detail: stats.bulletinsFailed > 0
                  ? 'dont ${stats.bulletinsFailed} en échec d\'envoi'
                  : 'sur ${stats.bulletinsTotal} préparés',
              icone: Icons.description_outlined,
              module: 'reports',
              urgent: stats.bulletinsFailed > 0,
            ),
          if (stats.teacherAbsences > 0)
            ActionATraiter(
              titre:
                  '${stats.teacherAbsences} '
                  '${stats.teacherAbsences == 1 ? "absence" : "absences"} d’enseignant',
              detail: stats.teacherLate > 0
                  ? 'et ${stats.teacherLate} retards à examiner'
                  : 'à examiner',
              icone: Icons.how_to_reg_outlined,
              module: 'teacher_timesheet',
            ),
        ];
      },
    );
  }
}

/// Le surveillant: l'assiduité et la discipline des élèves.
///
/// `finance`, `grades`, `payroll` et `teacher_timesheet` sont tous à « - »
/// pour lui — l'ancien écran lui montrait pourtant le recouvrement de l'école.
/// Il garde `students`, `attendance`, `exams`, `reports` et `stock`.
class SupervisorDashboardPage extends StatelessWidget {
  const SupervisorDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _TableauDEncadrement(
      rangee: 'L\'assiduité',
      cartes: (stats) => [
        CarteChiffre(
          libelle: 'Absences du mois',
          valeur: '${stats.monthlyAbsences}',
          phrase: stats.phraseDesAbsences,
          icone: Icons.event_busy_outlined,
          alerte: stats.monthlyAbsences > 0,
        ),
        CarteChiffre(
          libelle: 'Élèves suivis',
          valeur: '${stats.students}',
          unite: stats.students == 1 ? 'élève' : 'élèves',
          phrase:
              'répartis sur ${stats.classrooms} '
              '${stats.classrooms == 1 ? "classe" : "classes"}',
          icone: Icons.groups_outlined,
        ),
        CarteChiffre(
          libelle: 'Bulletins remis',
          valeur: '${stats.bulletinsDelivered}',
          unite: 'sur ${stats.bulletinsTotal}',
          phrase: stats.bulletinsFailed > 0
              ? '${stats.bulletinsFailed} envois en échec'
              : 'aucun envoi en échec',
          icone: Icons.description_outlined,
          jauge: stats.partDesBulletins,
        ),
        CarteChiffre(
          libelle: 'Stock',
          valeur: '${stats.stockBelowThreshold}',
          unite: 'sous seuil',
          phrase: stats.stockTotal == 0
              ? 'aucun article en magasin'
              : 'sur ${stats.stockTotal} articles',
          icone: Icons.inventory_2_outlined,
          alerte: stats.stockBelowThreshold > 0,
        ),
      ],
      lignes: (stats) => [
        if (stats.stockBelowThreshold > 0)
          ActionATraiter(
            titre:
                '${stats.stockBelowThreshold} '
                '${stats.stockBelowThreshold == 1 ? "article est" : "articles sont"}'
                ' sous leur seuil',
            detail: 'sur ${stats.stockTotal} en magasin',
            icone: Icons.inventory_2_outlined,
            module: 'stock',
          ),
        if (stats.studentsUnassigned > 0)
          ActionATraiter(
            titre:
                '${stats.studentsUnassigned} '
                '${stats.studentsUnassigned == 1 ? "élève inscrit n’a" : "élèves inscrits n’ont"}'
                ' pas de classe',
            detail: 'Ils ne comptent dans aucune année',
            icone: Icons.person_add_alt,
            module: 'students',
            urgent: true,
          ),
      ],
    );
  }
}

String _taux(double valeur) =>
    '${valeur.toStringAsFixed(1).replaceAll('.', ',')} %';

String _note(double valeur) => valeur.toStringAsFixed(2).replaceAll('.', ',');
