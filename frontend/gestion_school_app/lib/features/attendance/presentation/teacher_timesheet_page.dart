import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../auth/presentation/auth_controller.dart';
import '../../../core/providers/navigation_intents.dart';
import '../../payments/presentation/payments_controller.dart';

enum _SummaryPeriod { day, week, month }

enum _SummaryScope { singleTeacher, allTeachers }

enum _SummarySortColumn {
  date,
  teacher,
  checkIn,
  checkOut,
  hours,
  late,
  auto,
}

class TeacherTimesheetPage extends ConsumerStatefulWidget {
  const TeacherTimesheetPage({super.key});

  @override
  ConsumerState<TeacherTimesheetPage> createState() =>
      _TeacherTimesheetPageState();
}

class _TeacherTimesheetPageState extends ConsumerState<TeacherTimesheetPage> {
  int? _selectedTeacherId;
  DateTime _entryDate = DateTime.now();
  TimeOfDay _checkIn = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _checkOut = const TimeOfDay(hour: 10, minute: 0);
  bool _forgotCheckout = false;
  bool _loading = true;
  bool _saving = false;

  final _notesController = TextEditingController();
  final _dateController = TextEditingController();

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _timeEntries = [];

  @override
  void initState() {
    super.initState();
    _dateController.text = _toApiDate(_entryDate);
    Future<void>.microtask(_loadData);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  bool _canAccess(String? role) {
    return role == 'super_admin' || role == 'supervisor' || role == 'director';
  }

  bool _isReadOnlyRole(String? role) {
    return role == 'director';
  }

  String _normalizePointageBusinessMessage(String raw) {
    final normalized = raw.trim();
    final lower = normalized.toLowerCase();

    if (lower.contains('dimanche')) {
      return 'Pointage refuse: le dimanche est interdit. Choisissez un jour autorise (lundi a samedi).';
    }

    if (lower.contains("aucun creneau") || lower.contains("emploi du temps")) {
      return 'Pointage bloque: aucun creneau d\'emploi du temps pour cet enseignant a cette date. Configurez le planning du jour puis reessayez.';
    }

    return normalized;
  }

  String _extractApiErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return _normalizePointageBusinessMessage(
              value.map((item) => item.toString()).join(' | '),
            );
          }
          if (value is String && value.trim().isNotEmpty) {
            return _normalizePointageBusinessMessage(value);
          }
        }
      }
      if (data is List && data.isNotEmpty) {
        return _normalizePointageBusinessMessage(
          data.map((item) => item.toString()).join(' | '),
        );
      }
      if (data is String && data.trim().isNotEmpty) {
        return _normalizePointageBusinessMessage(data);
      }
      return error.message ?? error.toString();
    }
    return error.toString();
  }

  String _toApiDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _uiDate(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  String _toApiTime(TimeOfDay value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m:00';
  }

  int _toMinutes(TimeOfDay value) {
    return value.hour * 60 + value.minute;
  }

  String _time24(TimeOfDay value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _teacherLabel(Map<String, dynamic> row) {
    final fullName = (row['user_full_name']?.toString().trim() ?? '');
    final code = (row['employee_code']?.toString().trim() ?? '');
    final name = fullName.isNotEmpty ? fullName : 'Enseignant #${row['id']}';
    return '$name${code.isNotEmpty ? ' ($code)' : ''}';
  }

  String _summaryPeriodLabel(_SummaryPeriod period) {
    switch (period) {
      case _SummaryPeriod.day:
        return 'Jour';
      case _SummaryPeriod.week:
        return 'Semaine';
      case _SummaryPeriod.month:
        return 'Mois';
    }
  }

  Future<void> _openSummaryDialog() async {
    if (_timeEntries.isEmpty) {
      _showMessage('Aucune donnee de presence a analyser pour le moment.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _TimesheetSummaryDialog(
          teachers: _teachers,
          entries: _timeEntries,
          teacherLabelBuilder: _teacherLabel,
          periodLabelBuilder: _summaryPeriodLabel,
          onInfo: (message) => _showMessage(message, isSuccess: true),
        );
      },
    );
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(paymentsRepositoryProvider);
      final results = await Future.wait([
        repo.fetchTeachers(),
        repo.fetchTeacherTimeEntries(),
      ]);

      if (!mounted) return;

      setState(() {
        _teachers = results[0] as List<Map<String, dynamic>>;
        _timeEntries = results[1] as List<Map<String, dynamic>>;
        _selectedTeacherId ??= _teachers.isNotEmpty
            ? (_teachers.first['id'] as num?)?.toInt()
            : null;
      });
    } catch (error) {
      _showMessage('Erreur chargement emargement: ${_extractApiErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTimeEntry() async {
    final role = ref.read(authControllerProvider).value?.role;
    if (_isReadOnlyRole(role)) {
      _showMessage(
        'Acces refuse: le role Directeur est en lecture seule sur Emargement enseignants.',
      );
      return;
    }

    final teacherId = _selectedTeacherId;
    if (teacherId == null) {
      _showMessage('Selectionnez un enseignant.');
      return;
    }

    if (!_forgotCheckout) {
      if (_toMinutes(_checkOut) <= _toMinutes(_checkIn)) {
        _showMessage("L'heure de sortie doit etre apres l'heure d'entree.");
        return;
      }
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(paymentsRepositoryProvider)
          .createTeacherTimeEntry(
            teacherId: teacherId,
            entryDate: _toApiDate(_entryDate),
            checkInTime: _toApiTime(_checkIn),
            checkOutTime: _forgotCheckout ? null : _toApiTime(_checkOut),
            notes: _notesController.text.trim(),
          );

      if (!mounted) return;
      _notesController.clear();
      setState(() => _forgotCheckout = false);
      _showMessage('Pointage enregistre avec succes.', isSuccess: true);
      await _loadData();
    } catch (error) {
      final details = _extractApiErrorMessage(error);
      final lower = details.toLowerCase();
      final hasPlanningBlock = lower.contains('aucun creneau') ||
          lower.contains('emploi du temps');
      _showMessage(
        'Erreur pointage: $details',
        actionLabel: hasPlanningBlock ? 'Ouvrir emploi du temps' : null,
        onAction: hasPlanningBlock
          ? () => ref.read(adminShellNavigationKeyProvider.notifier).state = 'timetable'
            : null,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(
    String text, {
    bool isSuccess = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
          backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction,
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(authControllerProvider).value?.role;
    final isReadOnlyRole = _isReadOnlyRole(role);
    if (!_canAccess(role)) {
      return const Center(
        child: Text('Acces reserve au super admin, au surveillant et au directeur.'),
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Emargement enseignants',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Saisie du pointage entree/sortie des enseignants. La paie reste dans le module Finances.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (isReadOnlyRole) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF1C27D)),
            ),
            child: const Text(
              'Mode lecture seule: le role Directeur peut consulter, mais ne peut pas enregistrer de pointage.',
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _openSummaryDialog,
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Afficher la liste des presences'),
            ),
            FilledButton.tonalIcon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Nouveau pointage',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 380,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedTeacherId,
                        decoration: const InputDecoration(
                          labelText: 'Enseignant',
                        ),
                        items: _teachers
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: (row['id'] as num?)?.toInt(),
                                child: Text(_teacherLabel(row)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setState(() => _selectedTeacherId = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: TextField(
                        controller: _dateController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Date pointage',
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _entryDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null && mounted) {
                            setState(() {
                              _entryDate = picked;
                              _dateController.text = _toApiDate(_entryDate);
                            });
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _checkIn,
                          );
                          if (picked != null && mounted) {
                            setState(() => _checkIn = picked);
                          }
                        },
                        icon: const Icon(Icons.login_rounded),
                        label: Text('Entree ${_time24(_checkIn)}'),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: OutlinedButton.icon(
                        onPressed: _forgotCheckout
                            ? null
                            : () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _checkOut,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _checkOut = picked);
                                }
                              },
                        icon: const Icon(Icons.logout_rounded),
                        label: Text('Sortie ${_time24(_checkOut)}'),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: _forgotCheckout,
                        title: const Text('Sortie oubliee (auto)'),
                        onChanged: (value) {
                          setState(() => _forgotCheckout = value ?? false);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 420,
                  child: TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optionnel)',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _createTimeEntry,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.access_time_filled_outlined),
                  label: const Text('Enregistrer pointage'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Derniers pointages (${_timeEntries.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_timeEntries.isEmpty)
                  const Text('Aucun pointage enseignant enregistre.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Enseignant')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Entree')),
                        DataColumn(label: Text('Sortie')),
                        DataColumn(label: Text('Auto')),
                        DataColumn(label: Text('Heures')),
                      ],
                      rows: _timeEntries.take(40).map((row) {
                        return DataRow(
                          cells: [
                            DataCell(Text(row['teacher_full_name']?.toString() ?? '-')),
                            DataCell(Text(_uiDate(row['entry_date']))),
                            DataCell(Text(row['check_in_time']?.toString() ?? '-')),
                            DataCell(Text(row['check_out_time']?.toString() ?? '-')),
                            DataCell(Text(row['is_auto_closed'] == true ? 'Oui' : 'Non')),
                            DataCell(Text(row['worked_hours']?.toString() ?? '0')),
                          ],
                        );
                      }).toList(growable: false),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimesheetSummaryDialog extends StatefulWidget {
  final List<Map<String, dynamic>> teachers;
  final List<Map<String, dynamic>> entries;
  final String Function(Map<String, dynamic>) teacherLabelBuilder;
  final String Function(_SummaryPeriod) periodLabelBuilder;
  final void Function(String message) onInfo;

  const _TimesheetSummaryDialog({
    required this.teachers,
    required this.entries,
    required this.teacherLabelBuilder,
    required this.periodLabelBuilder,
    required this.onInfo,
  });

  @override
  State<_TimesheetSummaryDialog> createState() => _TimesheetSummaryDialogState();
}

class _TimesheetSummaryDialogState extends State<_TimesheetSummaryDialog> {
  _SummaryPeriod _period = _SummaryPeriod.day;
  _SummaryScope _scope = _SummaryScope.allTeachers;
  _SummarySortColumn _sortColumn = _SummarySortColumn.date;
  bool _sortAscending = false;
  int? _selectedTeacherId;
  DateTime _anchorDate = DateTime.now();
  String _searchTerm = '';
  bool _onlyAnomalies = false;
  bool _isExporting = false;
  String _exportingLabel = '';
  int _rightPaneTab = 0;
  final ScrollController _tableVerticalController = ScrollController();
  final ScrollController _tableHorizontalController = ScrollController();

  @override
  void initState() {
    super.initState();
    _anchorDate = _latestEntryDate();
  }

  @override
  void dispose() {
    _tableVerticalController.dispose();
    _tableHorizontalController.dispose();
    super.dispose();
  }

  void _setExporting(bool value, {String label = ''}) {
    if (!mounted) return;
    setState(() {
      _isExporting = value;
      _exportingLabel = value ? label : '';
    });
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    final normalized = value?.toString().trim() ?? '';
    if (normalized.isEmpty) return 0;
    final parsedDouble = double.tryParse(normalized.replaceAll(',', '.'));
    if (parsedDouble != null) return parsedDouble.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _entryDate(Map<String, dynamic> row) {
    final raw = row['entry_date']?.toString() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _teacherNameForRow(Map<String, dynamic> row) {
    final name = (row['teacher_full_name']?.toString() ?? '').trim();
    if (name.isNotEmpty) return name;
    final code = (row['teacher_employee_code']?.toString() ?? '').trim();
    if (code.isNotEmpty) return code;
    return 'Enseignant #${row['teacher'] ?? '-'}';
  }

  List<Map<String, dynamic>> _recentEntriesForTeacher(int teacherId, {int limit = 7}) {
    final rows = widget.entries.where((entry) => _asInt(entry['teacher']) == teacherId).toList();
    rows.sort((a, b) {
      final dateA = _entryDate(a) ?? DateTime(1970);
      final dateB = _entryDate(b) ?? DateTime(1970);
      final cmpDate = dateB.compareTo(dateA);
      if (cmpDate != 0) return cmpDate;
      final inA = a['check_in_time']?.toString() ?? '';
      final inB = b['check_in_time']?.toString() ?? '';
      return inB.compareTo(inA);
    });
    return rows.take(limit).toList(growable: false);
  }

  Future<void> _showRowDetails(Map<String, dynamic> row) async {
    final teacherId = _asInt(row['teacher']);
    final teacherName = _teacherNameForRow(row);
    final teacherCode = row['teacher_employee_code']?.toString().trim() ?? '-';
    final notes = row['notes']?.toString().trim() ?? '';
    final recentRows = _recentEntriesForTeacher(teacherId, limit: 7);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 760,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Details pointage enseignant',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text('Enseignant: $teacherName'),
                      Text('Code: $teacherCode'),
                      Text('Date: ${_uiDate(row['entry_date'])}'),
                      Text('Entree: ${row['check_in_time']?.toString() ?? '-'}'),
                      Text('Sortie: ${row['check_out_time']?.toString() ?? '-'}'),
                      Text('Heures: ${_f2(_asDouble(row['worked_hours']))} h'),
                      Text('Retard: ${_asInt(row['late_minutes'])} min'),
                      Text('Auto-fermeture: ${row['is_auto_closed'] == true ? 'Oui' : 'Non'}'),
                    ],
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Note: $notes'),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Mini-resume des 7 derniers pointages',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: recentRows.isEmpty
                        ? const Text('Aucun historique disponible.')
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Date')),
                                DataColumn(label: Text('Entree')),
                                DataColumn(label: Text('Sortie')),
                                DataColumn(label: Text('Heures')),
                                DataColumn(label: Text('Retard')),
                                DataColumn(label: Text('Auto')),
                              ],
                              rows: recentRows.map((recent) {
                                return DataRow(cells: [
                                  DataCell(Text(_uiDate(recent['entry_date']))),
                                  DataCell(Text(recent['check_in_time']?.toString() ?? '-')),
                                  DataCell(Text(recent['check_out_time']?.toString() ?? '-')),
                                  DataCell(Text('${_f2(_asDouble(recent['worked_hours']))} h')),
                                  DataCell(Text('${_asInt(recent['late_minutes'])} min')),
                                  DataCell(Text(recent['is_auto_closed'] == true ? 'Oui' : 'Non')),
                                ]);
                              }).toList(growable: false),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  DateTime _dayStart(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _weekStart(DateTime value) {
    final day = _dayStart(value);
    final shift = day.weekday - DateTime.monday;
    return day.subtract(Duration(days: shift));
  }

  DateTime _monthStart(DateTime value) {
    return DateTime(value.year, value.month, 1);
  }

  DateTime _latestEntryDate({int? teacherId}) {
    DateTime? latest;
    for (final row in widget.entries) {
      if (teacherId != null && _asInt(row['teacher']) != teacherId) {
        continue;
      }
      final d = _entryDate(row);
      if (d == null) {
        continue;
      }
      if (latest == null || d.isAfter(latest)) {
        latest = d;
      }
    }
    return latest == null ? _dayStart(DateTime.now()) : _dayStart(latest);
  }

  String? _lastEntryLabel({int? teacherId}) {
    DateTime? latest;
    for (final row in widget.entries) {
      if (teacherId != null && _asInt(row['teacher']) != teacherId) {
        continue;
      }
      final d = _entryDate(row);
      if (d == null) {
        continue;
      }
      if (latest == null || d.isAfter(latest)) {
        latest = d;
      }
    }
    if (latest == null) {
      return null;
    }
    return DateFormat('dd/MM/yyyy').format(latest);
  }

  ({DateTime start, DateTime end}) _activeRange() {
    switch (_period) {
      case _SummaryPeriod.day:
        final start = _dayStart(_anchorDate);
        return (start: start, end: start);
      case _SummaryPeriod.week:
        final start = _weekStart(_anchorDate);
        return (start: start, end: start.add(const Duration(days: 6)));
      case _SummaryPeriod.month:
        final start = _monthStart(_anchorDate);
        final next = start.month == 12
            ? DateTime(start.year + 1, 1, 1)
            : DateTime(start.year, start.month + 1, 1);
        return (start: start, end: next.subtract(const Duration(days: 1)));
    }
  }

  String _rangeLabel(({DateTime start, DateTime end}) range) {
    String fmt(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    if (range.start == range.end) {
      return fmt(range.start);
    }
    return '${fmt(range.start)} - ${fmt(range.end)}';
  }

  String _uiDate(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  int _clockMinutes(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.length < 5) return -1;
    final parts = raw.substring(0, 5).split(':');
    if (parts.length != 2) return -1;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return -1;
    return h * 60 + m;
  }

  bool _isAnomalyRow(Map<String, dynamic> row) {
    final late = _asInt(row['late_minutes']);
    final auto = row['is_auto_closed'] == true;
    final hours = _asDouble(row['worked_hours']);
    final checkIn = _clockMinutes(row['check_in_time']);
    final checkOut = _clockMinutes(row['check_out_time']);
    final missingOut = (row['check_out_time']?.toString().trim() ?? '').isEmpty;
    final invalidOrder = checkIn >= 0 && checkOut >= 0 && checkOut <= checkIn;

    return auto || late > 15 || missingOut || hours <= 0 || invalidOrder;
  }

  bool _isLateStrictRow(Map<String, dynamic> row) {
    return _asInt(row['late_minutes']) > 15;
  }

  Color? _rowHighlightColor(Map<String, dynamic> row) {
    if (_isLateStrictRow(row)) {
      return const Color(0xFFFFE5E5);
    }
    if (_isAnomalyRow(row)) {
      return const Color(0xFFFFF1F0);
    }
    return null;
  }

  TextStyle? _rowTextStyle(Map<String, dynamic> row) {
    if (_isLateStrictRow(row)) {
      return const TextStyle(
        color: Color(0xFFB00020),
        fontWeight: FontWeight.w600,
      );
    }
    return null;
  }

  int _compareRowsBySort(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    _SummarySortColumn column,
  ) {
    switch (column) {
      case _SummarySortColumn.date:
        final ad = _entryDate(a) ?? DateTime(1970);
        final bd = _entryDate(b) ?? DateTime(1970);
        return ad.compareTo(bd);
      case _SummarySortColumn.teacher:
        return _teacherNameForRow(a).compareTo(_teacherNameForRow(b));
      case _SummarySortColumn.checkIn:
        return _clockMinutes(a['check_in_time']).compareTo(_clockMinutes(b['check_in_time']));
      case _SummarySortColumn.checkOut:
        return _clockMinutes(a['check_out_time']).compareTo(_clockMinutes(b['check_out_time']));
      case _SummarySortColumn.hours:
        return _asDouble(a['worked_hours']).compareTo(_asDouble(b['worked_hours']));
      case _SummarySortColumn.late:
        return _asInt(a['late_minutes']).compareTo(_asInt(b['late_minutes']));
      case _SummarySortColumn.auto:
        final av = a['is_auto_closed'] == true ? 1 : 0;
        final bv = b['is_auto_closed'] == true ? 1 : 0;
        return av.compareTo(bv);
    }
  }

  List<Map<String, dynamic>> _sortRows(List<Map<String, dynamic>> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final cmp = _compareRowsBySort(a, b, _sortColumn);
      if (cmp != 0) {
        return _sortAscending ? cmp : -cmp;
      }
      final tie = _compareRowsBySort(a, b, _SummarySortColumn.date);
      return _sortAscending ? tie : -tie;
    });
    return sorted;
  }

  void _setSort(_SummarySortColumn column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _sortAscending = ascending;
    });
  }

  ({DateTime start, DateTime end}) _previousRange(({DateTime start, DateTime end}) range) {
    switch (_period) {
      case _SummaryPeriod.day:
        final prev = range.start.subtract(const Duration(days: 1));
        return (start: prev, end: prev);
      case _SummaryPeriod.week:
        return (
          start: range.start.subtract(const Duration(days: 7)),
          end: range.end.subtract(const Duration(days: 7)),
        );
      case _SummaryPeriod.month:
        final prevEnd = DateTime(range.start.year, range.start.month, 1).subtract(const Duration(days: 1));
        final prevStart = DateTime(prevEnd.year, prevEnd.month, 1);
        return (start: prevStart, end: prevEnd);
    }
  }

  String _signed(double value, {int digits = 2}) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(digits)}';
  }

  String _hoursDeltaLabel(double currentHours, double previousHours) {
    return '${_f2(currentHours)} h';
  }

  String _hoursDeltaDetails(double currentHours, double previousHours) {
    final delta = currentHours - previousHours;
    if (currentHours <= 0 && previousHours <= 0) {
      return 'N: 0.00 h | N-1: 0.00 h';
    }

    if (previousHours <= 0) {
      return 'N-1: 0.00 h | Δ ${_signed(delta)} h (nouvelle activite)';
    }

    final pct = (delta / previousHours) * 100;
    return 'N-1: ${_f2(previousHours)} h | Δ ${_signed(delta)} h (${_signed(pct, digits: 1)}%)';
  }

  Widget _kpiComparisonCard(String label, String value, String details) {
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            details,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filteredRowsForRange(({DateTime start, DateTime end}) range) {
    final start = range.start;
    final end = range.end;
    final search = _searchTerm.trim().toLowerCase();

    final rows = widget.entries.where((row) {
      final entryDate = _entryDate(row);
      if (entryDate == null) return false;
      final day = _dayStart(entryDate);
      if (day.isBefore(start) || day.isAfter(end)) return false;

      if (_scope == _SummaryScope.singleTeacher && _selectedTeacherId != null) {
        if (_asInt(row['teacher']) != _selectedTeacherId) return false;
      }

      if (search.isNotEmpty) {
        final teacher = _teacherNameForRow(row).toLowerCase();
        final code = (row['teacher_employee_code']?.toString() ?? '').toLowerCase();
        if (!teacher.contains(search) && !code.contains(search)) {
          return false;
        }
      }

      if (_onlyAnomalies && !_isAnomalyRow(row)) {
        return false;
      }

      return true;
    }).toList(growable: false);

    return rows;
  }

  List<Map<String, dynamic>> _filteredRows() {
    return _filteredRowsForRange(_activeRange());
  }

  Map<String, dynamic> _kpi(List<Map<String, dynamic>> rows) {
    final totalHours = rows.fold<double>(
      0,
      (sum, row) => sum + _asDouble(row['worked_hours']),
    );
    final autoClosed = rows.where((row) => row['is_auto_closed'] == true).length;
    final lateStrict = rows.where((row) => _asInt(row['late_minutes']) > 15).length;
    final teachers = rows.map((row) => _asInt(row['teacher'])).where((id) => id > 0).toSet().length;
    return {
      'rows': rows.length,
      'hours': totalHours,
      'autoClosed': autoClosed,
      'lateStrict': lateStrict,
      'teachers': teachers,
    };
  }

  Map<String, double> _hoursByTeacher(List<Map<String, dynamic>> rows) {
    final out = <String, double>{};
    for (final row in rows) {
      final name = _teacherNameForRow(row);
      out[name] = (out[name] ?? 0) + _asDouble(row['worked_hours']);
    }
    return out;
  }

  Map<String, double> _hoursByDay(List<Map<String, dynamic>> rows) {
    final out = <String, double>{};
    for (final row in rows) {
      final d = _entryDate(row);
      if (d == null) continue;
      final key = DateFormat('yyyy-MM-dd').format(_dayStart(d));
      out[key] = (out[key] ?? 0) + _asDouble(row['worked_hours']);
    }
    return out;
  }

  String _csvEscape(String input) {
    final needsQuote = input.contains(',') || input.contains('"') || input.contains('\n');
    if (!needsQuote) return input;
    return '"${input.replaceAll('"', '""')}"';
  }

  String _f2(double value) => NumberFormat('0.00').format(value);

  String _buildCsv(List<Map<String, dynamic>> rows) {
    final buffer = StringBuffer();
    buffer.writeln('date,enseignant,code,entree,sortie,heures,retard_min,auto_ferme,motif_auto');
    for (final row in rows) {
      final date = row['entry_date']?.toString() ?? '';
      final teacher = _teacherNameForRow(row);
      final code = row['teacher_employee_code']?.toString() ?? '';
      final checkIn = row['check_in_time']?.toString() ?? '';
      final checkOut = row['check_out_time']?.toString() ?? '';
      final hours = row['worked_hours']?.toString() ?? '0';
      final late = row['late_minutes']?.toString() ?? '0';
      final auto = row['is_auto_closed'] == true ? 'oui' : 'non';
      final reason = row['auto_closed_reason']?.toString() ?? '';
      buffer.writeln(
        [
          _csvEscape(date),
          _csvEscape(teacher),
          _csvEscape(code),
          _csvEscape(checkIn),
          _csvEscape(checkOut),
          _csvEscape(hours),
          _csvEscape(late),
          _csvEscape(auto),
          _csvEscape(reason),
        ].join(','),
      );
    }

    return buffer.toString();
  }

  Future<void> _exportCsv(List<Map<String, dynamic>> rows) async {
    _setExporting(true, label: 'Export CSV en cours...');
    final csv = _buildCsv(rows);
    final fileName =
      'liste_presences_enseignants_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le fichier CSV',
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );

      if (savePath == null && !kIsWeb) {
        widget.onInfo('Export CSV annule.');
        return;
      }

      widget.onInfo('Fichier CSV exporte (${rows.length} lignes): $fileName');
      return;
    } catch (_) {
      // Fallback: preserve user access to the data when file save is unavailable.
      await Clipboard.setData(ClipboardData(text: csv));
      widget.onInfo('Export CSV indisponible, contenu copie dans le presse-papiers (${rows.length} lignes): $fileName');
    } finally {
      _setExporting(false);
    }
  }

  Uint8List _buildXlsx(List<Map<String, dynamic>> rows) {
    final workbook = xl.Excel.createExcel();
    const sheetName = 'Synthese';
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      workbook.rename(defaultSheet, sheetName);
    }
    final sheet = workbook[sheetName];

    sheet.appendRow([
      xl.TextCellValue('Date'),
      xl.TextCellValue('Enseignant'),
      xl.TextCellValue('Code'),
      xl.TextCellValue('Entree'),
      xl.TextCellValue('Sortie'),
      xl.TextCellValue('Heures'),
      xl.TextCellValue('Retard (min)'),
      xl.TextCellValue('Auto ferme'),
      xl.TextCellValue('Motif auto'),
    ]);

    for (final row in rows) {
      sheet.appendRow([
        xl.TextCellValue(_uiDate(row['entry_date'])),
        xl.TextCellValue(_teacherNameForRow(row)),
        xl.TextCellValue(row['teacher_employee_code']?.toString() ?? ''),
        xl.TextCellValue(row['check_in_time']?.toString() ?? ''),
        xl.TextCellValue(row['check_out_time']?.toString() ?? ''),
        xl.TextCellValue(_f2(_asDouble(row['worked_hours']))),
        xl.TextCellValue(_asInt(row['late_minutes']).toString()),
        xl.TextCellValue(row['is_auto_closed'] == true ? 'oui' : 'non'),
        xl.TextCellValue(row['auto_closed_reason']?.toString() ?? ''),
      ]);
    }

    final bytes = workbook.save();
    if (bytes == null || bytes.isEmpty) {
      return Uint8List(0);
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> _exportXlsx(List<Map<String, dynamic>> rows) async {
    _setExporting(true, label: 'Export XLSX en cours...');
    final bytes = _buildXlsx(rows);
    if (bytes.isEmpty) {
      widget.onInfo('Export XLSX vide.');
      _setExporting(false);
      return;
    }

    final fileName =
      'liste_presences_enseignants_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le fichier XLSX',
        fileName: fileName,
        bytes: bytes,
      );

      if (savePath == null && !kIsWeb) {
        widget.onInfo('Export XLSX annule.');
        return;
      }

      widget.onInfo('Fichier XLSX exporte (${rows.length} lignes): $fileName');
      return;
    } catch (_) {
      final csv = _buildCsv(rows);
      await Clipboard.setData(ClipboardData(text: csv));
      widget.onInfo('Export XLSX indisponible, CSV copie dans le presse-papiers (${rows.length} lignes, fichier cible: $fileName).');
    } finally {
      _setExporting(false);
    }
  }

  Future<void> _exportPdf(
    List<Map<String, dynamic>> rows,
    ({DateTime start, DateTime end}) range,
    Map<String, dynamic> kpi,
  ) async {
    if (rows.isEmpty) {
      widget.onInfo('Aucune donnee a exporter en PDF.');
      return;
    }

    _setExporting(true, label: 'Export PDF en cours...');

    final doc = pw.Document();
    final generatedAt = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final rangeLabel = _rangeLabel(range);
    pw.MemoryImage? logoImage;
    try {
      final raw = await rootBundle.load('assets/images/logo_icone_application.png');
      logoImage = pw.MemoryImage(raw.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    final scopeLabel = _scope == _SummaryScope.allTeachers ? 'Tout les enseignants' : 'Par enseignant';
    String teacherLabel = '-';
    if (_scope == _SummaryScope.singleTeacher && _selectedTeacherId != null) {
      final row = widget.teachers.firstWhere(
        (item) => _asInt(item['id']) == _selectedTeacherId,
        orElse: () => <String, dynamic>{},
      );
      teacherLabel = row.isEmpty ? '-' : widget.teacherLabelBuilder(row);
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          final tableHeaders = [
            'Date',
            'Enseignant',
            'Code',
            'Entree',
            'Sortie',
            'Heures',
            'Retard',
            'Auto',
          ];
          final tableRows = rows.take(220).map((row) {
            return [
              _uiDate(row['entry_date']),
              _teacherNameForRow(row),
              row['teacher_employee_code']?.toString() ?? '-',
              row['check_in_time']?.toString() ?? '-',
              row['check_out_time']?.toString() ?? '-',
              _f2(_asDouble(row['worked_hours'])),
              '${_asInt(row['late_minutes'])} min',
              row['is_auto_closed'] == true ? 'Oui' : 'Non',
            ];
          }).toList(growable: false);

          return [
            pw.Container(
              padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.blue200),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                color: PdfColors.blue50,
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 42,
                      height: 42,
                      margin: const pw.EdgeInsets.only(right: 10),
                      child: pw.Image(logoImage),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'La liste des présences des enseignants',
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          'Rapport de pointage et de suivi horaire',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Periode: ${widget.periodLabelBuilder(_period)} | Plage: $rangeLabel'),
                  pw.Text('Portee: $scopeLabel | Enseignant: $teacherLabel'),
                  pw.Text('Genere le: $generatedAt'),
                ],
              ),
            ),
            pw.SizedBox(height: 10),
            pw.Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.indigo200),
                    color: PdfColors.indigo50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'Pointages: ${kpi['rows']}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue200),
                    color: PdfColors.blue50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'Heures: ${_f2(_asDouble(kpi['hours']))} h',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.orange200),
                    color: PdfColors.orange50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'Auto-fermetures: ${kpi['autoClosed']}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.red200),
                    color: PdfColors.red50,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    'Retards > 15 min: ${kpi['lateStrict']}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              data: tableRows,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
            ),
            if (rows.length > 220)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Text(
                  'Note: export limite aux 220 premieres lignes pour garder un PDF lisible.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    try {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
      widget.onInfo('Export PDF lance.');
    } finally {
      _setExporting(false);
    }
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() => _anchorDate = picked);
    }
  }

  Widget _kpiCard(String label, String value) {
    return Container(
      width: 156,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _hoursByDayBarChart(List<MapEntry<String, double>> sortedDays) {
    if (sortedDays.isEmpty) {
      return const Center(child: Text('Aucune donnee'));
    }

    final maxY = sortedDays
        .map((entry) => entry.value)
        .fold<double>(0, (a, b) => math.max(a, b));
    final chartMaxY = maxY <= 0 ? 1.0 : (maxY * 1.2);

    final groups = <BarChartGroupData>[];
    for (var i = 0; i < sortedDays.length; i++) {
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: sortedDays[i].value,
              width: 14,
              borderRadius: BorderRadius.circular(3),
              color: const Color(0xFF2D6FD6),
            ),
          ],
        ),
      );
    }

    final chartWidth = math.max(420.0, sortedDays.length * 36.0);

    return SizedBox(
      height: 220,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: chartWidth,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: chartMaxY,
              gridData: FlGridData(
                show: true,
                horizontalInterval: chartMaxY / 4,
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (value, _) => Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= sortedDays.length) {
                        return const SizedBox.shrink();
                      }
                      final parsed = DateTime.tryParse(sortedDays[idx].key);
                      final dayLabel = parsed == null
                          ? sortedDays[idx].key
                          : DateFormat('dd/MM').format(parsed);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Transform.rotate(
                          angle: -0.6,
                          child: Text(
                            dayLabel,
                            style: const TextStyle(fontSize: 10),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barGroups: groups,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows();
    final sortedRows = _sortRows(rows);
    final kpi = _kpi(rows);
    final range = _activeRange();
    final prevRange = _previousRange(range);
    final previousRows = _filteredRowsForRange(prevRange);
    final previousKpi = _kpi(previousRows);
    final currentHours = _asDouble(kpi['hours']);
    final previousHours = _asDouble(previousKpi['hours']);
    final byTeacher = _hoursByTeacher(rows);
    final byDay = _hoursByDay(rows);
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(screenSize.width - 16, 1240.0);
    final dialogHeight = math.min(screenSize.height - 24, 760.0);
    final isStackedLayout = dialogWidth < 1050;

    final sortedTeachers = byTeacher.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedDays = byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final displayedRows = math.min(rows.length, 200);

    final tablePane = Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Lignes affichees: $displayedRows / ${rows.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (rows.length > 200)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Affichage limite aux 200 premieres lignes (utilisez l\'export CSV pour tout recuperer).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFC45B00),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        (() {
                          final last = _lastEntryLabel(
                            teacherId: _scope == _SummaryScope.singleTeacher
                                ? _selectedTeacherId
                                : null,
                          );
                          if (last == null) {
                            return 'Aucune presence pour ces filtres.';
                          }
                          return 'Aucune presence pour ces filtres.\nDernier pointage disponible: $last';
                        })(),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Scrollbar(
                      controller: _tableVerticalController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _tableVerticalController,
                        child: Scrollbar(
                          controller: _tableHorizontalController,
                          thumbVisibility: true,
                          notificationPredicate: (notification) =>
                              notification.metrics.axis == Axis.horizontal,
                          child: SingleChildScrollView(
                            controller: _tableHorizontalController,
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 16,
                              horizontalMargin: 10,
                              headingRowHeight: 36,
                              dataRowMinHeight: 34,
                              dataRowMaxHeight: 38,
                              dividerThickness: 0.4,
                              sortColumnIndex: _sortColumn.index,
                              sortAscending: _sortAscending,
                              columns: [
                                DataColumn(
                                  label: const Text('Date'),
                                  onSort: (_, ascending) =>
                                      _setSort(_SummarySortColumn.date, ascending),
                                ),
                                DataColumn(
                                  label: const Text('Enseignant'),
                                  onSort: (_, ascending) =>
                                      _setSort(_SummarySortColumn.teacher, ascending),
                                ),
                                DataColumn(
                                  label: const Text('Entree'),
                                  onSort: (_, ascending) =>
                                      _setSort(_SummarySortColumn.checkIn, ascending),
                                ),
                                DataColumn(
                                  label: const Text('Sortie'),
                                  onSort: (_, ascending) =>
                                      _setSort(_SummarySortColumn.checkOut, ascending),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: const Text('Heures'),
                                  onSort: (_, ascending) =>
                                      _setSort(_SummarySortColumn.hours, ascending),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: const Text('Retard'),
                                  onSort: (_, ascending) =>
                                      _setSort(_SummarySortColumn.late, ascending),
                                ),
                                DataColumn(
                                  label: const Text('Auto'),
                                  onSort: (_, ascending) =>
                                      _setSort(_SummarySortColumn.auto, ascending),
                                ),
                              ],
                              rows: sortedRows.take(200).map((row) {
                                final textStyle = _rowTextStyle(row);
                                return DataRow(
                                  onSelectChanged: (_) => _showRowDetails(row),
                                  color: MaterialStateProperty.resolveWith(
                                    (_) => _rowHighlightColor(row),
                                  ),
                                  cells: [
                                    DataCell(Text(_uiDate(row['entry_date']), style: textStyle)),
                                    DataCell(
                                      SizedBox(
                                        width: 170,
                                        child: Text(
                                          _teacherNameForRow(row),
                                          style: textStyle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(row['check_in_time']?.toString() ?? '-', style: textStyle)),
                                    DataCell(Text(row['check_out_time']?.toString() ?? '-', style: textStyle)),
                                    DataCell(Text(_f2(_asDouble(row['worked_hours'])), style: textStyle)),
                                    DataCell(Text('${_asInt(row['late_minutes'])} min', style: textStyle)),
                                    DataCell(Text(row['is_auto_closed'] == true ? 'Oui' : 'Non', style: textStyle)),
                                  ],
                                );
                              }).toList(growable: false),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );

    final insightsPane = Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, icon: Icon(Icons.bar_chart), label: Text('Graphique')),
                ButtonSegment(value: 1, icon: Icon(Icons.person_outline), label: Text('Par prof')),
              ],
              selected: {_rightPaneTab},
              onSelectionChanged: (values) {
                if (values.isEmpty) return;
                setState(() => _rightPaneTab = values.first);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _rightPaneTab == 0
                  ? _hoursByDayBarChart(sortedDays)
                  : (sortedTeachers.isEmpty
                        ? const Center(child: Text('Aucune donnee'))
                        : ListView.builder(
                            itemCount: sortedTeachers.length,
                            itemBuilder: (context, index) {
                              final entry = sortedTeachers[index];
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                title: Text(
                                  entry.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text('${entry.value.toStringAsFixed(2)} h'),
                              );
                            },
                          )),
            ),
          ],
        ),
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'La liste des présences des enseignants',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 148,
                    child: DropdownButtonFormField<_SummaryPeriod>(
                      initialValue: _period,
                      decoration: const InputDecoration(labelText: 'Periode', isDense: true),
                      items: _SummaryPeriod.values
                          .map(
                            (period) => DropdownMenuItem<_SummaryPeriod>(
                              value: period,
                              child: Text(widget.periodLabelBuilder(period)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _period = value);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 168,
                    child: DropdownButtonFormField<_SummaryScope>(
                      initialValue: _scope,
                      decoration: const InputDecoration(labelText: 'Portee', isDense: true),
                      items: const [
                        DropdownMenuItem(
                          value: _SummaryScope.allTeachers,
                          child: Text('Tout les enseignants'),
                        ),
                        DropdownMenuItem(
                          value: _SummaryScope.singleTeacher,
                          child: Text('Par enseignant'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _scope = value;
                          if (_scope == _SummaryScope.allTeachers) {
                            _selectedTeacherId = null;
                            _anchorDate = _latestEntryDate();
                          } else {
                            _selectedTeacherId ??= widget.teachers.isEmpty
                                ? null
                                : _asInt(widget.teachers.first['id']);
                            _anchorDate = _latestEntryDate(
                              teacherId: _selectedTeacherId,
                            );
                          }
                        });
                      },
                    ),
                  ),
                  if (_scope == _SummaryScope.singleTeacher)
                    SizedBox(
                      width: 280,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedTeacherId,
                        decoration: const InputDecoration(labelText: 'Enseignant', isDense: true),
                        items: widget.teachers
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: _asInt(row['id']),
                                child: Text(widget.teacherLabelBuilder(row)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setState(() {
                            _selectedTeacherId = value;
                            _anchorDate = _latestEntryDate(teacherId: value);
                          });
                        },
                      ),
                    ),
                  SizedBox(
                    width: 156,
                    child: OutlinedButton.icon(
                      onPressed: _pickAnchorDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Changer date'),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      enabled: !_isExporting,
                      onChanged: (value) => setState(() => _searchTerm = value),
                      decoration: const InputDecoration(
                        labelText: 'Recherche prof/code',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Afficher les Retards'),
                    selected: _onlyAnomalies,
                    onSelected: _isExporting
                        ? null
                        : (value) => setState(() => _onlyAnomalies = value),
                  ),
                  PopupMenuButton<String>(
                    enabled: rows.isNotEmpty && !_isExporting,
                    tooltip: 'Exports',
                    onSelected: (value) {
                      switch (value) {
                        case 'csv':
                          _exportCsv(rows);
                        case 'xlsx':
                          _exportXlsx(rows);
                        case 'pdf':
                          _exportPdf(rows, range, kpi);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'csv',
                        child: ListTile(
                          leading: Icon(Icons.download_outlined),
                          title: Text('Exporter CSV'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'xlsx',
                        child: ListTile(
                          leading: Icon(Icons.table_chart_outlined),
                          title: Text('Exporter XLSX'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'pdf',
                        child: ListTile(
                          leading: Icon(Icons.picture_as_pdf_outlined),
                          title: Text('Exporter PDF'),
                        ),
                      ),
                    ],
                    child: FilledButton.tonalIcon(
                      onPressed: null,
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Exports'),
                    ),
                  ),
                ],
              ),
              if (_isExporting) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _exportingLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Plage active: ${_rangeLabel(range)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _kpiCard('Pointages', '${kpi['rows']}'),
                  _kpiCard('Heures totales', '${(_asDouble(kpi['hours']) ).toStringAsFixed(2)} h'),
                  _kpiCard('Auto-fermetures', '${kpi['autoClosed']}'),
                  _kpiCard('Retards > 15 min', '${kpi['lateStrict']}'),
                  _kpiCard('Profs concernes', '${kpi['teachers']}'),
                  _kpiComparisonCard(
                    'Heures vs N-1',
                    _hoursDeltaLabel(currentHours, previousHours),
                    _hoursDeltaDetails(currentHours, previousHours),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: isStackedLayout
                    ? Column(
                        children: [
                          Expanded(flex: 6, child: tablePane),
                          const SizedBox(height: 8),
                          Expanded(flex: 4, child: insightsPane),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: tablePane),
                          const SizedBox(width: 10),
                          Expanded(flex: 3, child: insightsPane),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
