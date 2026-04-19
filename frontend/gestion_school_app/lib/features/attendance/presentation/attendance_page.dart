import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../auth/presentation/auth_controller.dart';
import '../domain/attendance_student.dart';
import 'attendance_controller.dart';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _conduiteController = TextEditingController(text: '18');

  int? _selectedStudentId;
  DateTime _selectedDate = DateTime.now();
  bool _isAbsent = true;
  bool _isLate = false;
  bool _sheetLoading = false;
  bool _sheetSaving = false;
  List<Map<String, dynamic>> _sheetClassrooms = [];
  List<Map<String, dynamic>> _sheetItems = [];
  int? _sheetSelectedClassroomId;
  DateTime _sheetSelectedDate = DateTime.now();
  bool _sheetLocked = false;
  String _sheetValidatedByName = '';
  String? _sheetValidatedAt;

  bool _sheetBootstrapped = false;

  static const _sheetReadRoles = {
    'super_admin',
    'director',
    'supervisor',
    'teacher',
    'accountant',
  };
  static const _sheetWriteRoles = {
    'super_admin',
    'director',
    'supervisor',
    'teacher',
  };
  static const _sheetValidateRoles = {
    'super_admin',
    'director',
    'supervisor',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _sheetBootstrapped) {
        return;
      }
      final role = ref.read(authControllerProvider).valueOrNull?.role;
      if (role != null && _sheetReadRoles.contains(role)) {
        _sheetBootstrapped = true;
        _loadSheetClassrooms();
      }
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _conduiteController.dispose();
    super.dispose();
  }

  Future<void> _loadSheetClassrooms() async {
    setState(() {
      _sheetLoading = true;
    });
    try {
      final rows = await ref.read(attendanceRepositoryProvider).fetchSheetClassrooms();
      if (!mounted) {
        return;
      }
      setState(() {
        _sheetClassrooms = rows;
        if (_sheetClassrooms.isEmpty) {
          _sheetSelectedClassroomId = null;
          _sheetItems = [];
          _sheetLocked = false;
          _sheetValidatedByName = '';
          _sheetValidatedAt = null;
        } else {
          final exists = _sheetClassrooms.any(
            (row) => _asInt(row['id']) == _sheetSelectedClassroomId,
          );
          if (!exists) {
            _sheetSelectedClassroomId = _asInt(_sheetClassrooms.first['id']);
          }
        }
      });
      if (_sheetSelectedClassroomId != null) {
        await _loadClassSheet();
      }
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur chargement classes (fiche).'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetLoading = false;
        });
      }
    }
  }

  Future<void> _loadClassSheet() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      return;
    }
    setState(() {
      _sheetLoading = true;
    });
    try {
      final payload = await ref
          .read(attendanceRepositoryProvider)
          .fetchClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
          );
      if (!mounted) {
        return;
      }
      final rowsRaw = payload['items'];
      final rows = rowsRaw is List
          ? rowsRaw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _sheetItems = rows;
        _sheetLocked = payload['is_locked'] == true;
        _sheetValidatedByName = payload['validated_by_name']?.toString() ?? '';
        _sheetValidatedAt = payload['validated_at']?.toString();
      });
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur chargement fiche.'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetLoading = false;
        });
      }
    }
  }

  Future<void> _saveClassSheet() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }
    setState(() {
      _sheetSaving = true;
    });
    try {
      final items = _sheetItems
          .map(
            (row) => {
              'student': row['student'],
              'is_absent': row['is_absent'] == true,
              'is_late': row['is_late'] == true,
              'reason': (row['reason'] ?? '').toString(),
            },
          )
          .toList(growable: false);
      final result = await ref
          .read(attendanceRepositoryProvider)
          .saveClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            items: items,
          );
      if (!mounted) {
        return;
      }
      _showMessage(
        result['detail']?.toString() ?? 'Fiche de présence enregistrée.',
        isSuccess: true,
      );
      ref.invalidate(attendancesProvider);
      ref.invalidate(attendanceMonthlyStatsProvider);
      await _loadClassSheet();
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur enregistrement fiche.'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetSaving = false;
        });
      }
    }
  }

  Future<void> _setClassSheetLock(bool lock) async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }

    setState(() {
      _sheetSaving = true;
    });
    try {
      final result = await ref
          .read(attendanceRepositoryProvider)
          .setClassSheetLock(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            lock: lock,
          );

      if (!mounted) {
        return;
      }
      _showMessage(
        result['detail']?.toString() ??
            (lock ? 'Fiche validée.' : 'Fiche déverrouillée.'),
        isSuccess: true,
      );
      await _loadClassSheet();
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur validation fiche.'));
    } finally {
      if (mounted) {
        setState(() {
          _sheetSaving = false;
        });
      }
    }
  }

  Future<void> _exportClassSheetPdf() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }
    try {
      final bytes = await ref
          .read(attendanceRepositoryProvider)
          .exportClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            format: 'pdf',
          );
      if (bytes.isEmpty) {
        _showMessage('Export PDF vide.');
        return;
      }
      await Printing.layoutPdf(
        onLayout: (_) async => Uint8List.fromList(bytes),
      );
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur export PDF.'));
    }
  }

  Future<void> _exportClassSheetExcel() async {
    final classroomId = _sheetSelectedClassroomId;
    if (classroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }
    try {
      final bytes = await ref
          .read(attendanceRepositoryProvider)
          .exportClassSheet(
            classroomId: classroomId,
            date: _apiDate(_sheetSelectedDate),
            format: 'xlsx',
          );
      if (bytes.isEmpty) {
        _showMessage('Export Excel vide.');
        return;
      }

      final fileName =
          'presence_classe_${_sheetSelectedClassroomId}_${_apiDate(_sheetSelectedDate)}.xlsx';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la fiche Excel',
        fileName: fileName,
      );

      if (savePath == null) {
        if (!mounted) {
          return;
        }
        _showMessage('Export Excel prêt (${bytes.length} octets).', isSuccess: true);
        return;
      }

      final file = File(savePath);
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        return;
      }
      _showMessage('Fichier Excel exporté.', isSuccess: true);
    } catch (error) {
      _showMessage(_sheetErrorMessage(error, fallback: 'Erreur export Excel.'));
    }
  }

  String _sheetErrorMessage(Object error, {required String fallback}) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 404) {
        return 'L\'API utilisée ne contient pas encore la fiche de présence par classe. '
            'Redémarre le backend local ou reconfigure l\'URL API vers le serveur mis à jour.';
      }

      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final detail = data['detail']?.toString().trim();
        if (detail != null && detail.isNotEmpty) {
          return detail;
        }
      }
    }
    return '$fallback ${error.toString()}';
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
    final studentsAsync = ref.watch(attendanceStudentsProvider);
    final attendancesAsync = ref.watch(attendancesProvider);
    final statsAsync = ref.watch(attendanceMonthlyStatsProvider);
    final mutationState = ref.watch(attendanceMutationProvider);
    final authState = ref.watch(authControllerProvider);
    final userRole = authState.valueOrNull?.role;
    final canEditConduite =
        userRole == 'supervisor' || userRole == 'super_admin';
    final isReadOnlyMode = userRole == 'accountant';
    final canUseSheet = userRole != null && _sheetReadRoles.contains(userRole);
    final canWriteSheet = userRole != null && _sheetWriteRoles.contains(userRole);
    final canValidateSheet =
      userRole != null && _sheetValidateRoles.contains(userRole);
    final isTeacherRole = userRole == 'teacher';
    final allowedClassroomIds = isTeacherRole
      ? _sheetClassrooms
        .map((row) => _asInt(row['id']))
        .where((id) => id > 0)
        .toSet()
      : <int>{};

    ref.listen<AsyncValue<void>>(attendanceMutationProvider, (prev, next) {
      if (prev?.isLoading == true && !next.isLoading && mounted) {
        if (next.hasError) {
          _showMessage('Erreur enregistrement: ${next.error}');
        } else {
          _showMessage('Absence/retard enregistré', isSuccess: true);
          _reasonController.clear();
          if (canEditConduite) {
            _conduiteController.text = '18';
          }
          setState(() {
            _isAbsent = true;
            _isLate = false;
            _selectedDate = DateTime.now();
          });
        }
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Gestion des absences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          statsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('Erreur stats: $error'),
            data: (stats) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Statistiques mensuelles (${stats.month})'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _smallStat(
                          'Enregistrements',
                          stats.totalRecords.toString(),
                        ),
                        _smallStat('Absences', stats.absences.toString()),
                        _smallStat('Retards', stats.lates.toString()),
                        _smallStat(
                          'Justificatifs',
                          stats.justifications.toString(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: LineChart(
                        LineChartData(
                          titlesData: const FlTitlesData(show: true),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < stats.daily.length; i++)
                                  FlSpot(
                                    i.toDouble(),
                                    stats.daily[i].absences.toDouble(),
                                  ),
                              ],
                              isCurved: true,
                            ),
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < stats.daily.length; i++)
                                  FlSpot(
                                    i.toDouble(),
                                    stats.daily[i].lates.toDouble(),
                                  ),
                              ],
                              isCurved: true,
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
          const SizedBox(height: 16),
          if (canUseSheet)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Fiche de présence par classe',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (_sheetLocked)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFCC80)),
                        ),
                        child: Text(
                          'Fiche verrouillée'
                          '${_sheetValidatedByName.isNotEmpty ? ' • par $_sheetValidatedByName' : ''}'
                          '${_sheetValidatedAt != null ? ' • $_sheetValidatedAt' : ''}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    if (_sheetLocked) const SizedBox(height: 10),
                    if (_sheetLoading) const LinearProgressIndicator(),
                    if (_sheetClassrooms.isEmpty && !_sheetLoading)
                      const Text('Aucune classe accessible pour cette fiche.'),
                    if (_sheetClassrooms.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        initialValue: _sheetSelectedClassroomId,
                        decoration: const InputDecoration(labelText: 'Classe'),
                        items: _sheetClassrooms
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: _asInt(row['id']),
                                child: Text(
                                  '${row['name'] ?? '-'}'
                                  '${(row['academic_year_name']?.toString().isNotEmpty ?? false) ? ' • ${row['academic_year_name']}' : ''}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _sheetLoading
                            ? null
                            : (value) async {
                                if (value == null) {
                                  return;
                                }
                                setState(() {
                                  _sheetSelectedClassroomId = value;
                                });
                                await _loadClassSheet();
                              },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Date de la fiche'),
                        subtitle: Text(_formatDate(_sheetSelectedDate)),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_month),
                          onPressed: _sheetLoading
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _sheetSelectedDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _sheetSelectedDate = picked;
                                    });
                                    await _loadClassSheet();
                                  }
                                },
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_sheetItems.isEmpty && !_sheetLoading)
                        const Text('Aucun élève trouvé pour cette classe/date.')
                      else
                        ..._sheetItems.map((row) {
                          final studentName =
                              row['student_full_name']?.toString().trim().isNotEmpty ==
                                  true
                              ? row['student_full_name'].toString()
                              : 'Élève';
                          final matricule = row['student_matricule']?.toString() ?? '';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$studentName${matricule.isNotEmpty ? ' ($matricule)' : ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Absent'),
                                    value: row['is_absent'] == true,
                                    onChanged: (canWriteSheet && !_sheetLocked)
                                        ? (value) {
                                            setState(() {
                                              row['is_absent'] = value;
                                            });
                                          }
                                        : null,
                                  ),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Retard'),
                                    value: row['is_late'] == true,
                                    onChanged: (canWriteSheet && !_sheetLocked)
                                        ? (value) {
                                            setState(() {
                                              row['is_late'] = value;
                                            });
                                          }
                                        : null,
                                  ),
                                  TextFormField(
                                    initialValue: row['reason']?.toString() ?? '',
                                    enabled: canWriteSheet && !_sheetLocked,
                                    decoration: const InputDecoration(
                                      labelText: 'Motif / remarque',
                                    ),
                                    onChanged: (value) {
                                      row['reason'] = value;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _sheetLoading ? null : _exportClassSheetPdf,
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const Text('Export PDF'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _sheetLoading ? null : _exportClassSheetExcel,
                              icon: const Icon(Icons.table_view_outlined),
                              label: const Text('Export Excel'),
                            ),
                            if (canValidateSheet)
                              OutlinedButton.icon(
                                onPressed: (_sheetSaving || _sheetLoading)
                                    ? null
                                    : () => _setClassSheetLock(!_sheetLocked),
                                icon: Icon(
                                  _sheetLocked
                                      ? Icons.lock_open_outlined
                                      : Icons.verified_outlined,
                                ),
                                label: Text(
                                  _sheetLocked
                                      ? 'Déverrouiller'
                                      : 'Valider & verrouiller',
                                ),
                              ),
                            FilledButton.icon(
                              onPressed: (!canWriteSheet ||
                                      _sheetSaving ||
                                      _sheetLoading ||
                                      _sheetLocked)
                                  ? null
                                  : _saveClassSheet,
                              icon: _sheetSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save),
                              label: const Text('Enregistrer la fiche'),
                            ),
                          ],
                        ),
                      ),
                      if (!canWriteSheet)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Lecture seule: ce role peut consulter la fiche sans modifier.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          if (canUseSheet) const SizedBox(height: 16),
          if (isTeacherRole)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Périmètre enseignant: saisie et historique limités aux élèves de vos classes assignées.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Saisie absence/retard'),
                    const SizedBox(height: 10),
                    studentsAsync.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (error, _) => Text('Erreur élèves: $error'),
                      data: (students) {
                        final scopedStudents = isTeacherRole
                            ? students
                                  .where(
                                    (student) => student.classroomId != null &&
                                        allowedClassroomIds.contains(student.classroomId),
                                  )
                                  .toList(growable: false)
                            : students;

                        if (scopedStudents.isEmpty) {
                          return const Text('Aucun élève disponible');
                        }
                        final scopedIds = scopedStudents
                            .map((student) => student.id)
                            .toSet();
                        if (_selectedStudentId == null || !scopedIds.contains(_selectedStudentId)) {
                          _selectedStudentId = scopedStudents.first.id;
                        }

                        return DropdownButtonFormField<int>(
                          initialValue: _selectedStudentId,
                          items: scopedStudents
                              .map(
                                (student) => DropdownMenuItem<int>(
                                  value: student.id,
                                  child: Text(_studentLabel(student)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _selectedStudentId = value),
                          decoration: const InputDecoration(labelText: 'Élève'),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle: Text(_formatDate(_selectedDate)),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                          }
                        },
                      ),
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
                    TextFormField(
                      controller: _reasonController,
                      enabled: !isReadOnlyMode,
                      decoration: const InputDecoration(
                        labelText: 'Motif / remarque',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _conduiteController,
                      enabled: canEditConduite,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Conduite (/20)',
                        helperText: canEditConduite
                            ? 'Modifiable par surveillant/super admin.'
                            : 'Lecture seule: modifiable par surveillant/super admin.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: (mutationState.isLoading || isReadOnlyMode)
                          ? null
                          : () async {
                              final studentId = _selectedStudentId;
                              if (studentId == null) {
                                return;
                              }

                              double? conduite;
                              if (canEditConduite) {
                                conduite = double.tryParse(
                                  _conduiteController.text.trim().replaceAll(
                                    ',',
                                    '.',
                                  ),
                                );
                                if (conduite == null ||
                                    conduite < 0 ||
                                    conduite > 20) {
                                  _showMessage(
                                    'La conduite doit être comprise entre 0 et 20.',
                                  );
                                  return;
                                }
                              }

                              await ref
                                  .read(attendanceMutationProvider.notifier)
                                  .createAttendance(
                                    studentId: studentId,
                                    date: _apiDate(_selectedDate),
                                    isAbsent: _isAbsent,
                                    isLate: _isLate,
                                    reason: _reasonController.text.trim(),
                                    conduite: conduite,
                                  );
                            },
                      child: mutationState.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enregistrer'),
                    ),
                    if (isReadOnlyMode) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Mode lecture seule: le comptable peut consulter sans modifier.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Historique'),
          const SizedBox(height: 8),
          attendancesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Text('Erreur absences: $error'),
            data: (items) {
              final scopedItems = isTeacherRole
                  ? (() {
                      final studentRows = studentsAsync.valueOrNull ?? const <AttendanceStudent>[];
                      final allowedStudentIds = studentRows
                          .where(
                            (student) => student.classroomId != null &&
                                allowedClassroomIds.contains(student.classroomId),
                          )
                          .map((student) => student.id)
                          .toSet();
                      return items
                          .where((item) => allowedStudentIds.contains(item.studentId))
                          .toList(growable: false);
                    })()
                  : items;

              if (scopedItems.isEmpty) {
                return const Text('Aucune donnée');
              }
              return Column(
                children: scopedItems
                    .map(
                      (item) => Card(
                        child: ListTile(
                          title: Text(
                            '${item.studentFullName} (${item.studentMatricule})',
                          ),
                          subtitle: Text(
                            '${item.date} • ${item.isAbsent ? 'Absent' : 'Présent'} • ${item.isLate ? 'Retard' : 'À l\'heure'} • Conduite: ${item.conduite.toStringAsFixed(2)}',
                          ),
                          trailing: item.reason.isEmpty
                              ? null
                              : Tooltip(
                                  message: item.reason,
                                  child: const Icon(Icons.info_outline),
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _smallStat(String title, String value) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _studentLabel(AttendanceStudent student) {
    return '${student.fullName} (${student.matricule})';
  }

  String _formatDate(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _apiDate(DateTime value) => _formatDate(value);

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
