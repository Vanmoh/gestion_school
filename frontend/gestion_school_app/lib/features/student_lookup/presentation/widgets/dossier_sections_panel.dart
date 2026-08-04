import 'package:flutter/material.dart';

import '../../domain/student_dossier.dart';
import '../dossier_item_formatter.dart';
import 'dossier_identity_card.dart';

/// Colonne « CONSULTATION » : une ligne par rubrique, depliable.
///
/// Une rubrique interdite reste visible et porte son motif. La masquer ferait
/// lire « aucun incident » la ou il faut lire « vous n'y avez pas acces » —
/// une absence silencieuse est un contresens, pas une simplification.
class DossierSectionsPanel extends StatelessWidget {
  final List<DossierSection> sections;

  const DossierSectionsPanel({super.key, required this.sections});

  static const accesRefuse = 'Accès non autorisé';
  static const aucunElement = 'Aucun élément';

  @override
  Widget build(BuildContext context) {
    return DossierPanel(
      title: 'CONSULTATION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SectionRow(section: section),
            ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final DossierSection section;

  const _SectionRow({required this.section});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (!section.granted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                section.label,
                style: textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              DossierSectionsPanel.accesRefuse,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  section.label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _CountBadge(count: section.count),
            ],
          ),
          subtitle: _summaryLine(section) == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _summaryLine(section)!,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
          children: [
            if (section.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  DossierSectionsPanel.aucunElement,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else ...[
              for (final item in section.items)
                _ItemLine(line: formatDossierItem(section.key, item)),
              if (section.hasMore)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    // Le total reste juste meme quand la liste est tronquee.
                    'Les ${section.items.length} plus récents sur '
                    '${section.count}. Voir le module dédié pour la suite.',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Chiffres cles de la rubrique, calcules sur sa totalite.
  static String? _summaryLine(DossierSection section) {
    if (section.summary.isEmpty) return null;

    final parts = <String>[];
    section.summary.forEach((key, value) {
      if (value == null) return;
      final texte = value.toString();
      if (texte.isEmpty || texte == 'null' || texte == '0') return;
      parts.add('${_summaryLabel(key)} : ${_summaryValue(key, texte)}');
    });

    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  static const _cellulesMonetaires = {'total_du', 'total_encaisse'};

  static String _summaryLabel(String key) {
    const libelles = {
      'moyenne': 'Moyenne',
      'absences': 'Absences',
      'retards': 'Retards',
      'ouverts': 'Incidents ouverts',
      'total_du': 'Total dû',
      'total_encaisse': 'Encaissé',
      'en_cours': 'Emprunts en cours',
      'impayes': 'Repas impayés',
    };
    return libelles[key] ?? key;
  }

  static String _summaryValue(String key, String raw) {
    final parsed = double.tryParse(raw);
    if (parsed == null) return raw;
    if (_cellulesMonetaires.contains(key)) return formatDossierMoney(parsed);
    if (parsed == parsed.roundToDouble()) return parsed.toStringAsFixed(0);
    return parsed.toStringAsFixed(2);
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: count == 0
            ? scheme.surfaceContainerHigh
            : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: count == 0 ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  final DossierLine line;

  const _ItemLine({required this.line});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.title.isEmpty ? '—' : line.title,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (line.subtitle.isNotEmpty)
                  Text(
                    line.subtitle,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (line.trailing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                line.trailing,
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
