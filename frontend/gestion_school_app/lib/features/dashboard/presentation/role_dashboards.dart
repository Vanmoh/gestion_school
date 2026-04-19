import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';

List<Map<String, dynamic>> _rows(dynamic data) {
  if (data is Map<String, dynamic> && data['results'] is List) {
    return (data['results'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
  if (data is List) {
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _FetchRowsResult {
  final List<Map<String, dynamic>> rows;
  final bool restricted;

  const _FetchRowsResult({required this.rows, required this.restricted});
}

Future<_FetchRowsResult> _safeGetRows(Dio dio, String path) async {
  try {
    final response = await dio.get(path);
    return _FetchRowsResult(rows: _rows(response.data), restricted: false);
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const _FetchRowsResult(rows: <Map<String, dynamic>>[], restricted: true);
    }
    return const _FetchRowsResult(rows: <Map<String, dynamic>>[], restricted: false);
  } catch (_) {
    return const _FetchRowsResult(rows: <Map<String, dynamic>>[], restricted: false);
  }
}

class _RoleMetric {
  final String label;
  final String value;

  const _RoleMetric({required this.label, required this.value});
}

class _RoleDashboardScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_RoleMetric> metrics;
  final Future<void> Function() onRefresh;
  final String? fallbackNote;

  const _RoleDashboardScaffold({
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.onRefresh,
    this.fallbackNote,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: 220,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metric.label, style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Text(
                            metric.value,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        ),
        if (fallbackNote != null) ...[
          const SizedBox(height: 10),
          Text(
            fallbackNote!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class SupervisorDashboardPage extends ConsumerStatefulWidget {
  const SupervisorDashboardPage({super.key});

  @override
  ConsumerState<SupervisorDashboardPage> createState() => _SupervisorDashboardPageState();
}

class _SupervisorDashboardPageState extends ConsumerState<SupervisorDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _students = 0;
  int _attendances = 0;
  int _incidentsOpen = 0;
  int _teacherEntries = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/students/'),
      _safeGetRows(dio, '/attendances/'),
      _safeGetRows(dio, '/discipline-incidents/'),
      _safeGetRows(dio, '/teacher-time-entries/'),
    ]);

    if (!mounted) return;
    setState(() {
      _students = results[0].rows.length;
      _attendances = results[1].rows.length;
      _incidentsOpen = results[2]
          .rows
          .where((row) => (row['status']?.toString() ?? 'open') == 'open')
          .length;
      _teacherEntries = results[3].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Dashboard Surveillant',
      subtitle: 'Suivi opérationnel quotidien de l\'établissement.',
      metrics: [
        _RoleMetric(label: 'Élèves suivis', value: '$_students'),
        _RoleMetric(label: 'Lignes absences/retards', value: '$_attendances'),
        _RoleMetric(label: 'Incidents ouverts', value: '$_incidentsOpen'),
        _RoleMetric(label: 'Pointages enseignants', value: '$_teacherEntries'),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class TeacherDashboardPage extends ConsumerStatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  ConsumerState<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends ConsumerState<TeacherDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _assignedClasses = 0;
  int _assignedSubjects = 0;
  int _slots = 0;
  int _openIncidents = 0;
  int _myEntries = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final authUser = ref.read(authControllerProvider).value;
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/teachers/'),
      _safeGetRows(dio, '/teacher-assignments/'),
      _safeGetRows(dio, '/teacher-schedule-slots/'),
      _safeGetRows(dio, '/discipline-incidents/'),
      _safeGetRows(dio, '/teacher-time-entries/'),
    ]);

    final teachers = results[0].rows;
    final assignments = results[1].rows;
    final slots = results[2].rows;
    final incidents = results[3].rows;
    final entries = results[4].rows;

    final teacher = teachers.firstWhere(
      (row) => _asInt(row['user']) == (authUser?.id ?? 0),
      orElse: () => <String, dynamic>{},
    );
    final teacherId = _asInt(teacher['id']);

    final ownAssignments = assignments
        .where((row) => _asInt(row['teacher']) == teacherId)
        .toList(growable: false);
    final ownAssignmentIds = ownAssignments
        .map((row) => _asInt(row['id']))
        .where((id) => id > 0)
        .toSet();
    final ownClassroomIds = ownAssignments
        .map((row) => _asInt(row['classroom']))
        .where((id) => id > 0)
        .toSet();
    final ownSubjectIds = ownAssignments
        .map((row) => _asInt(row['subject']))
        .where((id) => id > 0)
        .toSet();

    if (!mounted) return;
    setState(() {
      _assignedClasses = ownClassroomIds.length;
      _assignedSubjects = ownSubjectIds.length;
      _slots = slots
          .where((row) => ownAssignmentIds.contains(_asInt(row['assignment'])))
          .length;
      _openIncidents = incidents
          .where((row) => (row['status']?.toString() ?? 'open') == 'open')
          .length;
      _myEntries = entries.where((row) => _asInt(row['teacher']) == teacherId).length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Dashboard Enseignant',
      subtitle: 'Vue personnelle des classes, matières et actions pédagogiques.',
      metrics: [
        _RoleMetric(label: 'Classes affectées', value: '$_assignedClasses'),
        _RoleMetric(label: 'Matières affectées', value: '$_assignedSubjects'),
        _RoleMetric(label: 'Créneaux planifiés', value: '$_slots'),
        _RoleMetric(label: 'Incidents ouverts (vos classes)', value: '$_openIncidents'),
        _RoleMetric(label: 'Vos pointages', value: '$_myEntries'),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class AccountantDashboardPage extends ConsumerStatefulWidget {
  const AccountantDashboardPage({super.key});

  @override
  ConsumerState<AccountantDashboardPage> createState() => _AccountantDashboardPageState();
}

class _AccountantDashboardPageState extends ConsumerState<AccountantDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _payments = 0;
  int _fees = 0;
  int _payrolls = 0;
  int _expenses = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/payments/'),
      _safeGetRows(dio, '/fees/'),
      _safeGetRows(dio, '/teacher-payrolls/'),
      _safeGetRows(dio, '/expenses/'),
    ]);

    if (!mounted) return;
    setState(() {
      _payments = results[0].rows.length;
      _fees = results[1].rows.length;
      _payrolls = results[2].rows.length;
      _expenses = results[3].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Dashboard Comptable',
      subtitle: 'Pilotage financier opérationnel de l\'établissement.',
      metrics: [
        _RoleMetric(label: 'Paiements enregistrés', value: '$_payments'),
        _RoleMetric(label: 'Frais élèves', value: '$_fees'),
        _RoleMetric(label: 'Bulletins de paie enseignants', value: '$_payrolls'),
        _RoleMetric(label: 'Dépenses', value: '$_expenses'),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class ParentDashboardPage extends ConsumerStatefulWidget {
  const ParentDashboardPage({super.key});

  @override
  ConsumerState<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends ConsumerState<ParentDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _childrenGrades = 0;
  int _childrenAttendances = 0;
  int _childrenIncidents = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/grades/'),
      _safeGetRows(dio, '/attendances/'),
      _safeGetRows(dio, '/discipline-incidents/'),
    ]);

    if (!mounted) return;
    setState(() {
      _childrenGrades = results[0].rows.length;
      _childrenAttendances = results[1].rows.length;
      _childrenIncidents = results[2].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Dashboard Parent',
      subtitle: 'Suivi des informations scolaires liées à vos enfants.',
      metrics: [
        _RoleMetric(label: 'Notes visibles', value: '$_childrenGrades'),
        _RoleMetric(label: 'Absences/retards visibles', value: '$_childrenAttendances'),
        _RoleMetric(label: 'Incidents visibles', value: '$_childrenIncidents'),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class StudentDashboardPage extends ConsumerStatefulWidget {
  const StudentDashboardPage({super.key});

  @override
  ConsumerState<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends ConsumerState<StudentDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _myGrades = 0;
  int _myAttendances = 0;
  int _myIncidents = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/grades/'),
      _safeGetRows(dio, '/attendances/'),
      _safeGetRows(dio, '/discipline-incidents/'),
    ]);

    if (!mounted) return;
    setState(() {
      _myGrades = results[0].rows.length;
      _myAttendances = results[1].rows.length;
      _myIncidents = results[2].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Dashboard Élève',
      subtitle: 'Vue personnelle de votre progression et de votre suivi.',
      metrics: [
        _RoleMetric(label: 'Notes visibles', value: '$_myGrades'),
        _RoleMetric(label: 'Absences/retards', value: '$_myAttendances'),
        _RoleMetric(label: 'Incidents', value: '$_myIncidents'),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}
