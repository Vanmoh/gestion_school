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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/montant.dart';
import '../../../core/providers/navigation_intents.dart';
import '../domain/dashboard_stats.dart';
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

    return RefreshIndicator(
      onRefresh: _actualiser,
      child: compteurs.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (erreur, _) => _Panne(erreur: erreur, onReessayer: _actualiser),
        data: (stats) => _Contenu(
          stats: stats,
          echeancier: echeancier,
          onActualiser: _actualiser,
          onOuvrirModule: _ouvrirModule,
        ),
      ),
    );
  }
}

/// Une panne se dit, au lieu de laisser la page muette.
class _Panne extends StatelessWidget {
  const _Panne({required this.erreur, required this.onReessayer});

  final Object erreur;
  final Future<void> Function() onReessayer;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, color: couleurs.error),
                    const SizedBox(width: 10),
                    Text(
                      'Erreur de chargement',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Les compteurs ne sont pas arrivés. $erreur',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onReessayer,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.stats,
    required this.echeancier,
    required this.onActualiser,
    required this.onOuvrirModule,
  });

  final DashboardStats stats;
  final AsyncValue<Echeancier> echeancier;
  final Future<void> Function() onActualiser;
  final void Function(String) onOuvrirModule;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _EnTete(stats: stats, onActualiser: onActualiser),
        const SizedBox(height: 24),
        _QuatreChiffres(stats: stats),
        const SizedBox(height: 20),
        _PanneauEcheancier(echeancier: echeancier),
        const SizedBox(height: 20),
        _ATraiter(
          stats: stats,
          echeancier: echeancier.valueOrNull,
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
class _EnTete extends StatelessWidget {
  const _EnTete({required this.stats, required this.onActualiser});

  final DashboardStats stats;
  final Future<void> Function() onActualiser;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;
    final annee = stats.academicYearName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stats.activeEtablissementName?.trim().isNotEmpty == true
                    ? stats.activeEtablissementName!
                    : 'Tableau de bord',
                style: textes.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (annee != null && annee.isNotEmpty)
                    _Etiquette(
                      texte: 'Année $annee',
                      icone: Icons.event_outlined,
                      accentuee: true,
                    )
                  else
                    const _Etiquette(
                      texte: 'Aucune année active',
                      icone: Icons.event_busy_outlined,
                    ),
                  if (stats.academicYearClosed)
                    const _Etiquette(
                      texte: 'Année clôturée',
                      icone: Icons.lock_outline,
                    ),
                  if (stats.academicYearStart != null &&
                      stats.academicYearEnd != null)
                    Text(
                      'du ${_jour(stats.academicYearStart!)} '
                      'au ${_jour(stats.academicYearEnd!)}',
                      style: textes.bodySmall?.copyWith(
                        color: couleurs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: onActualiser,
          icon: const Icon(Icons.refresh),
          tooltip: 'Actualiser',
        ),
      ],
    );
  }

  /// « 2025-09-01 » devient « 01/09/2025 ».
  static String _jour(String iso) {
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    final jour = parts[2].split('T').first;
    return '$jour/${parts[1]}/${parts[0]}';
  }
}

class _Etiquette extends StatelessWidget {
  const _Etiquette({
    required this.texte,
    required this.icone,
    this.accentuee = false,
  });

  final String texte;
  final IconData icone;
  final bool accentuee;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final fond = accentuee
        ? couleurs.primary.withValues(alpha: 0.12)
        : couleurs.surfaceContainerHighest;
    final encre = accentuee ? couleurs.primary : couleurs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: encre),
          const SizedBox(width: 6),
          Text(
            texte,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: encre,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quatre chiffres, et une phrase par chiffre.
///
/// Quatre et non neuf: au-delà, on ne lit plus, on balaie. Et une phrase
/// plutôt qu'un pourcentage nu, parce qu'un nombre sans son sens oblige
/// chacun à l'interpréter — souvent de travers.
class _QuatreChiffres extends StatelessWidget {
  const _QuatreChiffres({required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final cartes = <Widget>[
      _CarteChiffre(
        libelle: 'Effectif de l\'année',
        valeur: '${stats.students}',
        unite: stats.students == 1 ? 'élève' : 'élèves',
        phrase:
            '${stats.classrooms} ${stats.classrooms == 1 ? "classe" : "classes"}'
            ' · ${stats.teachers} '
            '${stats.teachers == 1 ? "enseignant" : "enseignants"}',
        icone: Icons.groups_outlined,
      ),
      _CarteChiffre(
        libelle: 'Recouvrement',
        valeur: _taux(stats.collectionRate),
        phrase: stats.feesOutstanding > 0
            ? '${montantEnFrancs(stats.feesOutstanding)} restent à encaisser'
            : 'Tout l\'échéancier est soldé',
        icone: Icons.savings_outlined,
        jauge: stats.feesDue > 0 ? stats.collectionRate / 100 : null,
      ),
      _CarteChiffre(
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
      _CarteChiffre(
        libelle: 'Absences du mois',
        valeur: '${stats.monthlyAbsences}',
        phrase: stats.phraseDesAbsences,
        icone: Icons.event_busy_outlined,
      ),
    ];

    return LayoutBuilder(
      builder: (context, contraintes) {
        // Quatre de front sur un bureau, deux sur une tablette, une seule sur
        // un téléphone. Le seuil vient de la largeur qu'un montant en francs
        // demande sans se couper: « 5 040 000 FCFA » ne tient pas sous 240 px.
        final parLigne = contraintes.maxWidth >= 1000
            ? 4
            : contraintes.maxWidth >= 620
            ? 2
            : 1;
        const ecart = 14.0;
        final largeur =
            (contraintes.maxWidth - ecart * (parLigne - 1)) / parLigne;

        return Wrap(
          spacing: ecart,
          runSpacing: ecart,
          children: [
            for (final carte in cartes)
              SizedBox(width: largeur, child: carte),
          ],
        );
      },
    );
  }

  static String _taux(double valeur) {
    final arrondi = valeur.toStringAsFixed(1).replaceAll('.', ',');
    return '$arrondi %';
  }
}

class _CarteChiffre extends StatelessWidget {
  const _CarteChiffre({
    required this.libelle,
    required this.valeur,
    required this.phrase,
    required this.icone,
    this.unite,
    this.jauge,
    this.alerte = false,
  });

  final String libelle;
  final String valeur;
  final String? unite;
  final String phrase;
  final IconData icone;

  /// La part réalisée, entre 0 et 1, quand le chiffre est un ratio.
  ///
  /// Une jauge sur piste de même teinte, et non un camembert de deux parts:
  /// « 93 % d'un total » se lit d'un coup sur une barre, et la part manquante
  /// occupe visuellement la place qu'elle représente.
  final double? jauge;

  final bool alerte;

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
            Row(
              children: [
                Icon(icone, size: 18, color: couleurs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    libelle,
                    style: textes.labelLarge?.copyWith(
                      color: couleurs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  valeur,
                  style: textes.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                if (unite != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    unite!,
                    style: textes.bodyMedium?.copyWith(
                      color: couleurs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (jauge != null) ...[
              const SizedBox(height: 12),
              _Jauge(part: jauge!),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (alerte) ...[
                  Icon(
                    Icons.pending_actions_outlined,
                    size: 15,
                    color: couleurs.error,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    phrase,
                    style: textes.bodySmall?.copyWith(
                      color: alerte ? couleurs.error : couleurs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La part réalisée, sur une piste de la même teinte.
class _Jauge extends StatelessWidget {
  const _Jauge({required this.part});

  final double part;

  @override
  Widget build(BuildContext context) {
    final couleurs = Theme.of(context).colorScheme;
    final borne = part.clamp(0.0, 1.0);

    return Semantics(
      label: 'Réalisé ${(borne * 100).round()} pour cent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: borne,
          minHeight: 8,
          backgroundColor: couleurs.primary.withValues(alpha: 0.16),
          valueColor: AlwaysStoppedAnimation(couleurs.primary),
        ),
      ),
    );
  }
}

/// Une seule courbe: ce qui était dû chaque mois, et ce qui est rentré.
///
/// Une seule, parce que l'écran en portait quatre — un radar, des barres, un
/// anneau, des sparklines — et qu'aucune ne disait quoi faire.
///
/// Le mois vient de l'échéance du barème et non de l'heure de saisie du
/// paiement: `Payment` ne porte aucune date de paiement, donc un reçu écrit le
/// 30 et saisi le 2 tombait dans le mois suivant, et un import en masse faisait
/// tenir une année dans un seul mois.
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
    required this.onOuvrirModule,
  });

  final DashboardStats stats;
  final Echeancier? echeancier;
  final void Function(String) onOuvrirModule;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;
    final lignes = _lignes();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'À traiter',
              style: textes.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (lignes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: couleurs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rien n\'attend de décision.',
                        style: textes.bodyMedium?.copyWith(
                          color: couleurs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final ligne in lignes)
                _LigneAction(
                  ligne: ligne,
                  onOuvrir: () => onOuvrirModule(ligne.module),
                ),
          ],
        ),
      ),
    );
  }

  List<_Action> _lignes() {
    final actions = <_Action>[];

    if (stats.yearExpensesPendingCount > 0) {
      actions.add(
        _Action(
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
        _Action(
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
        _Action(
          titre: 'Le recouvrement décroche depuis ${decrochage.libelle}',
          detail: '${montantEnFrancs(decrochage.manque)} sur ce mois',
          icone: Icons.trending_down,
          module: 'finance',
          urgent: true,
        ),
      );
    }

    if (stats.studentsUnassigned > 0) {
      actions.add(
        _Action(
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

class _Action {
  const _Action({
    required this.titre,
    required this.detail,
    required this.icone,
    required this.module,
    this.urgent = false,
  });

  final String titre;
  final String detail;
  final IconData icone;
  final String module;
  final bool urgent;
}

class _LigneAction extends StatelessWidget {
  const _LigneAction({required this.ligne, required this.onOuvrir});

  final _Action ligne;
  final VoidCallback onOuvrir;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final couleurs = Theme.of(context).colorScheme;
    final encre = ligne.urgent ? couleurs.error : couleurs.onSurfaceVariant;

    return InkWell(
      onTap: onOuvrir,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        // 48 px de haut au minimum: une ligne cliquable doit pouvoir être
        // touchée au doigt.
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(ligne.icone, size: 19, color: encre),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ligne.titre,
                    style: textes.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ligne.detail,
                    style: textes.bodySmall?.copyWith(
                      color: couleurs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: couleurs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
