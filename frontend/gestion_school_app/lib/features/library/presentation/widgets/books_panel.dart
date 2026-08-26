import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// Le catalogue papier: chercher, filtrer, corriger une fiche.
///
/// Le fonds s'affichait entier et trie par titre, sans recherche: trouver
/// un ouvrage dans plusieurs centaines de lignes revenait a faire defiler.
class BooksPanel extends StatelessWidget {
  final List<Book> livres;
  final String recherche;

  /// « », « available » ou « out ».
  final String filtreDisponibilite;

  final ValueChanged<String> onRechercheChanged;
  final ValueChanged<String> onFiltreChanged;

  /// Nuls quand le profil ne peut pas ecrire: l'ecran n'affiche alors aucune
  /// action plutot que des boutons qui rendraient un refus.
  final void Function(Book livre)? onModifier;
  final void Function(Book livre)? onSupprimer;

  const BooksPanel({
    super.key,
    required this.livres,
    required this.recherche,
    required this.filtreDisponibilite,
    required this.onRechercheChanged,
    required this.onFiltreChanged,
    this.onModifier,
    this.onSupprimer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('books-search'),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search),
            hintText: 'Titre, auteur ou ISBN',
            border: OutlineInputBorder(),
          ),
          onSubmitted: onRechercheChanged,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final filtre in const [
              ('', 'Tous'),
              ('available', 'Disponibles'),
              ('out', 'Tous sortis'),
            ])
              ChoiceChip(
                label: Text(filtre.$2),
                selected: filtreDisponibilite == filtre.$1,
                onSelected: (_) => onFiltreChanged(filtre.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (livres.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              recherche.isEmpty && filtreDisponibilite.isEmpty
                  ? 'Aucun ouvrage enregistré.'
                  : 'Aucun ouvrage ne correspond.',
            ),
          )
        else
          for (final livre in livres)
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.menu_book_outlined,
                  color: livre.estDisponible ? scheme.primary : scheme.outline,
                ),
                title: Text(livre.title),
                subtitle: Text(
                  [
                    '${livre.author} • ISBN ${livre.isbn}',
                    if (livre.complements.isNotEmpty) livre.complements,
                    if (livre.quantityBorrowed > 0)
                      '${livre.quantityBorrowed} exemplaire(s) emprunté(s)',
                  ].join('\n'),
                ),
                isThreeLine:
                    livre.quantityBorrowed > 0 || livre.complements.isNotEmpty,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _pastilleDisponibilite(context, livre),
                    if (onModifier != null || onSupprimer != null)
                      PopupMenuButton<String>(
                        tooltip: 'Actions',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (action) {
                          if (action == 'modifier') onModifier?.call(livre);
                          if (action == 'supprimer') onSupprimer?.call(livre);
                        },
                        itemBuilder: (_) => [
                          if (onModifier != null)
                            const PopupMenuItem(
                              value: 'modifier',
                              child: Text('Modifier'),
                            ),
                          if (onSupprimer != null)
                            const PopupMenuItem(
                              value: 'supprimer',
                              child: Text('Supprimer'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  /// « 2/5 » : ce qui reste en rayon sur le fonds total.
  Widget _pastilleDisponibilite(BuildContext context, Book livre) {
    final scheme = Theme.of(context).colorScheme;
    final epuise = !livre.estDisponible;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: epuise
            ? scheme.errorContainer
            : scheme.primaryContainer.withValues(alpha: 0.6),
      ),
      child: Text(
        '${livre.quantityAvailable}/${livre.quantityTotal}',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: epuise ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
