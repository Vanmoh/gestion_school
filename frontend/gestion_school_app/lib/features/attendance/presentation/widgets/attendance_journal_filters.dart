import 'package:flutter/material.dart';

/// De quoi retrouver une fiche precise dans le journal.
///
/// Le serveur savait deja filtrer par classe et par periode, mais aucun de ces
/// filtres n'etait offert a l'ecran: en fevrier, retrouver la fiche de mardi
/// demandait de faire defiler des centaines de lignes. Le serveur plafonne en
/// plus sa reponse, si bien que les fiches les plus anciennes finissaient hors
/// de portee.
class AttendanceJournalFilters extends StatelessWidget {
  /// Les classes proposees au filtre, telles que rendues par l'API
  /// (`id`, `name`).
  final List<Map<String, dynamic>> classes;

  final int? classeSelectionnee;
  final DateTime? du;
  final DateTime? au;

  /// Nombre de fiches actuellement affichees.
  final int nombreFiches;

  /// Vrai quand le serveur a coupe la liste: le dire evite de conclure a
  /// l'absence d'une fiche qui existe pourtant.
  final bool listeTronquee;

  final bool actif;

  final ValueChanged<int?> onClasseChangee;
  final ValueChanged<DateTime?> onDuChange;
  final ValueChanged<DateTime?> onAuChange;
  final VoidCallback onReinitialiser;

  const AttendanceJournalFilters({
    super.key,
    required this.classes,
    required this.classeSelectionnee,
    required this.du,
    required this.au,
    required this.nombreFiches,
    required this.listeTronquee,
    required this.actif,
    required this.onClasseChangee,
    required this.onDuChange,
    required this.onAuChange,
    required this.onReinitialiser,
  });

  bool get _filtre =>
      classeSelectionnee != null || du != null || au != null;

  static String _jourLisible(DateTime date) {
    final jour = date.day.toString().padLeft(2, '0');
    final mois = date.month.toString().padLeft(2, '0');
    return '$jour/$mois/${date.year}';
  }

  Future<void> _choisirDate(
    BuildContext context,
    DateTime? valeur,
    ValueChanged<DateTime?> onChange,
  ) async {
    final choisi = await showDatePicker(
      context: context,
      initialDate: valeur ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (choisi != null) {
      onChange(choisi);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<int?>(
                initialValue: classeSelectionnee,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Classe',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Toutes les classes'),
                  ),
                  for (final classe in classes)
                    DropdownMenuItem<int?>(
                      value: _entier(classe['id']),
                      child: Text(
                        (classe['name'] ?? '-').toString(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: actif ? onClasseChangee : null,
              ),
            ),
            _BoutonDate(
              etiquette: 'Du',
              valeur: du,
              actif: actif,
              onChoisir: () => _choisirDate(context, du, onDuChange),
              onEffacer: du == null ? null : () => onDuChange(null),
            ),
            _BoutonDate(
              etiquette: 'Au',
              valeur: au,
              actif: actif,
              onChoisir: () => _choisirDate(context, au, onAuChange),
              onEffacer: au == null ? null : () => onAuChange(null),
            ),
            if (_filtre)
              TextButton.icon(
                onPressed: actif ? onReinitialiser : null,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Réinitialiser'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          nombreFiches == 0
              ? 'Aucune fiche'
              : '$nombreFiches fiche${nombreFiches > 1 ? 's' : ''}'
                    '${_filtre ? ' (filtrées)' : ''}',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (listeTronquee) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: scheme.tertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Liste tronquée par le serveur : affinez la classe ou la '
                  'période pour voir les fiches plus anciennes.',
                  style: textTheme.bodySmall?.copyWith(color: scheme.tertiary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static int _entier(dynamic valeur) {
    if (valeur is int) return valeur;
    return int.tryParse(valeur?.toString() ?? '') ?? 0;
  }
}

class _BoutonDate extends StatelessWidget {
  final String etiquette;
  final DateTime? valeur;
  final bool actif;
  final VoidCallback onChoisir;

  /// Absent tant qu'aucune date n'est posee: proposer d'effacer le vide
  /// n'aurait rien a effacer.
  final VoidCallback? onEffacer;

  const _BoutonDate({
    required this.etiquette,
    required this.valeur,
    required this.actif,
    required this.onChoisir,
    this.onEffacer,
  });

  @override
  Widget build(BuildContext context) {
    final libelle = valeur == null
        ? etiquette
        : '$etiquette ${AttendanceJournalFilters._jourLisible(valeur!)}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: actif ? onChoisir : null,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text(libelle),
        ),
        if (onEffacer != null)
          IconButton(
            tooltip: 'Effacer $etiquette',
            visualDensity: VisualDensity.compact,
            onPressed: actif ? onEffacer : null,
            icon: const Icon(Icons.close, size: 16),
          ),
      ],
    );
  }
}
