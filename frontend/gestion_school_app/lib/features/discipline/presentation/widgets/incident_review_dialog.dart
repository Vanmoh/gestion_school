import 'package:flutter/material.dart';

import '../../domain/discipline_incident.dart';

/// Ce qu'un arbitrage modifie sur un incident deja declare.
class IncidentReviewResult {
  final String severity;
  final String sanction;
  final String status;
  final bool parentNotified;

  const IncidentReviewResult({
    required this.severity,
    required this.sanction,
    required this.status,
    required this.parentNotified,
  });
}

/// Traitement d'un incident: qualifier, sanctionner, informer, clore.
///
/// L'ecran ne savait que declarer: un incident ouvert le restait, et la
/// sanction saisie a chaud lors de la declaration ne pouvait plus etre
/// corrigee. Le motif, la date et l'eleve ne sont volontairement pas
/// modifiables ici -- ils appartiennent au declarant, l'arbitrage porte sur
/// la suite donnee.
class IncidentReviewDialog extends StatefulWidget {
  final DisciplineIncident incident;

  const IncidentReviewDialog({super.key, required this.incident});

  @override
  State<IncidentReviewDialog> createState() => _IncidentReviewDialogState();
}

class _IncidentReviewDialogState extends State<IncidentReviewDialog> {
  late final TextEditingController _sanctionController;
  late String _severity;
  late String _status;
  late bool _parentNotified;

  @override
  void initState() {
    super.initState();
    _sanctionController = TextEditingController(
      text: widget.incident.sanction,
    );
    _severity = widget.incident.severity;
    _status = widget.incident.status;
    _parentNotified = widget.incident.parentNotified;
  }

  @override
  void dispose() {
    _sanctionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Traiter l\'incident'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(incident.libelleEleve, style: textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '${incident.category} • ${incident.incidentDate}',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Text(incident.description, style: textTheme.bodyMedium),
              if (incident.reportedByName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Déclaré par ${incident.reportedByName}',
                  style: textTheme.bodySmall,
                ),
              ],
              const Divider(height: 26),
              DropdownButtonFormField<String>(
                key: const Key('review-severity'),
                initialValue: _severity,
                decoration: const InputDecoration(labelText: 'Gravité'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('Faible')),
                  DropdownMenuItem(value: 'medium', child: Text('Moyenne')),
                  DropdownMenuItem(value: 'high', child: Text('Élevée')),
                ],
                onChanged: (value) =>
                    setState(() => _severity = value ?? _severity),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('review-sanction'),
                controller: _sanctionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Sanction'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('review-status'),
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Ouvert')),
                  DropdownMenuItem(value: 'resolved', child: Text('Traité')),
                ],
                onChanged: (value) =>
                    setState(() => _status = value ?? _status),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _parentNotified,
                title: const Text('Parent informé'),
                onChanged: (value) => setState(() => _parentNotified = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            IncidentReviewResult(
              severity: _severity,
              sanction: _sanctionController.text.trim(),
              status: _status,
              parentNotified: _parentNotified,
            ),
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
