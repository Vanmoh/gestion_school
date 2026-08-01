import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../models/etablissement.dart';

class PromotionPage extends ConsumerStatefulWidget {
  const PromotionPage({super.key});

  @override
  ConsumerState<PromotionPage> createState() => _PromotionPageState();
}

class _PromotionPageState extends ConsumerState<PromotionPage> {
  bool _loading = true;
  bool _busy = false;

  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _runs = [];

  int? _sourceYearId;
  int? _targetYearId;
  final Set<int> _sourceClassroomIds = <int>{};

  final TextEditingController _minAverageController = TextEditingController(text: '10');
  final TextEditingController _minConduiteController = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _minAverageController.dispose();
    _minConduiteController.dispose();
    super.dispose();
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final rows = data is Map<String, dynamic> && data['results'] is List<dynamic>
        ? data['results'] as List<dynamic>
        : (data is List<dynamic> ? data : const <dynamic>[]);
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    try {
      final parsed = DateTime.parse(raw).toLocal();
      return DateFormat('dd/MM/yyyy HH:mm').format(parsed);
    } catch (_) {
      return raw;
    }
  }

  String _decisionLabel(String value) {
    switch (value) {
      case 'promoted':
        return 'Promu';
      case 'repeated':
        return 'Redouble';
      case 'archived':
        return 'Archive';
      default:
        return value;
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'simulated':
        return 'Simulation';
      case 'executed':
        return 'Execute';
      default:
        return value;
    }
  }

  String _yearLabel(dynamic idValue) {
    final id = _asInt(idValue);
    if (id == null) {
      return '-';
    }
    for (final row in _years) {
      if (_asInt(row['id']) == id) {
        return row['name']?.toString() ?? '$id';
      }
    }
    return '$id';
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }

    try {
      final dio = ref.read(dioProvider);
      final responses = await Future.wait<Response<dynamic>>([
        dio.get('/academic-years/'),
        dio.get('/classrooms/'),
        dio.get('/promotion-runs/'),
      ]);

      final years = _extractRows(responses[0].data);
      final classrooms = _extractRows(responses[1].data);
      final runs = _extractRows(responses[2].data);

      if (!mounted) {
        return;
      }

      setState(() {
        _years = years;
        _classrooms = classrooms;
        _runs = runs;
        _sourceYearId ??= _asInt(
          years.cast<Map<String, dynamic>?>().firstWhere(
                (item) => item?['is_active'] == true,
                orElse: () => years.isNotEmpty ? years.first : null,
              )?['id'],
        );
        final firstYearId = years.isNotEmpty ? _asInt(years.first['id']) : null;
        _targetYearId ??= firstYearId;
        if (_targetYearId == _sourceYearId) {
          for (final year in years) {
            final candidateId = _asInt(year['id']);
            if (candidateId != null && candidateId != _sourceYearId) {
              _targetYearId = candidateId;
              break;
            }
          }
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Erreur de chargement: $error');
    } finally {
      if (mounted && showLoading) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> _targetClassroomsForYear() {
    return _classrooms
        .where((row) => _asInt(row['academic_year']) == _targetYearId)
        .toList(growable: false);
  }

  Map<int, Map<String, dynamic>?> _computeAutoMappingPreview(List<Map<String, dynamic>> sourceClasses) {
    final targets = _targetClassroomsForYear();
    final targetByName = <String, Map<String, dynamic>>{};

    for (final row in targets) {
      final name = (row['name']?.toString() ?? '').trim().toLowerCase();
      targetByName[name] = row;
    }

    final mapping = <int, Map<String, dynamic>?>{};
    for (final source in sourceClasses) {
      final sourceId = _asInt(source['id']);
      if (sourceId == null) {
        continue;
      }

      final sourceName = (source['name']?.toString() ?? '').trim().toLowerCase();
      final exact = targetByName[sourceName];
      if (exact != null) {
        mapping[sourceId] = exact;
        continue;
      }

      mapping[sourceId] = targets.isNotEmpty ? targets.first : null;
    }

    return mapping;
  }

  Future<bool> _confirmExecuteWhenMissingTargets(List<Map<String, dynamic>> sourceClasses) async {
    final mapping = _computeAutoMappingPreview(sourceClasses);
    final missing = <String>[];
    for (final source in sourceClasses) {
      final sourceId = _asInt(source['id']);
      if (sourceId == null) {
        continue;
      }
      if (mapping[sourceId] == null) {
        missing.add(source['name']?.toString() ?? 'Classe inconnue');
      }
    }

    if (missing.isEmpty) {
      return true;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Classes cibles manquantes'),
          content: Text(
            'Aucune classe cible automatique n\'a ete trouvee pour:\n'
            '${missing.join('\n')}\n\n'
            'Les eleves eligibles de ces classes seront archives automatiquement. Continuer ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continuer'),
            ),
          ],
        );
      },
    );

    return proceed == true;
  }

  Future<void> _launchRun({required bool execute}) async {
    if (_sourceYearId == null) {
      _showMessage('Selectionnez une annee source.');
      return;
    }

    final minAverage = double.tryParse(_minAverageController.text.trim().replaceAll(',', '.'));
    final minConduite = double.tryParse(_minConduiteController.text.trim().replaceAll(',', '.'));
    if (minAverage == null || minConduite == null) {
      _showMessage('Les seuils doivent etre numeriques.');
      return;
    }

    if (_targetYearId == null) {
      _showMessage('Selectionnez une annee cible.');
      return;
    }

    if (_sourceYearId == _targetYearId) {
      _showMessage('L\'annee cible doit etre differente de l\'annee source.');
      return;
    }

    final sourceClasses = _classrooms
        .where((row) => _asInt(row['academic_year']) == _sourceYearId)
        .where((row) {
          if (_sourceClassroomIds.isEmpty) {
            return true;
          }
          final id = _asInt(row['id']);
          return id != null && _sourceClassroomIds.contains(id);
        })
        .toList(growable: false);

    if (execute) {
      final proceed = await _confirmExecuteWhenMissingTargets(sourceClasses);
      if (!proceed) {
        return;
      }
    }

    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'source_academic_year': _sourceYearId,
        'target_academic_year': _targetYearId,
        'min_average': minAverage,
        'min_conduite': minConduite,
        if (_sourceClassroomIds.isNotEmpty)
          'source_classrooms': _sourceClassroomIds.toList(growable: false),
      };

      final endpoint = execute ? '/promotion-runs/execute/' : '/promotion-runs/simulate/';
      await ref.read(dioProvider).post(endpoint, data: payload);

      if (!mounted) {
        return;
      }
      _showMessage(
        execute
            ? 'Passation executee avec succes.'
            : 'Simulation de passation creee avec succes.',
        isSuccess: true,
      );
      await _loadData(showLoading: false);
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showMessage('Echec operation: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showDecisions(Map<String, dynamic> run) {
    final decisions = run['decisions'] is List<dynamic>
        ? (run['decisions'] as List<dynamic>).whereType<Map<String, dynamic>>().toList(growable: false)
        : const <Map<String, dynamic>>[];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Decisions du lot #${run['id'] ?? '-'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (decisions.isEmpty)
                  const Text('Aucune decision disponible.')
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: decisions.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final row = decisions[index];
                        final studentName = (row['student_full_name']?.toString().trim().isNotEmpty ?? false)
                            ? row['student_full_name'].toString().trim()
                            : 'Eleve #${row['student'] ?? '-'}';
                        final matricule = row['student_matricule']?.toString() ?? '';
                        final sourceClass = row['source_classroom_name']?.toString() ?? '-';
                        final targetClass = row['target_classroom_name']?.toString() ?? '-';
                        final decision = _decisionLabel(row['decision']?.toString() ?? '-');
                        final avg = row['average']?.toString() ?? '0';
                        final conduite = row['conduite']?.toString() ?? '0';
                        final rank = row['rank']?.toString() ?? '-';
                        final reason = row['reason']?.toString() ?? '';

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('$studentName${matricule.isNotEmpty ? ' ($matricule)' : ''}'),
                          subtitle: Text(
                            'Decision: $decision | Rang: $rank | Moy: $avg | Conduite: $conduite\n'
                            'Classe: $sourceClass -> $targetClass'
                            '${reason.trim().isNotEmpty ? '\nMotif: $reason' : ''}',
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final selectedEtab = ref.watch(etablissementProvider).selected;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final sourceClasses = _classrooms
        .where((row) => _asInt(row['academic_year']) == _sourceYearId)
        .toList(growable: false)
      ..sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));

    return RefreshIndicator(
      onRefresh: () => _loadData(showLoading: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Passation & Archivage',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selectedEtab == null
                ? 'Aucun etablissement selectionne.'
                : 'Etablissement actif: ${selectedEtab.name}',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lancer une passation',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    key: ValueKey('source-year-${_sourceYearId ?? 'none'}'),
                    initialValue: _sourceYearId,
                    decoration: const InputDecoration(labelText: 'Annee source'),
                    items: _years
                        .map(
                          (row) => DropdownMenuItem<int?>(
                            value: _asInt(row['id']),
                            child: Text(row['name']?.toString() ?? '-'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _sourceYearId = value;
                              _sourceClassroomIds.clear();
                              if (_targetYearId == _sourceYearId) {
                                for (final year in _years) {
                                  final candidateId = _asInt(year['id']);
                                  if (candidateId != null && candidateId != _sourceYearId) {
                                    _targetYearId = candidateId;
                                    break;
                                  }
                                }
                              }
                            });
                          },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    key: ValueKey('target-year-${_targetYearId ?? 'none'}'),
                    initialValue: _targetYearId,
                    decoration: const InputDecoration(
                      labelText: 'Annee cible',
                      helperText: 'Obligatoire et differente de l\'annee source',
                    ),
                    items: [
                      ..._years.map(
                        (row) => DropdownMenuItem<int?>(
                          value: _asInt(row['id']),
                          child: Text(row['name']?.toString() ?? '-'),
                        ),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _targetYearId = value),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minAverageController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Seuil moyenne'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _minConduiteController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Seuil conduite'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Classes sources',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (sourceClasses.isEmpty)
                    const Text('Aucune classe trouvee pour cette annee source.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: sourceClasses.map((row) {
                        final id = _asInt(row['id']);
                        final selected = id != null && _sourceClassroomIds.contains(id);
                        return FilterChip(
                          label: Text(row['name']?.toString() ?? '-'),
                          selected: selected,
                          onSelected: _busy || id == null
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value) {
                                      _sourceClassroomIds.add(id);
                                    } else {
                                      _sourceClassroomIds.remove(id);
                                    }
                                  });
                                },
                        );
                      }).toList(growable: false),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _launchRun(execute: false),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Simuler'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _launchRun(execute: true),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Executer'),
                      ),
                    ],
                  ),
                  if (_sourceYearId == _targetYearId)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Attention: l\'annee source et l\'annee cible doivent etre differentes.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Historique des lots',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_runs.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucun lot de passation pour le moment.'),
              ),
            )
          else
            ..._runs.map((run) {
              final status = run['status']?.toString() ?? '-';
              final sourceYearName = _yearLabel(run['source_academic_year']);
              final targetYearName = _yearLabel(run['target_academic_year']);
              final total = run['total_students']?.toString() ?? '0';
              final promoted = run['promoted_count']?.toString() ?? '0';
              final repeated = run['repeated_count']?.toString() ?? '0';
              final archived = run['archived_count']?.toString() ?? '0';

              return Card(
                child: ListTile(
                  title: Text(
                    'Lot #${run['id'] ?? '-'} • ${_statusLabel(status)}',
                  ),
                  subtitle: Text(
                    'Source: $sourceYearName | Cible: $targetYearName\n'
                    'Total: $total | Promus: $promoted | Redoublants: $repeated | Archives: $archived\n'
                    'Cree le: ${_formatDate(run['created_at']?.toString())}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Voir decisions',
                    onPressed: () => _showDecisions(run),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
