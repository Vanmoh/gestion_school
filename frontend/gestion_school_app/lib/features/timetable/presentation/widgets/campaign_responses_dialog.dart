import 'package:flutter/material.dart';

import '../../domain/availability.dart';

/// Qui a répondu, qui manque à l'appel.
///
/// La liste des seuls répondants ne dirait rien: c'est celle des manquants
/// qui sert à relancer, et elle n'existe qu'en partant de l'effectif complet.
/// Les manquants arrivent donc en tête.
class CampaignResponsesDialog extends StatelessWidget {
  final String titre;
  final List<AvailabilityResponseRow> reponses;
  final VoidCallback? onRelancer;

  const CampaignResponsesDialog({
    super.key,
    required this.titre,
    required this.reponses,
    this.onRelancer,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manquants = reponses.where((ligne) => !ligne.isSubmitted).toList();
    final rendus = reponses.where((ligne) => ligne.isSubmitted).toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titre, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '${rendus.length} rendu${rendus.length > 1 ? 's' : ''} · '
                          '${manquants.length} en attente',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (onRelancer != null && manquants.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: onRelancer,
                      icon: const Icon(Icons.notifications_active_outlined, size: 18),
                      label: const Text('Relancer'),
                    ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: reponses.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: Text('Aucun enseignant dans cet établissement.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final ligne in [...manquants, ...rendus])
                          ListTile(
                            dense: true,
                            leading: Icon(
                              ligne.isSubmitted
                                  ? Icons.check_circle_outline
                                  : Icons.schedule_outlined,
                              color: ligne.isSubmitted ? scheme.primary : scheme.error,
                            ),
                            title: Text(ligne.name),
                            subtitle: Text(
                              [
                                if (ligne.employeeCode.isNotEmpty) ligne.employeeCode,
                                '${ligne.slotsDeclared} créneau'
                                    '${ligne.slotsDeclared > 1 ? 'x' : ''} déclaré'
                                    '${ligne.slotsDeclared > 1 ? 's' : ''}',
                                if (!ligne.isSubmitted && ligne.reminderCount > 0)
                                  'relancé ${ligne.reminderCount} fois',
                              ].join('  ·  '),
                            ),
                            trailing: Text(
                              ligne.isSubmitted ? 'Rendu' : 'En attente',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: ligne.isSubmitted ? scheme.primary : scheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
