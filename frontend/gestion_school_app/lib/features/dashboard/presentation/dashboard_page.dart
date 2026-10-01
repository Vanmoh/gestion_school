/// L'écran d'accueil de la direction: une page, quatre réponses.
///
/// Ce que cette page remplace: 3 261 lignes, 43 classes de widgets, neuf blocs
/// sur un seul écran — bandeau héros, ruban de contexte, filtres visuels, bande
/// de faits saillants, cinq cartes à sparklines, panneau finances, panneau
/// « récit » avec radar *et* barres, anneau de score, panneau constats. Le
/// problème n'était pas l'apparence: l'écran disait beaucoup et signifiait peu.
/// Un radar à quatre axes ne se lit pas, un anneau qui agrège marge et absences
/// ne se décide pas.
///
/// Trois chiffres étaient en outre faux, et personne ne l'avait vu:
///
///  - **611 élèves** et **30 classes** sur une école qui en compte 450 et 15
///    cette année-là. La vue ne consultait aucune année scolaire, et l'écran
///    n'en nommait aucune — donc rien n'invitait à douter du nombre.
///  - **« Bénéfice net 66 965 000 FCFA »**, qui était en réalité le montant
///    encaissé: les charges non encore doublement validées — 4 124 000 FCFA sur
///    trente-six lignes — sont exclues du calcul du bénéfice.
///  - **le recouvrement absent**. C'est pourtant le chiffre d'une école
///    malienne: 93,0 %, et 5 040 000 FCFA qui restent à encaisser.
///
/// La page répond donc à quatre questions, dans cet ordre: qui est là, où en
/// est l'argent, qu'est-ce qui attend une signature, qui manque en classe. Puis
/// elle montre une seule courbe, l'échéancier contre les encaissements, et
/// termine par ce qui demande une décision.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/montant.dart';
import '../../../core/providers/navigation_intents.dart';
import '../domain/dashboard_stats.dart';
import 'dashboard_cartes.dart';
import 'dashboard_controller.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Future<void> _actualiser() async {
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(echeancierProvider);
    try {
      await ref.read(dashboardStatsProvider.future);
    } catch (_) {
      // Le geste de tirage doit rester vif même serveur éteint: l'erreur
      // s'affiche par l'état du provider, pas en bloquant l'animation.
    }
  }

  void _ouvrirModule(String cle) {
    ref.read(adminShellNavigationKeyProvider.notifier).state = cle;
  }

  @override
  Widget build(BuildContext context) {
    final compteurs = ref.watch(dashboardStatsProvider);
    final echeancier = ref.watch(echeancierProvider);
    // Écouté ici pour que la ligne « jamais connectés » du bloc « À traiter »
    // en dispose. Le bandeau, lui, l'écoute pour son propre compte: son
    // minuteur de quinze secondes ne doit pas reconstruire toute la page.
    final presence = ref.watch(presenceProvider);

    return RefreshIndicator(
      onRefresh: _actualiser,
      child: compteurs.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (erreur, _) => Panne(erreur: erreur, onReessayer: _actualiser),
        data: (stats) => _Contenu(
          stats: stats,
          echeancier: echeancier,
          presence: presence,
          onActualiser: _actualiser,
          onOuvrirModule: _ouvrirModule,
        ),
      ),
    );
  }
}

/// Une panne se dit, au lieu de laisser la page muette.
class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.stats,
    required this.echeancier,
    required this.presence,
    required this.onActualiser,
    required this.onOuvrirModule,
  });

  final DashboardStats stats;
  final AsyncValue<Echeancier> echeancier;
  final AsyncValue<PresenceParRole> presence;
  final Future<void> Function() onActualiser;
  final void Function(String) onOuvrirModule;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        EnTete(stats: stats, onActualiser: onActualiser),
        const SizedBox(height: 14),
        const _BandeauPresence(),
        const SizedBox(height: 22),
        _QuatreChiffres(stats: stats),
        const SizedBox(height: 20),
        _PanneauEcheancier(echeancier: echeancier),
        const SizedBox(height: 20),
        _ATraiter(
          stats: stats,
          echeancier: echeancier.valueOrNull,
          presence: presence.valueOrNull,
          onOuvrirModule: onOuvrirModule,
        ),
      ],
    );
  }
}

/// L'école, et l'année que ces chiffres décrivent.
///
/// L'année est ici parce que son absence est ce qui a permis à « 611 élèves »
/// de s'afficher pendant des mois sans que personne ne s'interroge. Un écran
/// qui nomme sa période rend l'écart visible au premier regard.
class _BandeauPresence extends ConsumerStatefulWidget {
  const _BandeauPresence();

  @override
  ConsumerState<_BandeauPresence> createState() => _BandeauPresenceState();
}

class _BandeauPresenceState extends ConsumerState<_BandeauPresence> {
  static const _cadence = Duration(seconds: 15);
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(_cadence, (_) {
      // `mounted` avant d'invalider: un minuteur qui survit à la page ferait
      // repartir une requête sur un provider que plus personne n'écoute.
      if (mounted) {
        ref.invalidate(presenceProvider);
      }
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presence = ref.watch(presenceProvider);

    return presence.when(
      // Ni pendant le chargement ni en cas de refus: un bandeau qui clignote à
      // chaque rafraîchissement serait pire que pas de bandeau.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (donnees) => _LigneDePresence(presence: donnees),
    );
  }
}

class _LigneDePresence extends StatelessWidget {
  const _LigneDePresence({required this.presence});

  final PresenceParRole presence;

  /// L'ordre d'affichage, et les noms qu'une école emploie.
  ///
  /// Les rôles d'encadrement d'abord: ce sont eux dont la présence se décide,
  /// et un directeur qui cherche son comptable ne veut pas parcourir six cents
  /// élèves d'abord.
  static const _ordre = <String, String>{
    'director': 'direction',
    'censor': 'censeur',
    'accountant': 'comptable',
    'supervisor': 'surveillant',
    'teacher': 'enseignants',
    'parent': 'parents',
    'student': 'élèves',
  };

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: couleurs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'EN LIGNE MAINTENANT',
                style: textes.labelSmall?.copyWith(
                  color: couleurs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· signe de vie de moins de ${presence.fenetreSecondes} s',
                style: textes.labelSmall?.copyWith(
                  color: couleurs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (presence.totalEnLigne == 0)
            Text(
              'Personne n\'est connecté en ce moment.',
              style: textes.bodySmall?.copyWith(
                color: couleurs.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final entree in _ordre.entries)
                  if ((presence.enLigneParRole[entree.key] ?? 0) > 0)
                    _Pastille(
                      combien: presence.enLigneParRole[entree.key]!,
                      libelle: entree.value,
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({required this.combien, required this.libelle});

  final int combien;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Un point plein: la présence se dit par la forme autant que par la
        // couleur, et le bandeau ne garde que les rôles qui en ont.
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: couleurs.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          '$combien',
          style: textes.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 4),
        Text(
          libelle,
          style: textes.bodySmall?.copyWith(color: couleurs.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Deux rangées de quatre, étiquetées « L'argent » et « L'école ».
///
/// Quatre chiffres valent mieux que neuf, mais **huit rangés en deux familles
/// nommées se lisent mieux que quatre qui n'en couvrent qu'une seule**. La
/// version précédente ne parlait que de caisse: un directeur d'école lisait
/// son recouvrement et ses charges, et rien sur ses 26 730 notes, ses
/// bulletins ou la présence de ses enseignants.
///
/// La structure fait le travail que le nombre ne peut pas faire: on cherche
/// dans la rangée qui répond à sa question, pas dans un tapis de cartes.
class _QuatreChiffres extends StatelessWidget {
  const _QuatreChiffres({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Rangee(titre: 'L\'argent', cartes: _lArgent()),
        const SizedBox(height: 22),
        Rangee(titre: 'L\'école', cartes: _lEcole()),
      ],
    );
  }

  List<Widget> _lArgent() {
    return [
      CarteChiffre(
        libelle: 'Recouvrement',
        valeur: _taux(stats.collectionRate),
        phrase: stats.feesOutstanding > 0
            ? '${montantEnFrancs(stats.feesOutstanding)} restent à encaisser'
            : 'Tout l\'échéancier est soldé',
        icone: Icons.savings_outlined,
        jauge: stats.feesDue > 0 ? stats.collectionRate / 100 : null,
      ),
      // Ce que la refonte avait perdu: l'ancien écran montrait « Recettes du
      // mois » et « Bénéfice net ». Le bénéfice était faux -- il n'était que
      // l'encaissement, les charges non doublement validées étant exclues --
      // mais le retirer sans rien mettre à la place privait la direction du
      // chiffre qu'elle regarde le matin.
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
    ];
  }

  List<Widget> _lEcole() {
    return [
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
        libelle: 'Assiduité',
        valeur: '${stats.monthlyAbsences}',
        unite: 'absences élèves',
        phrase: stats.phraseDesEnseignants,
        icone: Icons.event_busy_outlined,
        alerte: stats.teacherAbsences > 0,
      ),
    ];
  }

  static String _taux(double valeur) {
    final arrondi = valeur.toStringAsFixed(1).replaceAll('.', ',');
    return '$arrondi %';
  }

  static String _note(double valeur) {
    return valeur.toStringAsFixed(2).replaceAll('.', ',');
  }
}

/// Une rangée nommée, et ses cartes qui se replient selon la largeur.
class _PanneauEcheancier extends StatelessWidget {
  const _PanneauEcheancier({required this.echeancier});

  final AsyncValue<Echeancier> echeancier;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Échéancier et encaissements',
              style: textes.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            echeancier.when(
              // Une courbe indisponible n'efface pas la page: les quatre
              // chiffres restent, et le panneau dit ce qui manque.
              loading: () => Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Lecture de l\'échéancier…',
                      style: textes.bodySmall?.copyWith(
                        color: couleurs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'L\'échéancier n\'a pas pu être lu. Les chiffres ci-dessus '
                  'restent valables.',
                  style: textes.bodySmall?.copyWith(
                    color: couleurs.onSurfaceVariant,
                  ),
                ),
              ),
              data: (donnees) => _Barres(echeancier: donnees),
            ),
          ],
        ),
      ),
    );
  }
}

class _Barres extends StatelessWidget {
  const _Barres({required this.echeancier});

  final Echeancier echeancier;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;
    final mois = echeancier.mois;

    if (mois.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Aucune échéance posée sur cette année: appliquez un barème de '
          'frais pour voir le recouvrement mois par mois.',
          style: textes.bodySmall?.copyWith(color: couleurs.onSurfaceVariant),
        ),
      );
    }

    final maximum = mois
        .map((m) => m.du > m.encaisse ? m.du : m.encaisse)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final decrochage = echeancier.premierDecrochage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          decrochage == null
              ? 'Chaque échéance de l\'année est soldée.'
              : 'Le recouvrement décroche depuis ${decrochage.libelle} : '
                    '${montantEnFrancs(decrochage.manque)} manquants sur ce '
                    'mois-là.',
          style: textes.bodySmall?.copyWith(
            color: decrochage == null
                ? couleurs.onSurfaceVariant
                : couleurs.error,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        // Identité par la forme et non par la seule couleur: la part encaissée
        // est pleine, le dû est un contour.
        Row(
          children: [
            _Cle(rempli: true, texte: 'Encaissé'),
            const SizedBox(width: 14),
            _Cle(rempli: false, texte: 'Dû'),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 168,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final ligne in mois)
                Expanded(
                  child: _Colonne(
                    ligne: ligne,
                    maximum: maximum == 0 ? 1 : maximum,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Le tableau des valeurs, pour qui ne peut pas lire la hauteur d'une
        // barre — et pour vérifier un chiffre sans le survoler.
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(
              'Voir les chiffres',
              style: textes.labelLarge?.copyWith(
                color: couleurs.onSurfaceVariant,
              ),
            ),
            children: [
              for (final ligne in mois)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(ligne.libelle, style: textes.bodySmall),
                      ),
                      Expanded(
                        child: Text(
                          'dû ${montantEnFrancs(ligne.du)}',
                          style: textes.bodySmall?.copyWith(
                            color: couleurs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'encaissé ${montantEnFrancs(ligne.encaisse)}',
                          style: textes.bodySmall?.copyWith(
                            color: couleurs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (ligne.manque > 0)
                        Text(
                          '-${montantAbrege(ligne.manque)}',
                          style: textes.bodySmall?.copyWith(
                            color: couleurs.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Cle extends StatelessWidget {
  const _Cle({required this.rempli, required this.texte});

  final bool rempli;
  final String texte;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: rempli ? couleurs.primary : Colors.transparent,
            border: rempli
                ? null
                : Border.all(
                    color: couleurs.primary.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          texte,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: couleurs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Colonne extends StatelessWidget {
  const _Colonne({required this.ligne, required this.maximum});

  final MoisDEcheance ligne;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;

    // Des fractions et non des pixels: la hauteur restante après l'étiquette
    // de manque et le libellé du mois dépend de la police du système, donc un
    // budget calculé à la main débordait de deux pixels — et un débordement
    // fait échouer la page entière, pas seulement le graphique.
    final partDu = (ligne.du / maximum).clamp(0.0, 1.0);
    final partEncaisse = (ligne.encaisse / maximum).clamp(0.0, 1.0);

    return Tooltip(
      message:
          '${ligne.libelle}\n'
          'Dû ${montantEnFrancs(ligne.du)}\n'
          'Encaissé ${montantEnFrancs(ligne.encaisse)}'
          '${ligne.manque > 0 ? "\nManque ${montantEnFrancs(ligne.manque)}" : ""}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (ligne.manque > 0)
              Text(
                '-${montantAbrege(ligne.manque)}',
                style: textes.labelSmall?.copyWith(
                  color: couleurs.error,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              const SizedBox(height: 16),
            const SizedBox(height: 4),
            // La piste porte le dû, la part pleine l'encaissé: l'espace vide
            // au-dessus est exactement ce qui manque.
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  FractionallySizedBox(
                    heightFactor: partDu,
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: couleurs.primary.withValues(alpha: 0.16),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  FractionallySizedBox(
                    heightFactor: partEncaisse,
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: couleurs.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ligne.libelle,
              style: textes.labelSmall?.copyWith(
                color: couleurs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ],
        ),
      ),
    );
  }
}

/// Ce qui demande une décision, et l'écran qui la règle.
///
/// C'est ce qui sépare un tableau de bord d'un outil: chaque ligne mène là où
/// on agit, au lieu de laisser la direction chercher le module elle-même.
class _ATraiter extends StatelessWidget {
  const _ATraiter({
    required this.stats,
    required this.echeancier,
    required this.presence,
    required this.onOuvrirModule,
  });

  final DashboardStats stats;
  final Echeancier? echeancier;
  final PresenceParRole? presence;
  final void Function(String) onOuvrirModule;

  @override
  Widget build(BuildContext context) {
    // Le rendu vit dans `ATraiter`, partage par les sept tableaux de bord.
    // Ici ne reste que le **choix des lignes**, qui est propre a la direction:
    // « ce qui demande une decision » depend du role -- un surveillant voit des
    // feuilles d'appel, un comptable des charges a valider.
    return ATraiter(lignes: _lignes(), onOuvrirModule: onOuvrirModule);
  }

  /// Les noms des rôles, tels qu'une école les emploie.
  static const _nomDuRole = <String, String>{
    'teacher': 'enseignants',
    'student': 'élèves',
    'parent': 'parents',
    'director': 'comptes de direction',
    'censor': 'censeurs',
    'accountant': 'comptables',
    'supervisor': 'surveillants',
    'promoter': 'promoteurs',
  };

  List<ActionATraiter> _lignes() {
    final actions = <ActionATraiter>[];

    // En tête, parce que c'est le fait le plus important d'un déploiement qui
    // commence: les comptes existent, les identifiants ont été générés, et
    // personne n'ouvre l'application. Sur IFP-OBK, 74 enseignants sur 75 et
    // 608 élèves sur 610 ne s'y sont jamais connectés — et aucun écran ne le
    // disait.
    //
    // Question distincte de celle du bandeau: non pas « qui travaille
    // maintenant » mais « qui n'a jamais commencé », et c'est de loin la plus
    // urgente.
    final absents = presence?.leRoleLePlusAbsent;
    if (absents != null && absents.$2 > 0) {
      final libelle = _nomDuRole[absents.$1] ?? absents.$1;
      final total = presence?.comptesParRole[absents.$1];
      actions.add(
        ActionATraiter(
          titre:
              '${absents.$2} $libelle n’ont jamais ouvert l’application',
          detail: total == null
              ? 'Distribuez-leur leurs identifiants'
              : 'sur $total comptes créés',
          icone: Icons.no_accounts_outlined,
          module: 'users',
          urgent: true,
        ),
      );
    }

    if (stats.yearExpensesPendingCount > 0) {
      actions.add(
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
      );
    }

    if (stats.studentsUnpaid > 0) {
      actions.add(
        ActionATraiter(
          titre:
              '${stats.studentsUnpaid} '
              '${stats.studentsUnpaid == 1 ? "élève a" : "élèves ont"}'
              ' un reste à payer',
          detail: montantEnFrancs(stats.feesOutstanding),
          icone: Icons.receipt_long_outlined,
          module: 'finance',
        ),
      );
    }

    final decrochage = echeancier?.premierDecrochage;
    if (decrochage != null) {
      actions.add(
        ActionATraiter(
          titre: 'Le recouvrement décroche depuis ${decrochage.libelle}',
          detail: '${montantEnFrancs(decrochage.manque)} sur ce mois',
          icone: Icons.trending_down,
          module: 'finance',
          urgent: true,
        ),
      );
    }

    final bulletinsManquants = stats.bulletinsTotal - stats.bulletinsDelivered;
    if (bulletinsManquants > 0) {
      actions.add(
        ActionATraiter(
          titre:
              '$bulletinsManquants '
              '${bulletinsManquants == 1 ? "bulletin n’est pas remis" : "bulletins ne sont pas remis"}',
          detail: stats.bulletinsFailed > 0
              ? 'dont ${stats.bulletinsFailed} en échec d\'envoi'
              : 'sur ${stats.bulletinsTotal} préparés',
          icone: Icons.description_outlined,
          module: 'reports',
          urgent: stats.bulletinsFailed > 0,
        ),
      );
    }

    if (stats.stockBelowThreshold > 0) {
      actions.add(
        ActionATraiter(
          titre:
              '${stats.stockBelowThreshold} '
              '${stats.stockBelowThreshold == 1 ? "article est" : "articles sont"}'
              ' sous leur seuil',
          detail: 'sur ${stats.stockTotal} en magasin',
          icone: Icons.inventory_2_outlined,
          module: 'stock',
        ),
      );
    }

    if (stats.studentsUnassigned > 0) {
      actions.add(
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
      );
    }

    return actions;
  }
}

