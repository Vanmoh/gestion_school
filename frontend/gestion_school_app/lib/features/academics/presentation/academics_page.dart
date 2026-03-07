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

  Future<void> _post(
    String endpoint,
    Map<String, dynamic> data,
    String successMessage,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(endpoint, data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final yearById = {for (final y in _years) _asInt(y['id']): y};
    final levelById = {for (final l in _levels) _asInt(l['id']): l};
    final sectionById = {for (final s in _sections) _asInt(s['id']): s};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Gestion académique',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Années scolaires, niveaux, sections, classes et matières.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Année scolaire',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _yearNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom (ex: 2025-2026)',
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date début'),
                  subtitle: Text(_apiDate(_yearStart)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _yearStart,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _yearStart = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date fin'),
                  subtitle: Text(_apiDate(_yearEnd)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _yearEnd,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _yearEnd = picked);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _yearActive,
                  onChanged: (v) => setState(() => _yearActive = v),
                  title: const Text('Année active'),
                ),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _post('/academic-years/', {
                          'name': _yearNameController.text.trim(),
                          'start_date': _apiDate(_yearStart),
                          'end_date': _apiDate(_yearEnd),
                          'is_active': _yearActive,
                        }, 'Année scolaire créée'),
                  child: const Text('Créer année scolaire'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Niveaux, sections, matières',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _levelNameController,
                  decoration: const InputDecoration(
                    labelText: 'Niveau (ex: 6ème)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () => _post('/levels/', {
                          'name': _levelNameController.text.trim(),
                        }, 'Niveau créé'),
                  child: const Text('Créer niveau'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _sectionNameController,
                  decoration: const InputDecoration(
                    labelText: 'Section (ex: Collège)',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () => _post('/sections/', {
                          'name': _sectionNameController.text.trim(),
                        }, 'Section créée'),
                  child: const Text('Créer section'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectNameController,
                  decoration: const InputDecoration(labelText: 'Nom matière'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _subjectCodeController,
                  decoration: const InputDecoration(labelText: 'Code matière'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _subjectCoefController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Coefficient'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () => _post('/subjects/', {
                          'name': _subjectNameController.text.trim(),
                          'code': _subjectCodeController.text.trim(),
                          'coefficient':
                              double.tryParse(
                                _subjectCoefController.text.trim(),
                              ) ??
                              1,
                        }, 'Matière créée'),
                  child: const Text('Créer matière'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Créer une classe',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _classNameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom classe (ex: 6A)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedYearId,
                  decoration: const InputDecoration(
                    labelText: 'Année scolaire',
                  ),
                  items: _years
                      .map(
                        (y) => DropdownMenuItem<int>(
                          value: _asInt(y['id']),
                          child: Text('${y['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedYearId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedLevelId,
                  decoration: const InputDecoration(labelText: 'Niveau'),
                  items: _levels
                      .map(
                        (l) => DropdownMenuItem<int>(
                          value: _asInt(l['id']),
                          child: Text('${l['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedLevelId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedSectionId,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: _sections
                      .map(
                        (s) => DropdownMenuItem<int>(
                          value: _asInt(s['id']),
                          child: Text('${s['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSectionId = v),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _post('/classrooms/', {
                          'name': _classNameController.text.trim(),
                          'academic_year': _selectedYearId,
                          'level': _selectedLevelId,
                          'section': _selectedSectionId,
                        }, 'Classe créée'),
                  child: const Text('Créer classe'),
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
                Text(
                  'Résumé académique',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Années scolaires: ${_years.length}'),
                Text('Niveaux: ${_levels.length}'),
                Text('Sections: ${_sections.length}'),
                Text('Matières: ${_subjects.length}'),
                Text('Classes: ${_classrooms.length}'),
                const SizedBox(height: 8),
                if (_classrooms.isNotEmpty)
                  ..._classrooms
                      .take(8)
                      .map(
                        (c) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${c['name']}'),
                          subtitle: Text(
                            '${levelById[_asInt(c['level'])]?['name'] ?? 'Niveau ?'} • '
                            '${sectionById[_asInt(c['section'])]?['name'] ?? 'Section ?'} • '
                            '${yearById[_asInt(c['academic_year'])]?['name'] ?? 'Année ?'}',
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
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
