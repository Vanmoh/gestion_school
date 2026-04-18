import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../../models/etablissement.dart';
import '../../../core/network/api_client.dart';

class AcademicsPage extends ConsumerStatefulWidget {
  const AcademicsPage({super.key});

  @override
  ConsumerState<AcademicsPage> createState() => _AcademicsPageState();
}

class _AcademicsPageState extends ConsumerState<AcademicsPage> {
  static const int _rowsPerPage = 8;
  final _yearNameController = TextEditingController();
  DateTime _yearStart = DateTime(DateTime.now().year, 9, 1);
  DateTime _yearEnd = DateTime(DateTime.now().year + 1, 7, 31);
  bool _yearActive = true;

  final _subjectNameController = TextEditingController();
  final _subjectCoefController = TextEditingController(text: '1');
  final _classSearchController = TextEditingController();
  final _subjectSearchController = TextEditingController();

  final _classNameController = TextEditingController();
  int? _selectedYearId;
  int? _selectedSubjectClassroomId;
  String _classQuery = '';
  String _subjectQuery = '';
  int? _subjectFilterClassroomId;
  int _classPage = 1;
  int _subjectPage = 1;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];
  int? _loadedEtablissementId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _yearNameController.dispose();
    _subjectNameController.dispose();
    _subjectCoefController.dispose();
    _classSearchController.dispose();
    _subjectSearchController.dispose();
    _classNameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final selectedEtablissement = ref.read(etablissementProvider).selected;
      final selectedEtablissementId = selectedEtablissement?.id;
      final yearResult = await dio.get('/academic-years/');
      List<Map<String, dynamic>> loadedSubjects = [];
      List<Map<String, dynamic>> loadedClassrooms = [];

      if (selectedEtablissementId != null) {
        final results = await Future.wait([
          dio.get('/subjects/?etablissement=$selectedEtablissementId'),
          dio.get('/classrooms/?etablissement=$selectedEtablissementId'),
        ]);
        loadedSubjects = _extractRows(results[0].data);
        loadedClassrooms = _extractRows(results[1].data);
      }

      if (!mounted) return;

      setState(() {
        _years = _extractRows(yearResult.data);
        _subjects = loadedSubjects;
        _classrooms = loadedClassrooms;
        _loadedEtablissementId = selectedEtablissementId;

        final activeYear = _years.firstWhere(
          (row) => row['is_active'] == true,
          orElse: () => <String, dynamic>{},
        );
        _selectedYearId = activeYear.isEmpty ? null : _asInt(activeYear['id']);
        if (_classrooms.isEmpty) {
          _selectedSubjectClassroomId = null;
          _subjectFilterClassroomId = null;
        } else {
          final selectedStillExists = _classrooms.any(
            (row) => _asInt(row['id']) == _selectedSubjectClassroomId,
          );
          if (!selectedStillExists) {
            _selectedSubjectClassroomId = _asInt(_classrooms.first['id']);
          }

          if (_subjectFilterClassroomId != null) {
            final filterStillExists = _classrooms.any(
              (row) => _asInt(row['id']) == _subjectFilterClassroomId,
            );
            if (!filterStillExists) {
              _subjectFilterClassroomId = null;
            }
          }
        }
        _classPage = 1;
        _subjectPage = 1;
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
      _showMessage('Erreur: ${_extractApiError(error)}');
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _patch(
    String endpoint,
    Map<String, dynamic> data,
    String successMessage,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).patch(endpoint, data: data);
      if (!mounted) return false;
      _showMessage(successMessage, isSuccess: true);
      await _loadData();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _showMessage('Erreur: ${_extractApiError(error)}');
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _delete(
    String endpoint,
    String successMessage,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete(endpoint);
      if (!mounted) return false;
      _showMessage(successMessage, isSuccess: true);
      await _loadData();
      return true;
    } catch (error) {
      if (!mounted) return false;
      _showMessage('Suppression refusée: ${_extractApiError(error)}');
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _extractApiError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        for (final key in const ['detail', 'message', 'error']) {
          final value = data[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString();
          }
        }
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return '${entry.key}: ${value.first}';
          }
          if (value != null && value.toString().trim().isNotEmpty) {
            return '${entry.key}: $value';
          }
        }
      }
      final status = error.response?.statusCode;
      if (status != null) {
        return 'HTTP $status';
      }
    }
    return error.toString();
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

  Future<void> _openSubjectForm() {
    return _openFloatingPanel(
      title: 'Créer une matière',
      contentBuilder: (panelContext, refreshPanel) {
        if (_classrooms.isEmpty) {
          return const Text(
            'Crée d’abord une classe. Chaque matière est maintenant liée à une classe.',
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedSubjectClassroomId,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _selectedSubjectClassroomId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _subjectNameController,
                decoration: const InputDecoration(labelText: 'Nom matière'),
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
                        final classroomId = _selectedSubjectClassroomId;
                        if (classroomId == null) {
                          _showMessage('Sélectionne une classe pour la matière.');
                          return false;
                        }

                        final name = _subjectNameController.text.trim();
                        if (name.isEmpty) {
                          _showMessage('Renseigne le nom de la matière.');
                          return false;
                        }

                        final success = await _post('/subjects/', {
                          'name': name,
                          'classroom': classroomId,
                          'coefficient':
                              double.tryParse(
                                _subjectCoefController.text.trim(),
                              ) ??
                              1,
                        }, 'Matière créée');
                        if (success) {
                          _subjectNameController.clear();
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

  Future<void> _openEditClassroomForm(Map<String, dynamic> classroom) {
    _classNameController.text = classroom['name']?.toString() ?? '';
    _selectedYearId = _asInt(classroom['academic_year']);

    return _openFloatingPanel(
      title: 'Modifier classe',
      contentBuilder: (panelContext, refreshPanel) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _classNameController,
                decoration: const InputDecoration(labelText: 'Nom classe'),
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int>(
                initialValue: _selectedYearId,
                decoration: const InputDecoration(labelText: 'Année scolaire'),
                items: _years
                    .map(
                      (y) => DropdownMenuItem<int>(
                        value: _asInt(y['id']),
                        child: Text(_yearLabel(y)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _selectedYearId = value;
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
                        final selectedEtab =
                            ref.read(etablissementProvider).selected;
                        final id = _asInt(classroom['id']);
                        final name = _classNameController.text.trim();
                        if (selectedEtab == null || id <= 0) {
                          _showMessage('Établissement actif introuvable.');
                          return false;
                        }
                        if (name.isEmpty || _selectedYearId == null) {
                          _showMessage('Renseigne le nom et l\'année.');
                          return false;
                        }
                        return _patch(
                          '/classrooms/$id/?etablissement=${selectedEtab.id}',
                          {
                            'name': name,
                            'academic_year': _selectedYearId,
                          },
                          'Classe modifiée',
                        );
                      },
                    ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openClassroomDetails(Map<String, dynamic> classroom) {
    final classId = _asInt(classroom['id']);
    final yearLabel = _yearLabel(
      _years.firstWhere(
        (row) => _asInt(row['id']) == _asInt(classroom['academic_year']),
        orElse: () => <String, dynamic>{},
      ),
    );
    final subjectsCount = _subjects.where((s) => _asInt(s['classroom']) == classId).length;

    return _openFloatingPanel(
      title: 'Détail classe',
      contentBuilder: (panelContext, refreshPanel) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom: ${classroom['name'] ?? '-'}'),
            const SizedBox(height: 6),
            Text('Année: $yearLabel'),
            const SizedBox(height: 6),
            Text('Établissement: ${ref.read(etablissementProvider).selected?.name ?? '-'}'),
            const SizedBox(height: 6),
            Text('Matières liées: $subjectsCount'),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteClassroom(Map<String, dynamic> classroom) async {
    final selectedEtab = ref.read(etablissementProvider).selected;
    final id = _asInt(classroom['id']);
    if (selectedEtab == null || id <= 0) {
      _showMessage('Établissement actif introuvable.');
      return;
    }

    Map<String, dynamic>? precheck;
    try {
      final response = await ref
          .read(dioProvider)
          .get('/classrooms/$id/delete-check/?etablissement=${selectedEtab.id}');
      if (response.data is Map<String, dynamic>) {
        precheck = Map<String, dynamic>.from(response.data as Map<String, dynamic>);
      }
    } catch (_) {
      precheck = null;
    }

    final deps = (precheck?['dependencies'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(precheck!['dependencies'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final canDelete = precheck?['can_delete'] == true;

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final depLines = <String>[];
        if (deps.isNotEmpty) {
          depLines.add('Dépendances détectées:');
          depLines.add('Élèves: ${deps['students'] ?? 0}');
          depLines.add('Matières: ${deps['subjects'] ?? 0}');
          depLines.add('Affectations: ${deps['teacher_assignments'] ?? 0}');
          depLines.add('Notes: ${deps['grades'] ?? 0}');
          depLines.add('Validations: ${deps['grade_validations'] ?? 0}');
          depLines.add('Plannings examens: ${deps['exam_plannings'] ?? 0}');
          depLines.add('Historiques: ${deps['academic_history'] ?? 0}');
        }
        return AlertDialog(
          title: const Text('Supprimer la classe ?'),
          content: Text(
            depLines.isEmpty
                ? 'Confirmer la suppression de la classe ${classroom['name']} ? '
                    'Cette action peut être refusée si des dépendances existent.'
                : 'Classe ${classroom['name']}\n\n${depLines.join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: canDelete ? () => Navigator.of(ctx).pop(true) : null,
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    await _delete(
      '/classrooms/$id/?etablissement=${selectedEtab.id}',
      'Classe supprimée',
    );
  }

  Future<void> _openEditSubjectForm(Map<String, dynamic> subject) {
    _subjectNameController.text = subject['name']?.toString() ?? '';
    _subjectCoefController.text = (subject['coefficient'] ?? '1').toString();
    _selectedSubjectClassroomId = _asInt(subject['classroom']);

    return _openFloatingPanel(
      title: 'Modifier matière',
      contentBuilder: (panelContext, refreshPanel) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<int?>(
                initialValue: _selectedSubjectClassroomId,
                decoration: const InputDecoration(labelText: 'Classe'),
                items: _classrooms
                    .map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _selectedSubjectClassroomId = value;
                  refreshPanel();
                },
              ),
            ),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _subjectNameController,
                decoration: const InputDecoration(labelText: 'Nom matière'),
              ),
            ),
            SizedBox(
              width: 180,
              child: TextField(
                controller: _subjectCoefController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Coefficient'),
              ),
            ),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: () async {
                        final selectedEtab =
                            ref.read(etablissementProvider).selected;
                        final id = _asInt(subject['id']);
                        final name = _subjectNameController.text.trim();
                        final classroomId = _selectedSubjectClassroomId;
                        if (selectedEtab == null || id <= 0) {
                          _showMessage('Établissement actif introuvable.');
                          return false;
                        }
                        if (name.isEmpty || classroomId == null) {
                          _showMessage('Renseigne la classe et le nom.');
                          return false;
                        }
                        return _patch(
                          '/subjects/$id/?etablissement=${selectedEtab.id}',
                          {
                            'name': name,
                            'classroom': classroomId,
                            'coefficient':
                                double.tryParse(_subjectCoefController.text.trim()) ?? 1,
                          },
                          'Matière modifiée',
                        );
                      },
                    ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSubjectDetails(Map<String, dynamic> subject) {
    final classroomName = subject['classroom_name']?.toString().trim().isNotEmpty == true
        ? subject['classroom_name'].toString()
        : _classrooms
              .firstWhere(
                (row) => _asInt(row['id']) == _asInt(subject['classroom']),
                orElse: () => <String, dynamic>{},
              )['name']
              ?.toString() ??
          '-';

    return _openFloatingPanel(
      title: 'Détail matière',
      contentBuilder: (panelContext, refreshPanel) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nom: ${subject['name'] ?? '-'}'),
            const SizedBox(height: 6),
            Text('Code: ${subject['code'] ?? '-'}'),
            const SizedBox(height: 6),
            Text('Coefficient: ${subject['coefficient'] ?? '-'}'),
            const SizedBox(height: 6),
            Text('Classe: $classroomName'),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteSubject(Map<String, dynamic> subject) async {
    final selectedEtab = ref.read(etablissementProvider).selected;
    final id = _asInt(subject['id']);
    if (selectedEtab == null || id <= 0) {
      _showMessage('Établissement actif introuvable.');
      return;
    }

    Map<String, dynamic>? precheck;
    try {
      final response = await ref
          .read(dioProvider)
          .get('/subjects/$id/delete-check/?etablissement=${selectedEtab.id}');
      if (response.data is Map<String, dynamic>) {
        precheck = Map<String, dynamic>.from(response.data as Map<String, dynamic>);
      }
    } catch (_) {
      precheck = null;
    }

    final deps = (precheck?['dependencies'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(precheck!['dependencies'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final canDelete = precheck?['can_delete'] == true;

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final depLines = <String>[];
        if (deps.isNotEmpty) {
          depLines.add('Dépendances détectées:');
          depLines.add('Affectations: ${deps['teacher_assignments'] ?? 0}');
          depLines.add('Notes: ${deps['grades'] ?? 0}');
          depLines.add('Plannings examens: ${deps['exam_plannings'] ?? 0}');
          depLines.add('Résultats examens: ${deps['exam_results'] ?? 0}');
        }
        return AlertDialog(
          title: const Text('Supprimer la matière ?'),
          content: Text(
            depLines.isEmpty
                ? 'Confirmer la suppression de la matière ${subject['name']} ? '
                    'Cette action peut être refusée si des dépendances existent.'
                : 'Matière ${subject['name']}\n\n${depLines.join('\n')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: canDelete ? () => Navigator.of(ctx).pop(true) : null,
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    await _delete(
      '/subjects/$id/?etablissement=${selectedEtab.id}',
      'Matière supprimée',
    );
  }

  Future<void> _openClassroomForm() {
    return _openFloatingPanel(
      title: 'Créer une classe',
      contentBuilder: (panelContext, refreshPanel) {
        final selectedEtablissement = ref.read(etablissementProvider).selected;
        if (selectedEtablissement == null) {
          return const Text(
            'Sélectionne un établissement actif avant de créer une classe.',
          );
        }

        if (_years.isEmpty) {
          return const Text(
            'Crée d’abord une année scolaire active.',
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
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Année scolaire'),
                child: Text(
                  _years
                          .firstWhere(
                            (row) => _asInt(row['id']) == _selectedYearId,
                            orElse: () => <String, dynamic>{},
                          )['name']
                          ?.toString() ??
                      'Année active non définie',
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _submitFromPanel(
                      panelContext: panelContext,
                      action: () async {
                        final name = _classNameController.text.trim();
                        if (name.isEmpty || _selectedYearId == null) {
                          _showMessage(
                            'Complète le nom et vérifie qu’une année active existe.',
                          );
                          return false;
                        }

                        final success = await _post(
                          '/classrooms/?etablissement=${selectedEtablissement.id}',
                          {
                          'name': name,
                          'academic_year': _selectedYearId,
                          },
                          'Classe créée pour ${selectedEtablissement.name}',
                        );
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
    final authUser = ref.watch(authControllerProvider).value;
    final isSuperAdmin = authUser?.role == 'super_admin';
    final selectedEtablissement = ref.watch(etablissementProvider).selected;
    final etablissements = ref.watch(etablissementProvider).etablissements;
    final selectedEtablissementId = selectedEtablissement?.id;

    if (!_loading && _loadedEtablissementId != selectedEtablissementId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final yearById = {for (final y in _years) _asInt(y['id']): y};
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeYearRow = _years.firstWhere(
      (row) => row['is_active'] == true,
      orElse: () => _years.isNotEmpty ? _years.first : <String, dynamic>{},
    );
    final activeYearLabel = activeYearRow.isEmpty
        ? 'Non définie'
        : _yearLabel(activeYearRow);
    final normalizedClassQuery = _classQuery.trim().toLowerCase();
    final normalizedSubjectQuery = _subjectQuery.trim().toLowerCase();
    final filteredClassrooms = _classrooms.where((row) {
      if (normalizedClassQuery.isEmpty) return true;
      final name = (row['name'] ?? '').toString().toLowerCase();
      final yearName =
          (yearById[_asInt(row['academic_year'])]?['name'] ?? '').toString().toLowerCase();
      return name.contains(normalizedClassQuery) || yearName.contains(normalizedClassQuery);
    }).toList();
    final filteredSubjects = _subjects.where((row) {
      if (_subjectFilterClassroomId != null &&
          _asInt(row['classroom']) != _subjectFilterClassroomId) {
        return false;
      }
      if (normalizedSubjectQuery.isEmpty) return true;
      final name = (row['name'] ?? '').toString().toLowerCase();
      final code = (row['code'] ?? '').toString().toLowerCase();
      final className = (row['classroom_name'] ?? '').toString().toLowerCase();
      return name.contains(normalizedSubjectQuery) ||
          code.contains(normalizedSubjectQuery) ||
          className.contains(normalizedSubjectQuery);
    }).toList();
    final classTotalPages = filteredClassrooms.isEmpty
      ? 1
      : ((filteredClassrooms.length - 1) ~/ _rowsPerPage) + 1;
    final subjectTotalPages = filteredSubjects.isEmpty
      ? 1
      : ((filteredSubjects.length - 1) ~/ _rowsPerPage) + 1;
    if (_classPage > classTotalPages) _classPage = classTotalPages;
    if (_subjectPage > subjectTotalPages) _subjectPage = subjectTotalPages;
    final classStart = (_classPage - 1) * _rowsPerPage;
    final subjectStart = (_subjectPage - 1) * _rowsPerPage;
    final pagedClassrooms = filteredClassrooms.skip(classStart).take(_rowsPerPage).toList();
    final pagedSubjects = filteredSubjects.skip(subjectStart).take(_rowsPerPage).toList();

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
                          'Configure années scolaires, matières et classes dans un flux rapide.',
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
                              icon: Icons.business_outlined,
                              label:
                                  'Établissement: ${selectedEtablissement?.name ?? 'Aucun'}',
                              maxWidth: 320,
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
                          if (isSuperAdmin) ...[
                            DropdownButtonFormField<int?>(
                              initialValue: selectedEtablissementId,
                              decoration: const InputDecoration(
                                labelText: 'Établissement actif',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                ...etablissements.map(
                                  (etab) => DropdownMenuItem<int?>(
                                    value: etab.id,
                                    child: Text(etab.name),
                                  ),
                                ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (value) async {
                                      if (value == null) {
                                        _showMessage('Sélectionne un établissement actif.');
                                        return;
                                      }
                                      final target = etablissements
                                          .where((etab) => etab.id == value)
                                          .cast<Etablissement?>()
                                          .firstWhere(
                                            (etab) => etab != null,
                                            orElse: () => null,
                                          );
                                      if (target != null) {
                                        await ref
                                            .read(etablissementProvider)
                                            .selectEtablissement(target);
                                      }
                                    },
                            ),
                            const SizedBox(height: 10),
                          ],
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
                  'Les matières sont créées par classe, avec code et coefficient indépendants selon la classe.',
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
                        final yearName =
                            yearById[_asInt(
                              classroom['academic_year'],
                            )]?['name'] ??
                            'Année ?';

                        return ListTile(
                          dense: true,
                          title: Text('${classroom['name']}'),
                          subtitle: Text(
                            '$yearName',
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Classes', style: textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: _saving ? null : _openClassroomForm,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter classe'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _classSearchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Rechercher une classe',
                  ),
                  onChanged: (value) => setState(() {
                    _classQuery = value;
                    _classPage = 1;
                  }),
                ),
                const SizedBox(height: 10),
                if (filteredClassrooms.isEmpty)
                  const Text('Aucune classe trouvée pour l’établissement actif.')
                else
                  ...pagedClassrooms.map((classroom) {
                    final yearName =
                        yearById[_asInt(classroom['academic_year'])]?['name'] ??
                        'Année ?';
                    final classId = _asInt(classroom['id']);
                    final subjectsCount =
                        _subjects.where((s) => _asInt(s['classroom']) == classId).length;

                    return Card(
                      child: ListTile(
                        title: Text('${classroom['name']}'),
                        subtitle: Text('$yearName • $subjectsCount matières'),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'view') {
                              _openClassroomDetails(classroom);
                            } else if (value == 'edit') {
                              _openEditClassroomForm(classroom);
                            } else if (value == 'delete') {
                              _confirmDeleteClassroom(classroom);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'view', child: Text('Afficher')),
                            PopupMenuItem(value: 'edit', child: Text('Modifier')),
                            PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                          ],
                        ),
                      ),
                    );
                  }),
                if (filteredClassrooms.isNotEmpty)
                  _buildPager(
                    page: _classPage,
                    totalPages: classTotalPages,
                    onPrevious: _classPage > 1
                        ? () => setState(() => _classPage -= 1)
                        : null,
                    onNext: _classPage < classTotalPages
                        ? () => setState(() => _classPage += 1)
                        : null,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('Matières', style: textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: _saving ? null : _openSubjectForm,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter matière'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: _subjectFilterClassroomId,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.filter_list),
                    labelText: 'Filtrer par classe',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Toutes les classes'),
                    ),
                    ..._classrooms.map(
                      (row) => DropdownMenuItem<int?>(
                        value: _asInt(row['id']),
                        child: Text('${row['name']}'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _subjectFilterClassroomId = value;
                      _subjectPage = 1;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _subjectSearchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Rechercher une matière',
                  ),
                  onChanged: (value) => setState(() {
                    _subjectQuery = value;
                    _subjectPage = 1;
                  }),
                ),
                const SizedBox(height: 10),
                if (filteredSubjects.isEmpty)
                  const Text('Aucune matière trouvée pour l’établissement actif.')
                else
                  ...pagedSubjects.map((subject) {
                    final className =
                        subject['classroom_name']?.toString().trim().isNotEmpty == true
                        ? subject['classroom_name'].toString()
                        : _classrooms
                                  .firstWhere(
                                    (row) =>
                                        _asInt(row['id']) == _asInt(subject['classroom']),
                                    orElse: () => <String, dynamic>{},
                                  )['name']
                                  ?.toString() ??
                              '-';
                    return Card(
                      child: ListTile(
                        title: Text('${subject['name']}'),
                        subtitle: Text(
                          'Code ${subject['code'] ?? '-'} • Coef ${subject['coefficient'] ?? '-'} • Classe $className',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'view') {
                              _openSubjectDetails(subject);
                            } else if (value == 'edit') {
                              _openEditSubjectForm(subject);
                            } else if (value == 'delete') {
                              _confirmDeleteSubject(subject);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'view', child: Text('Afficher')),
                            PopupMenuItem(value: 'edit', child: Text('Modifier')),
                            PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                          ],
                        ),
                      ),
                    );
                  }),
                if (filteredSubjects.isNotEmpty)
                  _buildPager(
                    page: _subjectPage,
                    totalPages: subjectTotalPages,
                    onPrevious: _subjectPage > 1
                        ? () => setState(() => _subjectPage -= 1)
                        : null,
                    onNext: _subjectPage < subjectTotalPages
                        ? () => setState(() => _subjectPage += 1)
                        : null,
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

  Widget _buildPager({
    required int page,
    required int totalPages,
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Page $page/$totalPages'),
          const SizedBox(width: 10),
          IconButton(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Précédent',
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Suivant',
          ),
        ],
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
        content: Text(
          message,
          style: isSuccess ? const TextStyle(color: Colors.white) : null,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
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
