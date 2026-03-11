import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class AcademicsPage extends ConsumerStatefulWidget {
  const AcademicsPage({super.key});

  @override
  ConsumerState<AcademicsPage> createState() => _AcademicsPageState();
}

class _AcademicsPageState extends ConsumerState<AcademicsPage> {
  final _yearNameController = TextEditingController();
  DateTime _yearStart = DateTime(DateTime.now().year, 9, 1);
  DateTime _yearEnd = DateTime(DateTime.now().year + 1, 7, 31);
  bool _yearActive = true;

  final _levelNameController = TextEditingController();
  final _sectionNameController = TextEditingController();

  final _subjectNameController = TextEditingController();
  final _subjectCodeController = TextEditingController();
  final _subjectCoefController = TextEditingController(text: '1');

  final _classNameController = TextEditingController();
  int? _selectedYearId;
  int? _selectedLevelId;
  int? _selectedSectionId;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _sections = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _yearNameController.dispose();
    _levelNameController.dispose();
    _sectionNameController.dispose();
    _subjectNameController.dispose();
    _subjectCodeController.dispose();
    _subjectCoefController.dispose();
    _classNameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/academic-years/'),
        dio.get('/levels/'),
        dio.get('/sections/'),
        dio.get('/subjects/'),
        dio.get('/classrooms/'),
      ]);

      if (!mounted) return;

      setState(() {
        _years = _extractRows(results[0].data);
        _levels = _extractRows(results[1].data);
        _sections = _extractRows(results[2].data);
        _subjects = _extractRows(results[3].data);
        _classrooms = _extractRows(results[4].data);

        _selectedYearId ??= _years.isNotEmpty
            ? _asInt(_years.first['id'])
            : null;
        _selectedLevelId ??= _levels.isNotEmpty
            ? _asInt(_levels.first['id'])
            : null;
        _selectedSectionId ??= _sections.isNotEmpty
            ? _asInt(_sections.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement académique: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _post(
    String endpoint,
    Map<String, dynamic> data,
    String successMessage,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(endpoint, data: data);
      if (!mounted) return false;
      _showMessage(successMessage, isSuccess: true);
      await _loadData();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _showMessage('Erreur: $error');
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openFloatingPanel({
    required String title,
    required Widget Function(
      BuildContext panelContext,
      VoidCallback refreshPanel,
    )
    contentBuilder,
  }) async {
    final compact = MediaQuery.of(context).size.width < 920;

    if (compact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return StatefulBuilder(
            builder: (panelContext, setPanelState) {
              void refreshPanel() {
                if (mounted) setState(() {});
                setPanelState(() {});
              }

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    16 + MediaQuery.of(panelContext).viewInsets.bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        contentBuilder(panelContext, refreshPanel),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(panelContext).pop(),
                            child: const Text('Fermer'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (panelContext, setPanelState) {
            void refreshPanel() {
              if (mounted) setState(() {});
              setPanelState(() {});
            }

            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: contentBuilder(panelContext, refreshPanel),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(panelContext).pop(),
                          child: const Text('Fermer'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitFromPanel({
    required BuildContext panelContext,
    required Future<bool> Function() action,
  }) async {
    final success = await action();
    if (!success || !mounted) return;

    if (panelContext.mounted) {
      final navigator = Navigator.of(panelContext);
      if (navigator.canPop()) {
        navigator.pop();
      }
    }
  }

  Future<void> _openYearForm() {
    return _openFloatingPanel(
      title: 'Créer une année scolaire',
      contentBuilder: (panelContext, refreshPanel) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _yearNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom (ex: 2025-2026)',
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate: _yearStart,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  _yearStart = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Début: ${_apiDate(_yearStart)}'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: panelContext,
                  initialDate: _yearEnd,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  _yearEnd = picked;
                  refreshPanel();
                }
              },
              icon: const Icon(Icons.event_available_outlined),
              label: Text('Fin: ${_apiDate(_yearEnd)}'),
            ),
            SizedBox(
              width: 260,
              child: Row(
                children: [
                  Switch(
                    value: _yearActive,
                    onChanged: (value) {
                      _yearActive = value;
                      refreshPanel();
                    },
                  ),
                  const Text('Année active'),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: () async {
                        final name = _yearNameController.text.trim();
                        if (name.isEmpty) {
                          _showMessage('Renseigne le nom de l’année scolaire.');
                          return false;
                        }
                        final success = await _post('/academic-years/', {
                          'name': name,
                          'start_date': _apiDate(_yearStart),
                          'end_date': _apiDate(_yearEnd),
                          'is_active': _yearActive,
                        }, 'Année scolaire créée');
                        if (success) {
                          _yearNameController.clear();
                        }
                        return success;
                      },
                    ),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Créer année scolaire'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openLevelForm() {
    return _openFloatingPanel(
      title: 'Créer un niveau',
      contentBuilder: (panelContext, _) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                controller: _levelNameController,
                decoration: const InputDecoration(
                  labelText: 'Niveau (ex: 6ème)',
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: () async {
                        final name = _levelNameController.text.trim();
                        if (name.isEmpty) {
                          _showMessage('Renseigne le nom du niveau.');
                          return false;
                        }
                        final success = await _post('/levels/', {
                          'name': name,
                        }, 'Niveau créé');
                        if (success) {
                          _levelNameController.clear();
                        }
                        return success;
                      },
                    ),
              icon: const Icon(Icons.school_outlined),
              label: const Text('Créer niveau'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSectionForm() {
    return _openFloatingPanel(
      title: 'Créer une section',
      contentBuilder: (panelContext, _) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 340,
              child: TextField(
                controller: _sectionNameController,
                decoration: const InputDecoration(
                  labelText: 'Section (ex: Collège)',
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: () async {
                        final name = _sectionNameController.text.trim();
                        if (name.isEmpty) {
                          _showMessage('Renseigne le nom de la section.');
                          return false;
                        }
                        final success = await _post('/sections/', {
                          'name': name,
                        }, 'Section créée');
                        if (success) {
                          _sectionNameController.clear();
                        }
                        return success;
                      },
                    ),
              icon: const Icon(Icons.account_tree_outlined),
              label: const Text('Créer section'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSubjectForm() {
    return _openFloatingPanel(
      title: 'Créer une matière',
      contentBuilder: (panelContext, _) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _subjectNameController,
                decoration: const InputDecoration(labelText: 'Nom matière'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _subjectCodeController,
                decoration: const InputDecoration(labelText: 'Code matière'),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _subjectCoefController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Coefficient'),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: () async {
                        final name = _subjectNameController.text.trim();
                        if (name.isEmpty) {
                          _showMessage('Renseigne le nom de la matière.');
                          return false;
                        }
                        final success = await _post('/subjects/', {
                          'name': name,
                          'code': _subjectCodeController.text.trim(),
                          'coefficient':
                              double.tryParse(
                                _subjectCoefController.text.trim(),
                              ) ??
                              1,
                        }, 'Matière créée');
                        if (success) {
                          _subjectNameController.clear();
                          _subjectCodeController.clear();
                          _subjectCoefController.text = '1';
                        }
                        return success;
                      },
                    ),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Créer matière'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openClassroomForm() {
    return _openFloatingPanel(
      title: 'Créer une classe',
      contentBuilder: (panelContext, refreshPanel) {
        if (_years.isEmpty || _levels.isEmpty || _sections.isEmpty) {
          return const Text(
            'Crée d’abord au moins une année scolaire, un niveau et une section.',
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _classNameController,
                decoration: const InputDecoration(
                  labelText: 'Nom classe (ex: 6A)',
                ),
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedYearId,
                decoration: const InputDecoration(labelText: 'Année scolaire'),
                items: _years
                    .map(
                      (y) => DropdownMenuItem<int?>(
                        value: _asInt(y['id']),
                        child: Text('${y['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _selectedYearId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedLevelId,
                decoration: const InputDecoration(labelText: 'Niveau'),
                items: _levels
                    .map(
                      (l) => DropdownMenuItem<int?>(
                        value: _asInt(l['id']),
                        child: Text('${l['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _selectedLevelId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedSectionId,
                decoration: const InputDecoration(labelText: 'Section'),
                items: _sections
                    .map(
                      (s) => DropdownMenuItem<int?>(
                        value: _asInt(s['id']),
                        child: Text('${s['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _selectedSectionId = value;
                  refreshPanel();
                },
              ),
            ),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: () async {
                        final name = _classNameController.text.trim();
                        if (name.isEmpty ||
                            _selectedYearId == null ||
                            _selectedLevelId == null ||
                            _selectedSectionId == null) {
                          _showMessage(
                            'Complète nom, année, niveau et section.',
                          );
                          return false;
                        }

                        final success = await _post('/classrooms/', {
                          'name': name,
                          'academic_year': _selectedYearId,
                          'level': _selectedLevelId,
                          'section': _selectedSectionId,
                        }, 'Classe créée');
                        if (success) {
                          _classNameController.clear();
                        }
                        return success;
                      },
                    ),
              icon: const Icon(Icons.meeting_room_outlined),
              label: const Text('Créer classe'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final yearById = {for (final y in _years) _asInt(y['id']): y};
    final levelById = {for (final l in _levels) _asInt(l['id']): l};
    final sectionById = {for (final s in _sections) _asInt(s['id']): s};

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeYearRow = _years.firstWhere(
      (row) => row['is_active'] == true,
      orElse: () => _years.isNotEmpty ? _years.first : <String, dynamic>{},
    );
    final activeYearLabel = activeYearRow.isEmpty
        ? 'Non définie'
        : _yearLabel(activeYearRow);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primaryContainer.withValues(alpha: 0.75),
                  colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Module Académie',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Gestion académique',
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Configure années scolaires, niveaux, sections, matières et classes dans un flux rapide.',
                          style: textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _dashboardInfoChip(
                              icon: Icons.calendar_month_outlined,
                              label: 'Année active: $activeYearLabel',
                              maxWidth: 260,
                            ),
                            _dashboardInfoChip(
                              icon: Icons.meeting_room_outlined,
                              label: '${_classrooms.length} classes',
                            ),
                            _dashboardInfoChip(
                              icon: Icons.menu_book_outlined,
                              label: '${_subjects.length} matières',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Actions en fenêtre flottante',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Chaque action ouvre un panneau dédié pour une saisie claire.',
                            style: textTheme.bodySmall,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: _saving ? null : _openYearForm,
                                icon: const Icon(Icons.calendar_month_outlined),
                                label: const Text('Créer année'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _saving ? null : _openLevelForm,
                                icon: const Icon(Icons.school_outlined),
                                label: const Text('Créer niveau'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _saving ? null : _openSectionForm,
                                icon: const Icon(Icons.account_tree_outlined),
                                label: const Text('Créer section'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _saving ? null : _openSubjectForm,
                                icon: const Icon(Icons.menu_book_outlined),
                                label: const Text('Créer matière'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _saving ? null : _openClassroomForm,
                                icon: const Icon(Icons.meeting_room_outlined),
                                label: const Text('Créer classe'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _saving ? null : _loadData,
                                icon: const Icon(Icons.sync),
                                label: const Text('Actualiser'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _moduleMetricCard(
              title: 'Années scolaires',
              value: '${_years.length}',
              icon: Icons.calendar_view_month_outlined,
              tone: colorScheme.primary,
            ),
            _moduleMetricCard(
              title: 'Niveaux',
              value: '${_levels.length}',
              icon: Icons.layers_outlined,
              tone: colorScheme.secondary,
            ),
            _moduleMetricCard(
              title: 'Sections',
              value: '${_sections.length}',
              icon: Icons.account_tree_outlined,
              tone: colorScheme.tertiary,
            ),
            _moduleMetricCard(
              title: 'Matières',
              value: '${_subjects.length}',
              icon: Icons.menu_book_outlined,
              tone: colorScheme.primary,
            ),
            _moduleMetricCard(
              title: 'Classes',
              value: '${_classrooms.length}',
              icon: Icons.meeting_room_outlined,
              tone: colorScheme.secondary,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Résumé académique', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Aperçu des structures créées et dernières classes configurées.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _dashboardInfoChip(
                      icon: Icons.calendar_today_outlined,
                      label: 'Années: ${_years.length}',
                    ),
                    _dashboardInfoChip(
                      icon: Icons.school_outlined,
                      label: 'Niveaux: ${_levels.length}',
                    ),
                    _dashboardInfoChip(
                      icon: Icons.account_tree_outlined,
                      label: 'Sections: ${_sections.length}',
                    ),
                    _dashboardInfoChip(
                      icon: Icons.menu_book_outlined,
                      label: 'Matières: ${_subjects.length}',
                    ),
                    _dashboardInfoChip(
                      icon: Icons.meeting_room_outlined,
                      label: 'Classes: ${_classrooms.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_classrooms.isEmpty)
                  const Text('Aucune classe créée pour le moment.')
                else
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.55,
                        ),
                      ),
                    ),
                    child: Column(
                      children: _classrooms.take(10).map((classroom) {
                        final levelName =
                            levelById[_asInt(classroom['level'])]?['name'] ??
                            'Niveau ?';
                        final sectionName =
                            sectionById[_asInt(
                              classroom['section'],
                            )]?['name'] ??
                            'Section ?';
                        final yearName =
                            yearById[_asInt(
                              classroom['academic_year'],
                            )]?['name'] ??
                            'Année ?';

                        return ListTile(
                          dense: true,
                          title: Text('${classroom['name']}'),
                          subtitle: Text(
                            '$levelName • $sectionName • $yearName',
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dashboardInfoChip({
    required IconData icon,
    required String label,
    double maxWidth = 220,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color tone,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tone.withValues(alpha: 0.1), scheme.surface],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: tone.withValues(alpha: 0.18),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _yearLabel(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;

    final start = row['start_date']?.toString().trim() ?? '';
    final end = row['end_date']?.toString().trim() ?? '';
    if (start.isNotEmpty || end.isNotEmpty) {
      return '$start - $end';
    }

    return 'Année ${row['id'] ?? ''}'.trim();
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isSuccess ? Colors.green.shade700 : null,
      ),
    );
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final List<dynamic> rows;
    if (data is Map<String, dynamic> && data['results'] is List) {
      rows = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      rows = data;
    } else {
      rows = [];
    }

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _apiDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
}
