import 'package:flutter/material.dart';

import '../../domain/user_account.dart';

/// Ce qu'une suppression de compte emporte avec elle.
///
/// `Student.user` et `Teacher.user` sont en CASCADE: supprimer le compte
/// d'un enseignant efface sa fiche, ses affectations, ses créneaux d'emploi
/// du temps et ses pointages. Rien ne le disait avant de le faire.
///
/// L'inventaire vient du serveur — lui seul sait ce qui pend au compte — et
/// la désactivation reste proposée en premier, parce qu'elle retire l'accès
/// sans rien détruire.
class DialogueSuppression extends StatelessWidget {
  final UserAccount compte;

  /// Ce que le serveur a répondu: « fiche enseignant » → 1, « pointages » → 12.
  /// Vide quand le compte ne porte rien.
  final Map<String, int> donneesLiees;

  const DialogueSuppression({
    super.key,
    required this.compte,
    required this.donneesLiees,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final porteDesDonnees = donneesLiees.isNotEmpty;

    return AlertDialog(
      title: Text(
        porteDesDonnees ? 'Suppression définitive' : 'Supprimer le compte',
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${compte.fullName} (${compte.username})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (porteDesDonnees) ...[
              Text(
                'Ces données seront définitivement supprimées avec le compte :',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entree in donneesLiees.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_forever_outlined,
                              size: 15,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${entree.value} ${entree.key}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // La sortie preferable, proposee avant l'irreversible.
              Text(
                'Désactiver le compte retire l’accès sans rien détruire. '
                'C’est ce qu’il faut faire pour un départ.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Text(
                'Ce compte ne porte aucune donnée liée. Sa suppression est '
                'sans effet sur le reste de l’application.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        if (porteDesDonnees)
          TextButton(
            key: const Key('desactiver-plutot'),
            onPressed: () => Navigator.of(context).pop(ChoixSuppression.desactiver),
            child: const Text('Désactiver plutôt'),
          ),
        FilledButton(
          key: const Key('confirmer-suppression'),
          style: porteDesDonnees
              ? FilledButton.styleFrom(backgroundColor: scheme.error)
              : null,
          onPressed: () => Navigator.of(context).pop(ChoixSuppression.supprimer),
          child: Text(porteDesDonnees ? 'Supprimer quand même' : 'Supprimer'),
        ),
      ],
    );
  }
}

/// Ce que l'administration décide devant l'inventaire.
enum ChoixSuppression { supprimer, desactiver }
