import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/discipline_incident.dart';
import '../domain/parent_discipline_grouping.dart';
import 'discipline_controller.dart';

/// Vue discipline en lecture seule destinee aux parents et aux eleves.
///
/// Le backend restreint deja `/discipline-incidents/` aux enfants du parent
/// connecte (ou a l'élève lui-meme), la page n'a donc aucun filtrage a faire:
/// elle se contente de presenter les incidents recus, groupes par enfant.
/// Aucune action d'ecriture n'est exposee.
class ParentDisciplinePage extends ConsumerStatefulWidget {
  const ParentDisciplinePage({super.key});

  @override
  ConsumerState<ParentDisciplinePage> createState() =>
      _ParentDisciplinePageState();
}

class _ParentDisciplinePageState extends ConsumerState<ParentDisciplinePage> {
  bool _loading = true;
  bool _restricted = false;
  String? _errorMessage;
  List<DisciplineIncident> _incidents = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      // Le depot ne lit plus le JSON de l'API a la main: la page recopiait
      // l'extraction de `results` que chaque ecran refaisait a sa facon.
      final incidents = await ref
          .read(disciplineRepositoryProvider)
          .fetchIncidents();
      if (!mounted) return;
      setState(() {
        _incidents = incidents;
        _restricted = false;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _incidents = const [];
        _restricted = status == 401 || status == 403;
        _errorMessage = _restricted
            ? null
            : 'Impossible de charger le suivi disciplinaire pour le moment.';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _incidents = const [];
        _restricted = false;
        _errorMessage =
            'Impossible de charger le suivi disciplinaire pour le moment.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final groups = groupIncidentsByChild(_incidents);
    final openCount = _incidents.where((row) => row.estOuvert).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Discipline', style: textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Suivi des incidents disciplinaires concernant vos enfants.',
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_errorMessage != null)
            _NoticeCard(
              icon: Icons.error_outline,
              color: colorScheme.error,
              message: _errorMessage!,
            )
          else if (_restricted)
            _NoticeCard(
              icon: Icons.lock_outline,
              color: colorScheme.onSurfaceVariant,
              message:
                  'Le suivi disciplinaire n\'est pas accessible avec vos droits actuels.',
            )
          else if (_incidents.isEmpty)
            _NoticeCard(
              icon: Icons.verified_outlined,
              color: const Color(0xFF197A43),
              message:
                  'Aucun incident disciplinaire enregistré. Rien a signaler.',
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.gpp_maybe_outlined, size: 16),
                  label: Text(
                    '${_incidents.length} incident${_incidents.length > 1 ? 's' : ''}',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.pending_actions_outlined, size: 16),
                  label: Text(
                    '$openCount en cours',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.family_restroom_outlined, size: 16),
                  label: Text(
                    '${groups.length} enfant${groups.length > 1 ? 's' : ''} concerne${groups.length > 1 ? 's' : ''}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final group in groups) ...[
              _ChildIncidentsCard(group: group),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _ChildIncidentsCard extends StatelessWidget {
  final ChildIncidentGroup group;

  const _ChildIncidentsCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final openCount = group.openCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.person_outline, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.childName,
                        style: textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (group.matricule.isNotEmpty)
                        Text(
                          'Matricule ${group.matricule}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  openCount == 0
                      ? '${group.incidents.length} clos'
                      : '$openCount en cours',
                  style: textTheme.labelLarge?.copyWith(
                    color: openCount == 0
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final incident in group.incidents) ...[
              _IncidentTile(incident: incident),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  final DisciplineIncident incident;

  const _IncidentTile({required this.incident});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final severity = incident.severity;
    final resolved = !incident.estOuvert;
    final sanction = incident.sanction.trim();
    final description = incident.description.trim();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(incident.libelleMotif, style: textTheme.titleSmall),
              _Badge(
                label: _severityLabel(severity),
                color: _severityColor(severity, colorScheme),
              ),
              _Badge(
                label: resolved ? 'Traite' : 'En cours',
                color: resolved
                    ? const Color(0xFF197A43)
                    : colorScheme.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatDate(incident.incidentDate),
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          // « Traite » ne disait pas quand: pour une famille, la date de
          // cloture est ce qui distingue un dossier suivi d'un dossier
          // range sans suite.
          if (resolved && incident.jourDeCloture.isNotEmpty)
            Text(
              'Traite le ${_formatDate(incident.jourDeCloture)}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, style: textTheme.bodyMedium),
          ],
          if (sanction.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.gavel_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sanction: $sanction',
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
          if (incident.parentNotified) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'Famille informee',
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _NoticeCard({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _severityLabel(String value) {
  switch (value) {
    case 'low':
      return 'Gravite faible';
    case 'high':
      return 'Gravite elevee';
    default:
      return 'Gravite moyenne';
  }
}

Color _severityColor(String value, ColorScheme colorScheme) {
  switch (value) {
    case 'low':
      return const Color(0xFF197A43);
    case 'high':
      return colorScheme.error;
    default:
      return const Color(0xFFB26A00);
  }
}

const _monthLabels = <String>[
  'janvier',
  'fevrier',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'aout',
  'septembre',
  'octobre',
  'novembre',
  'decembre',
];

String _formatDate(String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return '${parsed.day} ${_monthLabels[parsed.month - 1]} ${parsed.year}';
}
