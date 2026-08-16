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
import 'widgets/attendance_sheet_journal.dart';
import 'widgets/attendance_sheet_list.dart';

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

  List<Map<String, dynamic>> _journalFiches = const [];
  bool _journalLoading = false;

  static const _sheetReadRoles = {
    'super_admin',
    'director',
    'promoter',
    'censor',
    'supervisor',
    'teacher',
    'accountant',
  };
  static const _sheetWriteRoles = {
    'super_admin',
    'director',
    'promoter',
    'censor',
    'supervisor',
    'teacher',
  };
  static const _sheetValidateRoles = {
    'super_admin',
    'director',
    'promoter',
    'censor',
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
        _loadSheetJournal();
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

  /// Fiches deja enregistrees, toutes classes accessibles confondues.
  ///
  /// Volontairement non filtre sur la classe selectionnee: on vient ici pour
  /// retrouver une fiche, souvent d'une autre classe que celle affichee.
  Future<void> _loadSheetJournal() async {
    setState(() => _journalLoading = true);
    try {
      final fiches = await ref
          .read(attendanceRepositoryProvider)
          .fetchSheetJournal();
      if (!mounted) return;
      setState(() => _journalFiches = fiches);
    } catch (error) {
      // Un journal indisponible ne doit pas empecher de faire l'appel: la
      // feuille est au-dessus et fonctionne sans lui.
      _showMessage(
        _sheetErrorMessage(error, fallback: 'Erreur chargement des fiches.'),
      );
    } finally {
      if (mounted) setState(() => _journalLoading = false);
    }
  }

  /// Exporte une fiche du journal.
  ///
  /// Elle est d'abord chargee dans le formulaire au-dessus, puis on reutilise
  /// les exports existants: ecrire un second chemin d'export ferait deux
  /// facons de produire le meme document, qui divergeraient.
  Future<void> _exportSheetAt(
    int classroomId,
    String date, {
    required bool excel,
  }) async {
    setState(() {
      _sheetSelectedClassroomId = classroomId;
      _sheetSelectedDate = DateTime.tryParse(date) ?? _sheetSelectedDate;
    });
    await _loadClassSheet();
    if (!mounted) return;
    if (excel) {
      await _exportClassSheetExcel();
    } else {
      await _exportClassSheetPdf();
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
      // La fiche qu'on vient d'enregistrer doit apparaitre au journal.
      await _loadSheetJournal();
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
    final statsAsync = ref.watch(attendanceMonthlyStatsProvider);
    final mutationState = ref.watch(attendanceMutationProvider);
    final authState = ref.watch(authControllerProvider);
    final userRole = authState.valueOrNull?.role;
    final canEditConduite =
      userRole == 'censor' || userRole == 'supervisor' || userRole == 'super_admin';
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
      // Le titre vit desormais dans l'onglet « Élèves » du module Émargements:
      // une barre de plus repeterait ce que la navigation dit deja.
      appBar: null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Les statistiques decrivent le mois ecoule; la feuille d'appel est
          // le geste du jour. Depliees en tete, elles obligeaient a defiler
          // pour faire l'appel. Elles restent a portee d'un clic.
          ExpansionTile(
            title: const Text('Statistiques mensuelles'),
            initiallyExpanded: false,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
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
            ],
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
                        AttendanceSheetList(
                          items: _sheetItems,
                          editable: canWriteSheet && !_sheetLocked,
                          onPresenceChanged: (row, etat) => setState(() {
                            final absent = etat == PresenceEleve.absent;
                            row['is_absent'] = absent;
                            // Repasser present efface le motif: il decrivait
                            // une absence qui n'existe plus, et il serait
                            // enregistre tel quel.
                            if (!absent) row['reason'] = '';
                          }),
                          onRetardChanged: (row, enRetard) =>
                              setState(() => row['is_late'] = enRetard),
                          onMotifChanged: (row, motif) => row['reason'] = motif,
                          onToutPresent: () => setState(() {
                            for (final row in _sheetItems) {
                              row['is_absent'] = false;
                              row['reason'] = '';
                            }
                          }),
                        ),
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
          const Text(
            'Fiches enregistrées',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Les fiches déjà saisies, par classe et par date.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          AttendanceSheetJournal(
            fiches: _journalFiches,
            loading: _journalLoading,
            onVoir: (classroomId, date) {
              // Recharger dans le formulaire au-dessus plutot que d'ouvrir un
              // second ecran: c'est le meme document, verrouille ou non.
              setState(() {
                _sheetSelectedClassroomId = classroomId;
                _sheetSelectedDate =
                    DateTime.tryParse(date) ?? _sheetSelectedDate;
              });
              _loadClassSheet();
            },
            onExporterPdf: (classroomId, date) =>
                _exportSheetAt(classroomId, date, excel: false),
            onExporterExcel: (classroomId, date) =>
                _exportSheetAt(classroomId, date, excel: true),
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
