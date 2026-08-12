import 'package:flutter/material.dart';

import '../../domain/students_stats.dart';
import '../student_actions.dart';

/// En-tete de « Gestion des eleves »: ce que dit l'etablissement, et ce qu'on
/// peut y faire qui ne vise pas un eleve en particulier.
///
/// Extrait de la page conformement au Sprint 2 du roadmap. Ses entrees sont
/// explicites -- effectifs, libelles, rappels -- ce qui le rend affichable et
/// verifiable sans monter la page entiere ni ses trente controleurs.
class StudentsDashboardCard extends StatelessWidget {
  final StudentsStats stats;
  final String activeYearLabel;
  final int classCount;
  final String scopeLabel;
  final String refreshLabel;
  final bool isCompactLayout;

  /// Un enregistrement est en cours: tout est momentanement neutralise.
  final bool saving;

  /// Le profil connecte consulte sans modifier.
  final bool readOnly;

  final VoidCallback onRefresh;
  final VoidCallback onAddStudent;
  final VoidCallback onOpenByClass;
  final VoidCallback onOpenClassCards;

  const StudentsDashboardCard({
    super.key,
    required this.stats,
    required this.activeYearLabel,
    required this.classCount,
    required this.scopeLabel,
    required this.refreshLabel,
    required this.isCompactLayout,
    required this.saving,
    required this.readOnly,
    required this.onRefresh,
    required this.onAddStudent,
    required this.onOpenByClass,
    required this.onOpenClassCards,
  });

  static ButtonStyle compactActionStyle() {
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.75),
              scheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isCompactLayout ? 12 : 15),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: isCompactLayout ? 10 : 12,
            crossAxisAlignment: WrapCrossAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isCompactLayout ? 760 : 620,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(textTheme),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: _chips(context)),
                  ],
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isCompactLayout ? 760 : 1120,
                ),
                child: _buildActions(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleRow(TextTheme textTheme) {
    final titre = Text(
      'Tableau de bord élèves',
      style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    );
    final actualiser = FilledButton.tonalIcon(
      style: compactActionStyle(),
      onPressed: saving ? null : onRefresh,
      icon: const Icon(Icons.sync),
      label: const Text('Actualiser'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titre,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: actualiser),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titre),
            const SizedBox(width: 10),
            actualiser,
          ],
        );
      },
    );
  }

  List<Widget> _chips(BuildContext context) {
    return [
      _Chip(icon: Icons.calendar_month_outlined, label: 'Année: $activeYearLabel'),
      _Chip(icon: Icons.class_outlined, label: '$classCount classes'),
      _Chip(
        icon: Icons.analytics_outlined,
        // Tant que le serveur n'a pas repondu, mieux vaut le dire que
        // d'afficher des zeros qu'on lirait comme une ecole vide.
        label: stats.isEmpty
            ? 'Effectifs indisponibles'
            : '${stats.active} actifs · ${stats.archived} archivés · ${stats.newThisYear} nouveaux',
        maxWidth: 420,
      ),
      _Chip(icon: Icons.apartment_outlined, label: scopeLabel, maxWidth: 320),
      _Chip(icon: Icons.schedule_outlined, label: refreshLabel),
    ];
  }

  Widget _buildActions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Seule action pleine de la page: c'est celle qu'on vient chercher.
          // Les actions visant un eleve vivent dans sa palette, la ou on le
          // regarde.
          Tooltip(
            message: readOnly ? lectureSeuleMotif : 'Inscrire un nouvel élève',
            child: FilledButton.icon(
              style: compactActionStyle(),
              onPressed: (saving || readOnly) ? null : onAddStudent,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Ajouter élève'),
            ),
          ),
          const SizedBox(width: 10),
          MenuAnchor(
            builder: (context, controller, _) => IconButton(
              tooltip: 'Autres vues',
              onPressed: saving
                  ? null
                  : () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
              icon: const Icon(Icons.more_horiz),
            ),
            menuChildren: [
              MenuItemButton(
                onPressed: saving ? null : onOpenByClass,
                leadingIcon: const Icon(Icons.groups_2_outlined),
                child: const Text('Vue par classe'),
              ),
              MenuItemButton(
                onPressed: saving ? null : onOpenClassCards,
                leadingIcon: const Icon(Icons.badge_outlined),
                child: const Text('Cartes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final double maxWidth;

  const _Chip({
    required this.icon,
    required this.label,
    this.maxWidth = 220,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
