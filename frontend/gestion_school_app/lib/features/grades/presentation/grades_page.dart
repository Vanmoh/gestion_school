import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  final _valueController = TextEditingController();
  final _termController = TextEditingController(text: 'T1');
  final _validationNotesController = TextEditingController();

  int? _selectedStudent;
  int? _selectedSubject;
  int? _selectedClassroom;
  int? _selectedAcademicYear;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _grades = [];
  Map<String, dynamic>? _validationStatus;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _termController.dispose();
    _validationNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/students/'),
        dio.get('/subjects/'),
        dio.get('/classrooms/'),
        dio.get('/academic-years/'),
        dio.get('/grades/'),
      ]);

      if (!mounted) return;

      setState(() {
        _students = _extractRows(results[0].data);
        _subjects = _extractRows(results[1].data);
        _classrooms = _extractRows(results[2].data);
        _years = _extractRows(results[3].data);
        _grades = _extractRows(results[4].data);

        _selectedStudent ??= _students.isNotEmpty
            ? _asInt(_students.first['id'])
            : null;
        _selectedSubject ??= _subjects.isNotEmpty
            ? _asInt(_subjects.first['id'])
            : null;
        _selectedClassroom ??= _classrooms.isNotEmpty
            ? _asInt(_classrooms.first['id'])
            : null;
        _selectedAcademicYear ??= _years.isNotEmpty
            ? _asInt(_years.first['id'])
            : null;
      });

      await _refreshValidationStatus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement notes: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createGrade() async {
    if (_isValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Période validée par la direction: saisie verrouillée.',
          ),
        ),
      );
      return;
    }

    final value = double.tryParse(_valueController.text.trim());
    if (_selectedStudent == null ||
        _selectedSubject == null ||
        _selectedClassroom == null ||
        _selectedAcademicYear == null ||
        (_termController.text.trim().isEmpty) ||
        value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complétez les champs de note.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(dioProvider)
          .post(
            '/grades/',
            data: {
              'student': _selectedStudent,
              'subject': _selectedSubject,
              'classroom': _selectedClassroom,
              'academic_year': _selectedAcademicYear,
              'term': _termController.text.trim(),
              'value': value,
            },
          );

      if (!mounted) return;
      _valueController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note enregistrée avec succès.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur enregistrement note: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _recalculateRanking() async {
    if (_isValidated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Période validée par la direction: recalcul verrouillé.',
          ),
        ),
      );
      return;
    }

    if (_selectedClassroom == null ||
        _selectedAcademicYear == null ||
        _termController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez classe, année et période.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            '/grades/recalculate_ranking/',
            data: {
              'classroom': _selectedClassroom,
              'academic_year': _selectedAcademicYear,
              'term': _termController.text.trim(),
            },
          );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Classement recalculé.')));
      await _refreshValidationStatus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur recalcul classement: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _refreshValidationStatus() async {
    final classroom = _selectedClassroom;
    final academicYear = _selectedAcademicYear;
    final term = _termController.text.trim();

    if (classroom == null || academicYear == null || term.isEmpty) {
      if (mounted) setState(() => _validationStatus = null);
      return;
    }

    try {
      final response = await ref
          .read(dioProvider)
          .get(
            '/grades/validation_status/',
            queryParameters: {
              'classroom': classroom,
              'academic_year': academicYear,
              'term': term,
            },
          );
      if (!mounted) return;
      setState(
        () =>
            _validationStatus = Map<String, dynamic>.from(response.data as Map),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _validationStatus = null);
    }
  }

  Future<void> _toggleValidation({required bool validate}) async {
    if (_selectedClassroom == null ||
        _selectedAcademicYear == null ||
        _termController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez classe, année et période.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            validate ? '/grades/validate_term/' : '/grades/unvalidate_term/',
            data: {
              'classroom': _selectedClassroom,
              'academic_year': _selectedAcademicYear,
              'term': _termController.text.trim(),
              if (validate) 'notes': _validationNotesController.text.trim(),
            },
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            validate
                ? 'Période validée par la direction.'
                : 'Validation retirée. Période réouverte.',
          ),
        ),
      );
      await _refreshValidationStatus();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur validation: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool get _isValidated => _validationStatus?['is_validated'] == true;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final studentById = {for (final s in _students) _asInt(s['id']): s};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Notes & Bulletins',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Saisie des notes, classement et validation direction.',
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
                  'Validation direction',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _isValidated
                      ? 'Statut: VALIDÉ • Par: ${(_validationStatus?['validated_by_name'] ?? '').toString().isEmpty ? 'N/A' : _validationStatus?['validated_by_name']} • Date: ${_validationStatus?['validated_at'] ?? '-'}'
                      : 'Statut: NON VALIDÉ',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _validationNotesController,
                  decoration: const InputDecoration(
                    labelText: 'Note de validation (optionnel)',
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _saving
                          ? null
                          : () => _toggleValidation(validate: true),
                      child: const Text('Valider période'),
                    ),
                    FilledButton.tonal(
                      onPressed: _saving
                          ? null
                          : () => _toggleValidation(validate: false),
                      child: const Text('Réouvrir période'),
                    ),
                  ],
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
                  'Saisie de note',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedStudent,
                  decoration: const InputDecoration(labelText: 'Élève'),
                  items: _students
                      .map(
                        (s) => DropdownMenuItem<int>(
                          value: _asInt(s['id']),
                          child: Text(
                            '${s['matricule'] ?? ''} • ${(s['user_full_name'] ?? '').toString().trim()}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedStudent = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedSubject,
                  decoration: const InputDecoration(labelText: 'Matière'),
                  items: _subjects
                      .map(
                        (s) => DropdownMenuItem<int>(
                          value: _asInt(s['id']),
                          child: Text('${s['code']} - ${s['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSubject = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedClassroom,
                  decoration: const InputDecoration(labelText: 'Classe'),
                  items: _classrooms
                      .map(
                        (c) => DropdownMenuItem<int>(
                          value: _asInt(c['id']),
                          child: Text('${c['name']} (ID ${c['id']})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedClassroom = v);
                    _refreshValidationStatus();
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedAcademicYear,
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
                  onChanged: (v) {
                    setState(() => _selectedAcademicYear = v);
                    _refreshValidationStatus();
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _termController,
                  decoration: const InputDecoration(
                    labelText: 'Période (ex: T1, T2)',
                  ),
                  onChanged: (_) => _refreshValidationStatus(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _valueController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Note / 20'),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: (_saving || _isValidated) ? null : _createGrade,
                  child: const Text('Enregistrer note'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: (_saving || _isValidated)
                      ? null
                      : _recalculateRanking,
                  child: const Text('Recalculer classement'),
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
                  'Dernières notes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_grades.isEmpty)
                  const Text('Aucune note enregistrée')
                else
                  ..._grades.take(30).map((g) {
                    final student = studentById[_asInt(g['student'])];
                    final subject = subjectById[_asInt(g['subject'])];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${student?['matricule'] ?? ''} • ${student?['user_full_name'] ?? 'Élève'}',
                        ),
                        subtitle: Text(
                          '${subject?['code'] ?? 'Matière'} • ${g['term']} • ${g['value']}/20',
                        ),
                      ),
                    );
                  }),
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
}
