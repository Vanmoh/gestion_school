import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class TeacherAttendancePage extends ConsumerStatefulWidget {
  const TeacherAttendancePage({super.key});

  @override
  ConsumerState<TeacherAttendancePage> createState() =>
      _TeacherAttendancePageState();
}

class _TeacherAttendancePageState extends ConsumerState<TeacherAttendancePage> {
  int? _selectedTeacherId;
  DateTime _selectedDate = DateTime.now();
  bool _isAbsent = true;
  bool _isLate = false;
  final _reasonController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _stats = {
    'month': '',
    'total_records': 0,
    'absences': 0,
    'lates': 0,
    'justifications': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(dioProvider);
      final responses = await Future.wait([
        dio.get('/teachers/'),
        dio.get('/teacher-attendances/'),
        dio.get('/teacher-attendances/monthly_stats/'),
      ]);

      final teachers = _extractRows(responses[0].data);
      final rows = _extractRows(responses[1].data);
      final stats = responses[2].data is Map<String, dynamic>
          ? Map<String, dynamic>.from(responses[2].data as Map)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _rows = rows;
        _stats = stats;
        _selectedTeacherId ??= teachers.isNotEmpty
            ? _asInt(teachers.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur chargement absences enseignants: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_selectedTeacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez un enseignant.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            '/teacher-attendances/',
            data: {
              'teacher': _selectedTeacherId,
              'date': _apiDate(_selectedDate),
              'is_absent': _isAbsent,
              'is_late': _isLate,
              'reason': _reasonController.text.trim(),
            },
          );

      if (!mounted) return;
      _reasonController.clear();
      setState(() {
        _selectedDate = DateTime.now();
        _isAbsent = true;
        _isLate = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Absence enseignant enregistrée.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur enregistrement: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final teacherById = {for (final t in _teachers) _asInt(t['id']): t};

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Absences enseignants',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Suivi des absences/retards des enseignants avec statistiques mensuelles.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 14,
              runSpacing: 10,
              children: [
                _stat('Mois', (_stats['month'] ?? '').toString()),
                _stat(
                  'Enregistrements',
                  (_stats['total_records'] ?? 0).toString(),
                ),
                _stat('Absences', (_stats['absences'] ?? 0).toString()),
                _stat('Retards', (_stats['lates'] ?? 0).toString()),
                _stat(
                  'Justificatifs',
                  (_stats['justifications'] ?? 0).toString(),
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
                  'Saisie absence/retard enseignant',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedTeacherId,
                  decoration: const InputDecoration(labelText: 'Enseignant'),
                  items: _teachers
                      .map(
                        (row) => DropdownMenuItem<int>(
                          value: _asInt(row['id']),
                          child: Text(_teacherLabel(row)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedTeacherId = value),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(_apiDate(_selectedDate)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isAbsent,
                  title: const Text('Absent'),
                  onChanged: (value) => setState(() => _isAbsent = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isLate,
                  title: const Text('Retard'),
                  onChanged: (value) => setState(() => _isLate = value),
                ),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Motif / remarque',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _saving ? null : _create,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer'),
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
                  'Historique',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  const Text('Aucune donnée')
                else
                  ..._rows.take(40).map((item) {
                    final teacher = teacherById[_asInt(item['teacher'])];
                    return Card(
                      child: ListTile(
                        title: Text(_teacherLabel(teacher ?? {})),
                        subtitle: Text(
                          '${item['date']} • ${item['is_absent'] == true ? 'Absent' : 'Présent'} • ${item['is_late'] == true ? 'Retard' : 'À l\'heure'}',
                        ),
                        trailing:
                            (item['reason']?.toString().isNotEmpty ?? false)
                            ? Tooltip(
                                message: item['reason'].toString(),
                                child: const Icon(Icons.info_outline),
                              )
                            : null,
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

  Widget _stat(String label, String value) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _teacherLabel(Map<String, dynamic> row) {
    final employee =
        row['employee_code']?.toString() ??
        row['teacher_employee_code']?.toString() ??
        'N/A';
    final user = row['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(row['user'] as Map)
        : const <String, dynamic>{};
    final first = user['first_name']?.toString() ?? '';
    final last = user['last_name']?.toString() ?? '';
    final fullName = '$first $last'.trim();
    final fallback = row['teacher_full_name']?.toString() ?? '';
    final name = fullName.isNotEmpty
        ? fullName
        : (fallback.isNotEmpty ? fallback : 'Enseignant ${row['id'] ?? ''}');
    return '$employee • $name';
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
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
