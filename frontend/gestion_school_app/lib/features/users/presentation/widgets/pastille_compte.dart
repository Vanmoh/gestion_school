import 'package:flutter/material.dart';

import '../../domain/user_account.dart';

/// L'état d'un compte, lisible d'un coup d'œil.
///
/// La liste ne disait pas si un compte était encore ouvert: on ne pouvait
/// donc ni voir qui gardait un accès après son départ, ni repérer les
/// comptes créés puis jamais utilisés.
class PastilleCompte extends StatelessWidget {
  final UserAccount compte;

  const PastilleCompte({super.key, required this.compte});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Un compte coupé prime sur tout le reste: qu'il se soit connecté ou
    // non ne change rien, il n'entre plus.
    final (fond, encre, icone, libelle) = !compte.isActive
        ? (
            scheme.errorContainer,
            scheme.onErrorContainer,
            Icons.block_rounded,
            'Désactivé',
          )
        : compte.jamaisConnecte
        ? (
            scheme.tertiaryContainer,
            scheme.onTertiaryContainer,
            Icons.hourglass_empty_rounded,
            'Jamais connecté',
          )
        : (
            scheme.primaryContainer,
            scheme.onPrimaryContainer,
            Icons.check_circle_outline_rounded,
            'Actif',
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 13, color: encre),
          const SizedBox(width: 5),
          Text(
            libelle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: encre,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
