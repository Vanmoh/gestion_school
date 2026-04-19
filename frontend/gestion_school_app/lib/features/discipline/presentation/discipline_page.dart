import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';

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

  bool _isDisciplineReadOnlyRole() {
    final role = ref.read(authControllerProvider).value?.role;
    return role != 'super_admin' && role != 'director' && role != 'supervisor' && role != 'teacher';
  }

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
        dio.get('/teachers/'),
        dio.get('/teacher-assignments/'),
      ]);

      if (!mounted) return;
      final students = _extractRows(results[0].data);
      final incidents = _extractRows(results[1].data);
      final teachers = _extractRows(results[2].data);
      final assignments = _extractRows(results[3].data);

      final authUser = ref.read(authControllerProvider).value;
      final isTeacherUser = authUser?.role == 'teacher';

      List<Map<String, dynamic>> scopedStudents = students;
      List<Map<String, dynamic>> scopedIncidents = incidents;

      if (isTeacherUser && authUser != null) {
        final ownTeacher = teachers.firstWhere(
          (row) => _asInt(row['user']) == authUser.id,
          orElse: () => <String, dynamic>{},
        );
        final teacherId = _asInt(ownTeacher['id']);
        final allowedClassroomIds = assignments
            .where((row) => _asInt(row['teacher']) == teacherId)
            .map((row) => _asInt(row['classroom']))
            .where((id) => id > 0)
            .toSet();

        scopedStudents = students
            .where(
              (row) => allowedClassroomIds.contains(_asInt(row['classroom'])),
            )
            .toList();

        final visibleStudentIds = scopedStudents
            .map((row) => _asInt(row['id']))
            .where((id) => id > 0)
            .toSet();

        scopedIncidents = incidents
            .where((row) => visibleStudentIds.contains(_asInt(row['student'])))
            .toList();
      }

      setState(() {
        _students = scopedStudents;
        _incidents = scopedIncidents;
        final validIds = scopedStudents
            .map((row) => _asInt(row['id']))
            .where((id) => id > 0)
            .toSet();
        if (_selectedStudentId == null || !validIds.contains(_selectedStudentId)) {
          _selectedStudentId = scopedStudents.isNotEmpty
              ? _asInt(scopedStudents.first['id'])
              : null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur chargement discipline: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createIncident() async {
    if (_isDisciplineReadOnlyRole()) {
      _showMessage('Mode lecture seule: creation d\'incident non autorisee.');
      return;
    }

    final studentId = _selectedStudentId;
    final category = _categoryController.text.trim();
    final description = _descriptionController.text.trim();

    if (studentId == null || category.isEmpty || description.isEmpty) {
      _showMessage('Complétez les champs obligatoires.');
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
      _showMessage('Incident disciplinaire enregistré.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur enregistrement incident: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    const successColor = Color(0xFF197A43);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? successColor : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final studentById = {for (final s in _students) _asInt(s['id']): s};
    final authUser = ref.watch(authControllerProvider).value;
    final isTeacherUser = authUser?.role == 'teacher';
    final isTeacherReportingOnly = isTeacherUser;
    final isReadOnlyMode =
      authUser?.role != 'super_admin' &&
      authUser?.role != 'director' &&
      authUser?.role != 'supervisor' &&
      authUser?.role != 'teacher';

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Discipline', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Suivi des incidents disciplinaires et des sanctions.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (isTeacherUser) ...[
          const SizedBox(height: 6),
          Text(
            'Affichage limité aux élèves de vos classes. Vous pouvez déclarer un incident, sans appliquer de sanction ni le marquer comme traité.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (isReadOnlyMode) ...[
          const SizedBox(height: 6),
          Text(
            'Mode lecture seule: consultation uniquement pour ce profil.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
                    onChanged: isReadOnlyMode
                      ? null
                      : (value) =>
                      setState(() => _selectedStudentId = value),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date de l\'incident'),
                  subtitle: Text(_apiDate(_incidentDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: isReadOnlyMode
                      ? null
                      : () async {
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
                  enabled: !isReadOnlyMode,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descriptionController,
                  enabled: !isReadOnlyMode,
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
                    onChanged: isReadOnlyMode
                      ? null
                      : (value) =>
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
                    onChanged: (isReadOnlyMode || isTeacherReportingOnly)
                      ? null
                      : (value) =>
                      setState(() => _status = value ?? 'open'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _sanctionController,
                  enabled: !isReadOnlyMode && !isTeacherReportingOnly,
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
                  onChanged: (isReadOnlyMode || isTeacherReportingOnly)
                      ? null
                      : (value) => setState(() => _parentNotified = value),
                ),
                FilledButton(
                  onPressed: (_saving || isReadOnlyMode) ? null : _createIncident,
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
