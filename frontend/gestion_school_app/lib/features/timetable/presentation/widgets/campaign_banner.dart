import 'package:flutter/material.dart';

import '../../domain/availability.dart';

/// L'état de la collecte, en tête de l'écran.
///
/// La collecte n'avait ni début, ni fin, ni compte de répondants: personne
/// ne savait si elle était encore ouverte, ni qui manquait à l'appel. Ce
/// bandeau répond aux deux questions, différemment selon qui regarde.
class CampaignBanner extends StatelessWidget {
  final AvailabilityCampaign? campagne;

  /// Vrai côté enseignant: il voit sa propre échéance, pas le taux de réponse
  /// de ses collègues.
  final bool vueEnseignant;

  /// Vrai quand l'enseignant a déjà rendu ses disponibilités.
  final bool dejaRendu;

  final VoidCallback? onRendre;
  final VoidCallback? onRelancer;
  final VoidCallback? onVoirLesReponses;

  const CampaignBanner({
    super.key,
    required this.campagne,
    required this.vueEnseignant,
    this.dejaRendu = false,
    this.onRendre,
    this.onRelancer,
    this.onVoirLesReponses,
  });

  @override
  Widget build(BuildContext context) {
    final active = campagne;
    final scheme = Theme.of(context).colorScheme;

    if (active == null) {
      return _cadre(
        context,
        teinte: scheme.outlineVariant,
        enfants: [
          Text(
            'Aucune campagne de collecte',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            'Les disponibilités déclarées restent enregistrées, mais sans '
            'échéance ni suivi des réponses.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    final restants = active.joursRestants;
    final teinte = active.isOpen ? scheme.primary : scheme.outline;

    return _cadre(
      context,
      teinte: teinte,
      enfants: [
        Row(
          children: [
            Expanded(
              child: Text(
                active.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _pastilleStatut(context, active),
          ],
        ),
        Text(
          [
            if (active.academicYearName.isNotEmpty) active.academicYearName,
            if (active.opensOn != null && active.closesOn != null)
              'du ${_jour(active.opensOn!)} au ${_jour(active.closesOn!)}',
            if (active.isOpen && restants != null)
              restants <= 0
                  ? 'dernier jour'
                  : 'encore $restants jour${restants > 1 ? 's' : ''}',
          ].join('  ·  '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (active.instructions.isNotEmpty)
          Text(
            active.instructions,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        const SizedBox(height: 4),
        if (vueEnseignant)
          _actionsEnseignant(context, active)
        else
          _actionsAdministration(context, active),
      ],
    );
  }

  Widget _actionsEnseignant(BuildContext context, AvailabilityCampaign active) {
    final scheme = Theme.of(context).colorScheme;
    if (dejaRendu) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, size: 17, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Vos disponibilités ont été transmises. Vous pouvez encore les '
              'modifier tant que la collecte est ouverte.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: active.isOpen ? onRendre : null,
        icon: const Icon(Icons.send_outlined, size: 18),
        label: const Text('J’ai terminé mes disponibilités'),
      ),
    );
  }

  Widget _actionsAdministration(
    BuildContext context,
    AvailabilityCampaign active,
  ) {
    final taux = active.tauxReponse;
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 190,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${active.teachersAnswered} / ${active.teachersTotal} enseignants '
                'ont répondu',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: taux ?? 0,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
        if (active.teachersMissing > 0)
          OutlinedButton.icon(
            onPressed: active.isOpen ? onRelancer : null,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text('Relancer ${active.teachersMissing} manquant'
                '${active.teachersMissing > 1 ? 's' : ''}'),
          ),
        TextButton.icon(
          onPressed: onVoirLesReponses,
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('Suivi des réponses'),
        ),
      ],
    );
  }

  Widget _pastilleStatut(BuildContext context, AvailabilityCampaign active) {
    final scheme = Theme.of(context).colorScheme;
    final ouverte = active.isOpen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: ouverte
            ? scheme.primaryContainer.withValues(alpha: 0.7)
            : scheme.surfaceContainerHighest,
      ),
      child: Text(
        ouverte ? 'Collecte ouverte' : active.statusLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: ouverte ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _cadre(
    BuildContext context, {
    required Color teinte,
    required List<Widget> enfants,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // La bande de couleur est un enfant, pas un cote de la bordure: Flutter
    // refuse de peindre un `Border` aux cotes de couleurs differentes des
    // qu'un rayon lui est donne, et le cadre entier restait alors blanc.
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: teinte),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 12, 14, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: enfants,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _jour(DateTime valeur) {
    final j = valeur.day.toString().padLeft(2, '0');
    final m = valeur.month.toString().padLeft(2, '0');
    return '$j/$m';
  }
}
