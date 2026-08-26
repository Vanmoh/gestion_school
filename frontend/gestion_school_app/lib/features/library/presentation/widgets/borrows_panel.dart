import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// Le suivi des prets: en cours, rendus, en retard.
///
/// Aucun retour n'etait possible auparavant -- `returned_at` n'etait ecrit
/// nulle part et un pret durait indefiniment. Le bouton « Rendre » est donc
/// la premiere action de cette liste, et le retard s'y lit sans calcul.
class BorrowsPanel extends StatelessWidget {
  final List<Borrow> emprunts;

  /// « », « ongoing », « returned » ou « late ».
  final String filtre;
  final ValueChanged<String> onFiltreChanged;

  /// Nuls pour un profil en lecture: l'eleve consulte ses prets, il ne les
  /// solde pas lui-meme.
  final void Function(Borrow emprunt)? onRendre;
  final void Function(Borrow emprunt)? onSupprimer;

  /// Vrai pour l'ecran « Mes emprunts »: le nom de l'emprunteur y serait
  /// une redite, c'est toujours le sien.
  final bool masquerEmprunteur;

  const BorrowsPanel({
    super.key,
    required this.emprunts,
    required this.filtre,
    required this.onFiltreChanged,
    this.onRendre,
    this.onSupprimer,
    this.masquerEmprunteur = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final option in const [
              ('', 'Tous'),
              ('ongoing', 'En cours'),
              ('late', 'En retard'),
              ('returned', 'Rendus'),
            ])
              ChoiceChip(
                label: Text(option.$2),
                selected: filtre == option.$1,
                onSelected: (_) => onFiltreChanged(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (emprunts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('Aucun emprunt à afficher.'),
          )
        else
          for (final emprunt in emprunts) _ligne(context, emprunt),
      ],
    );
  }

  Widget _ligne(BuildContext context, Borrow emprunt) {
    final scheme = Theme.of(context).colorScheme;
    final details = <String>[
      if (!masquerEmprunteur && emprunt.studentMatricule.isNotEmpty)
        '${emprunt.studentMatricule} • ${emprunt.studentFullName}',
      '${_jour(emprunt.borrowedAt)} → ${_jour(emprunt.dueDate)}',
      if (emprunt.isReturned) 'rendu le ${_jour(emprunt.returnedAt)}',
      if (emprunt.isReturned && emprunt.penaltyAmount > 0)
        'pénalité ${_montant(emprunt.penaltyAmount)}',
      if (emprunt.estEnRetard)
        '${emprunt.daysLate} jour(s) de retard'
            '${emprunt.penaltyDue > 0 ? ' • ${_montant(emprunt.penaltyDue)} dus' : ''}',
    ];

    return Card(
      child: ListTile(
        leading: Icon(
          emprunt.isReturned
              ? Icons.assignment_turned_in_outlined
              : Icons.assignment_outlined,
          color: emprunt.estEnRetard
              ? scheme.error
              : (emprunt.isReturned ? scheme.outline : scheme.primary),
        ),
        title: Text(emprunt.bookTitle),
        subtitle: Text(details.join('\n')),
        isThreeLine: details.length > 2,
        trailing: _actions(context, emprunt),
      ),
    );
  }

  Widget? _actions(BuildContext context, Borrow emprunt) {
    final boutons = <Widget>[
      if (!emprunt.isReturned && onRendre != null)
        FilledButton.tonal(
          onPressed: () => onRendre!(emprunt),
          child: const Text('Rendre'),
        ),
      if (onSupprimer != null)
        IconButton(
          tooltip: 'Supprimer l’emprunt',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => onSupprimer!(emprunt),
        ),
    ];
    if (boutons.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: boutons);
  }

  String _jour(DateTime? valeur) {
    if (valeur == null) return '—';
    final mois = valeur.month.toString().padLeft(2, '0');
    final jour = valeur.day.toString().padLeft(2, '0');
    return '$jour/$mois/${valeur.year}';
  }

  String _montant(double valeur) {
    return valeur == valeur.roundToDouble()
        ? '${valeur.round()} F'
        : '${valeur.toStringAsFixed(2)} F';
  }
}
