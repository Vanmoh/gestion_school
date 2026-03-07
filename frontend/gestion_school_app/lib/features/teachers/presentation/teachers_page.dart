import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class TeachersPage extends ConsumerStatefulWidget {
  const TeachersPage({super.key});

  @override
  ConsumerState<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends ConsumerState<TeachersPage> {
  final _employeeCodeController = TextEditingController();
  final _salaryController = TextEditingController();
  DateTime _hireDate = DateTime.now();

  int? _selectedTeacherUserId;
  int? _selectedTeacherId;
  int? _selectedSubjectId;
  int? _selectedClassroomId;

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _teacherUsers = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _assignments = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _employeeCodeController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);

    try {
      final results = await Future.wait([
        dio.get('/auth/users/', queryParameters: {'role': 'teacher'}),
        dio.get('/teachers/'),
        dio.get('/subjects/'),
        dio.get('/classrooms/'),
        dio.get('/teacher-assignments/'),
      ]);

      if (!mounted) return;

      setState(() {
        _teacherUsers = _extractRows(results[0].data);
        _teachers = _extractRows(results[1].data);
        _subjects = _extractRows(results[2].data);
        _classrooms = _extractRows(results[3].data);
        _assignments = _extractRows(results[4].data);

        _selectedTeacherUserId ??= _teacherUsers.isNotEmpty
            ? _asInt(_teacherUsers.first['id'])
            : null;
        _selectedTeacherId ??= _teachers.isNotEmpty
            ? _asInt(_teachers.first['id'])
            : null;
        _selectedSubjectId ??= _subjects.isNotEmpty
            ? _asInt(_subjects.first['id'])
            : null;
        _selectedClassroomId ??= _classrooms.isNotEmpty
            ? _asInt(_classrooms.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement enseignants: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createTeacherProfile() async {
    final userId = _selectedTeacherUserId;
    final employeeCode = _employeeCodeController.text.trim();
    final salary = double.tryParse(_salaryController.text.trim());

    if (userId == null || employeeCode.isEmpty || salary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complétez les champs enseignant.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(dioProvider)
          .post(
            '/teachers/',
            data: {
              'user': userId,
              'employee_code': employeeCode,
              'hire_date': _apiDate(_hireDate),
              'salary_base': salary,
            },
          );

      if (!mounted) return;
      _employeeCodeController.clear();
      _salaryController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil enseignant créé avec succès.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur création enseignant: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _createAssignment() async {
    final teacherId = _selectedTeacherId;
    final subjectId = _selectedSubjectId;
    final classroomId = _selectedClassroomId;

    if (teacherId == null || subjectId == null || classroomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez enseignant, matière et classe.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await ref
          .read(dioProvider)
          .post(
            '/teacher-assignments/',
            data: {
              'teacher': teacherId,
              'subject': subjectId,
              'classroom': classroomId,
            },
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Affectation créée avec succès.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur création affectation: $error')),
      );
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

    final teacherById = {for (final t in _teachers) _asInt(t['id']): t};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};
    final classroomById = {for (final c in _classrooms) _asInt(c['id']): c};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Gestion des enseignants',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Fiches enseignants, affectations matières/classes, suivi de base.',
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
                  'Créer un profil enseignant',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedTeacherUserId,
                  decoration: const InputDecoration(
                    labelText: 'Compte utilisateur (rôle enseignant)',
                  ),
                  items: _teacherUsers
                      .map(
                        (u) => DropdownMenuItem<int>(
                          value: _asInt(u['id']),
                          child: Text(_userLabel(u)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTeacherUserId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _employeeCodeController,
                  decoration: const InputDecoration(labelText: 'Code employé'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _salaryController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Salaire de base',
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date d\'embauche'),
                  subtitle: Text(_apiDate(_hireDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _hireDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _hireDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : _createTeacherProfile,
                  child: const Text('Créer enseignant'),
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
                  'Affecter une matière à une classe',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedTeacherId,
                  decoration: const InputDecoration(labelText: 'Enseignant'),
                  items: _teachers
                      .map(
                        (t) => DropdownMenuItem<int>(
                          value: _asInt(t['id']),
                          child: Text(
                            '${t['employee_code'] ?? 'Code ?'} (ID ${t['id']})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedTeacherId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedSubjectId,
                  decoration: const InputDecoration(labelText: 'Matière'),
                  items: _subjects
                      .map(
                        (s) => DropdownMenuItem<int>(
                          value: _asInt(s['id']),
                          child: Text('${s['code']} - ${s['name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedSubjectId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedClassroomId,
                  decoration: const InputDecoration(labelText: 'Classe'),
                  items: _classrooms
                      .map(
                        (c) => DropdownMenuItem<int>(
                          value: _asInt(c['id']),
                          child: Text('${c['name']} (ID ${c['id']})'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedClassroomId = v),
                ),
                const SizedBox(height: 10),
                FilledButton.tonal(
                  onPressed: _saving ? null : _createAssignment,
                  child: const Text('Créer affectation'),
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
                  'Affectations existantes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_assignments.isEmpty)
                  const Text('Aucune affectation enregistrée')
                else
                  ..._assignments.map((a) {
                    final teacher = teacherById[_asInt(a['teacher'])];
                    final subject = subjectById[_asInt(a['subject'])];
                    final classroom = classroomById[_asInt(a['classroom'])];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${subject?['code'] ?? 'Matière'} • ${classroom?['name'] ?? 'Classe'}',
                        ),
                        subtitle: Text(
                          'Enseignant: ${teacher?['employee_code'] ?? 'ID ${a['teacher']}'}',
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

  String _apiDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _userLabel(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString();
    final last = (user['last_name'] ?? '').toString();
    final full = '$first $last'.trim();
    final username = (user['username'] ?? '').toString();
    return full.isNotEmpty ? '$full ($username)' : username;
  }
}
