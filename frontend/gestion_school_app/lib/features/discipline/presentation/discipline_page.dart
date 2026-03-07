import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class DisciplinePage extends ConsumerStatefulWidget {
  const DisciplinePage({super.key});

  @override
  ConsumerState<DisciplinePage> createState() => _DisciplinePageState();
}

class _DisciplinePageState extends ConsumerState<DisciplinePage> {
  final _categoryController = TextEditingController(text: 'Indiscipline');
  final _descriptionController = TextEditingController();
  final _sanctionController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _incidents = [];

  int? _selectedStudentId;
  DateTime _incidentDate = DateTime.now();
  String _severity = 'medium';
  String _status = 'open';
  bool _parentNotified = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _descriptionController.dispose();
    _sanctionController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/students/'),
        dio.get('/discipline-incidents/'),
      ]);

      if (!mounted) return;
      final students = _extractRows(results[0].data);
      final incidents = _extractRows(results[1].data);

      setState(() {
        _students = students;
        _incidents = incidents;
        _selectedStudentId ??= students.isNotEmpty
            ? _asInt(students.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement discipline: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createIncident() async {
    final studentId = _selectedStudentId;
    final category = _categoryController.text.trim();
    final description = _descriptionController.text.trim();

    if (studentId == null || category.isEmpty || description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complétez les champs obligatoires.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            '/discipline-incidents/',
            data: {
              'student': studentId,
              'incident_date': _apiDate(_incidentDate),
              'category': category,
              'description': description,
              'severity': _severity,
              'sanction': _sanctionController.text.trim(),
              'status': _status,
              'parent_notified': _parentNotified,
            },
          );

      if (!mounted) return;
      _descriptionController.clear();
      _sanctionController.clear();
      _severity = 'medium';
      _status = 'open';
      _parentNotified = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incident disciplinaire enregistré.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur enregistrement incident: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final studentById = {for (final s in _students) _asInt(s['id']): s};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Discipline', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Suivi des incidents disciplinaires et des sanctions.',
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
                  'Déclarer un incident',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedStudentId,
                  decoration: const InputDecoration(labelText: 'Élève'),
                  items: _students
                      .map(
                        (row) => DropdownMenuItem<int>(
                          value: _asInt(row['id']),
                          child: Text(_studentLabel(row)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedStudentId = value),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date de l\'incident'),
                  subtitle: Text(_apiDate(_incidentDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _incidentDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _incidentDate = picked);
                  },
                ),
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Description *'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _severity,
                  decoration: const InputDecoration(labelText: 'Gravité'),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Faible')),
                    DropdownMenuItem(value: 'medium', child: Text('Moyenne')),
                    DropdownMenuItem(value: 'high', child: Text('Élevée')),
                  ],
                  onChanged: (value) =>
                      setState(() => _severity = value ?? 'medium'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Statut'),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('Ouvert')),
                    DropdownMenuItem(value: 'resolved', child: Text('Traité')),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'open'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _sanctionController,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Sanction (optionnel)',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _parentNotified,
                  title: const Text('Parent informé'),
                  onChanged: (value) => setState(() => _parentNotified = value),
                ),
                FilledButton(
                  onPressed: _saving ? null : _createIncident,
                  child: const Text('Enregistrer incident'),
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
                  'Incidents récents',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_incidents.isEmpty)
                  const Text('Aucun incident enregistré.')
                else
                  ..._incidents.take(30).map((incident) {
                    final student = studentById[_asInt(incident['student'])];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${incident['category'] ?? 'Incident'} • ${_severityLabel(incident['severity']?.toString() ?? '')}',
                        ),
                        subtitle: Text(
                          '${_studentLabel(student ?? {})}\n${incident['description'] ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text((incident['incident_date'] ?? '').toString()),
                            const SizedBox(height: 4),
                            Text(
                              _statusLabel(
                                incident['status']?.toString() ?? '',
                              ),
                            ),
                          ],
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

  String _studentLabel(Map<String, dynamic> row) {
    final matricule = row['matricule']?.toString() ?? 'N/A';
    final fullName = row['user_full_name']?.toString() ?? '';
    final label = fullName.isEmpty ? 'Élève ${row['id'] ?? ''}' : fullName;
    return '$matricule • $label';
  }

  String _severityLabel(String value) {
    switch (value) {
      case 'low':
        return 'Faible';
      case 'high':
        return 'Élevée';
      default:
        return 'Moyenne';
    }
  }

  String _statusLabel(String value) {
    return value == 'resolved' ? 'Traité' : 'Ouvert';
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

  String _apiDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
