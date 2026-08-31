import 'package:flutter/material.dart';

import '../../domain/user_account.dart';

/// L'état d'un compte, lisible d'un coup d'œil.
///
/// La liste ne disait pas si un compte était encore ouvert: on ne pouvait
/// donc ni voir qui gardait un accès après son départ, ni repérer les
/// comptes créés puis jamais utilisés.
class PastilleCompte extends StatelessWidget {
  /// Le meme vert que la messagerie: « en ligne » se reconnait d'un ecran a
  /// l'autre sans avoir a lire.
  static const couleurEnLigne = Color(0xFF12B76A);

  final UserAccount compte;

  const PastilleCompte({super.key, required this.compte});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Un compte coupé prime sur tout le reste: qu'il se soit connecté ou
    // non ne change rien, il n'entre plus.
    //
    // Vient ensuite qui est là maintenant. « Actif » ne disait que l'état
    // administratif du compte, jamais si son titulaire était joignable: on
    // ouvrait la messagerie pour le savoir.
    final (fond, encre, icone, libelle) = !compte.isActive
        ? (
            scheme.errorContainer,
            scheme.onErrorContainer,
            Icons.block_rounded,
            'Désactivé',
          )
        : compte.enLigne
        ? (
            couleurEnLigne.withValues(alpha: 0.18),
            couleurEnLigne,
            Icons.circle,
            'En ligne',
          )
        : compte.jamaisConnecte
        ? (
            scheme.tertiaryContainer,
            scheme.onTertiaryContainer,
            Icons.hourglass_empty_rounded,
            'Jamais connecté',
          )
        : (
            scheme.surfaceContainerHighest,
            scheme.onSurfaceVariant,
            Icons.schedule_rounded,
            // En bout de ligne de liste, la place est comptee: « Il y a 3
            // jours » y tient, l'horodatage complet non. Il reste a portee de
            // survol, et en toutes lettres sur la fiche.
            compte.derniereActivite,
          );

    return Tooltip(
      message: compte.isActive
          ? compte.etatDeConnexion
          : 'Compte désactivé — ${compte.etatDeConnexion}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: fond,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icone,
              size: compte.isActive && compte.enLigne ? 9 : 13,
              color: encre,
            ),
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
      ),
    );
  }
}
