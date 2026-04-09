import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/network/api_client.dart';
import '../../auth/presentation/auth_controller.dart';

class GradesPage extends ConsumerStatefulWidget {
  const GradesPage({super.key});

  @override
  ConsumerState<GradesPage> createState() => _GradesPageState();
}

class _GradesPageState extends ConsumerState<GradesPage> {
  final _termController = TextEditingController(text: 'T1');
  final _validationNotesController = TextEditingController();
  final _gradesSearchController = TextEditingController();

  int? _selectedStudent;
  int? _selectedSubject;
  int? _selectedClassroom;
  int? _selectedAcademicYear;

  bool _loading = true;
  bool _saving = false;
  int _notesPage = 1;
  int _notesRowsPerPage = 12;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _teacherAssignments = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _grades = [];
  Map<String, dynamic>? _validationStatus;
  bool _isTeacherUser = false;
  int? _loggedTeacherId;
  Set<int> _allowedClassroomIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _termController.dispose();
    _validationNotesController.dispose();
    _gradesSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/students/'),
        dio.get('/subjects/'),
        dio.get('/teachers/'),
        dio.get('/teacher-assignments/'),
        dio.get('/classrooms/'),
        dio.get('/academic-years/'),
      ]);

      if (!mounted) return;

      final authUser = ref.read(authControllerProvider).value;
      final isTeacherUser = authUser?.role == 'teacher';
      final teachers = _extractRows(results[2].data);
      final assignments = _extractRows(results[3].data);
      final classrooms = _extractRows(results[4].data);
      final years = _extractRows(results[5].data);

      int? loggedTeacherId;
      Set<int> allowedClassroomIds = <int>{};

      if (isTeacherUser && authUser != null) {
        final ownTeacher = teachers.firstWhere(
          (row) => _asInt(row['user']) == authUser.id,
          orElse: () => <String, dynamic>{},
        );
        final teacherId = _asInt(ownTeacher['id']);
        if (teacherId > 0) {
          loggedTeacherId = teacherId;
          allowedClassroomIds = assignments
              .where((row) => _asInt(row['teacher']) == teacherId)
              .map((row) => _asInt(row['classroom']))
              .where((id) => id > 0)
              .toSet();
        }
      }

      setState(() {
        _students = _extractRows(results[0].data);
        _subjects = _extractRows(results[1].data);
        _teacherAssignments = assignments;
        _classrooms = classrooms;
        _years = years;
        _isTeacherUser = isTeacherUser;
        _loggedTeacherId = loggedTeacherId;
        _allowedClassroomIds = allowedClassroomIds;
        _termController.text = _currentTermOrDefault();

        final visibleClassrooms = _classroomsForCurrentRole();
        final visibleClassroomIds = visibleClassrooms
            .map((row) => _asInt(row['id']))
            .where((id) => id > 0)
            .toSet();

        if (_selectedClassroom == null ||
            !visibleClassroomIds.contains(_selectedClassroom)) {
          _selectedClassroom = visibleClassrooms.isNotEmpty
              ? _asInt(visibleClassrooms.first['id'])
              : null;
        }

        _selectedAcademicYear ??= _years.isNotEmpty
            ? _asInt(_years.first['id'])
            : null;

        final classStudents = _studentsForClassroom(_selectedClassroom);
        final classSubjects = _subjectsForClassroom(_selectedClassroom);
        _selectedStudent ??= classStudents.isNotEmpty
            ? _asInt(classStudents.first['id'])
            : (_students.isNotEmpty ? _asInt(_students.first['id']) : null);
        _selectedSubject ??= classSubjects.isNotEmpty
            ? _asInt(classSubjects.first['id'])
            : null;
      });

      await _refreshValidationStatus();
      await _reloadGradesForCurrentFilters(showError: false);
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

  String _currentTermOrDefault() {
    final normalized = _normalizeTerm(_termController.text);
    return normalized.isEmpty ? 'T1' : normalized;
  }

  Future<List<Map<String, dynamic>>> _fetchAllGradesForCurrentFilters() async {
    final classroom = _selectedClassroom;
    final academicYear = _selectedAcademicYear;
    final term = _currentTermOrDefault();

    if (classroom == null || academicYear == null || term.isEmpty) {
      return [];
    }

    final dio = ref.read(dioProvider);
    final rows = <Map<String, dynamic>>[];

    int page = 1;
    while (page <= 50) {
      final response = await dio.get(
        '/grades/',
        queryParameters: {
          'classroom': classroom,
          'academic_year': academicYear,
          'term': term,
          'ordering': '-id',
          'page': page,
          'page_size': 200,
        },
      );

      final data = response.data;
      rows.addAll(_extractRows(data));

      if (data is! Map<String, dynamic>) {
        break;
      }

      final next = data['next'];
      if (next == null || next.toString().trim().isEmpty) {
        break;
      }

      page += 1;
    }

    return rows;
  }

  Future<void> _reloadGradesForCurrentFilters({bool showError = true}) async {
    try {
      final rows = await _fetchAllGradesForCurrentFilters();
      if (!mounted) return;
      setState(() {
        _grades = rows;
        _notesPage = 1;
      });
    } catch (error) {
      if (!mounted || !showError) return;
      _showMessage('Erreur chargement notes filtrées: $error');
    }
  }

  Future<Map<int, Map<String, dynamic>>> _fetchExistingGradesForDialog({
    required int classroomId,
    required int subjectId,
    required int academicYearId,
    required String term,
  }) async {
    if (subjectId <= 0 || classroomId <= 0 || academicYearId <= 0) {
      return <int, Map<String, dynamic>>{};
    }

    final dio = ref.read(dioProvider);
    final rowsByStudent = <int, Map<String, dynamic>>{};

    int page = 1;
    while (page <= 20) {
      final response = await dio.get(
        '/grades/',
        queryParameters: {
          'classroom': classroomId,
          'academic_year': academicYearId,
          'term': term,
          'subject': subjectId,
          'ordering': '-id',
          'page': page,
          'page_size': 200,
        },
      );

      final payload = response.data;
      final rows = _extractRows(payload);
      for (final row in rows) {
        final studentId = _asInt(row['student']);
        if (studentId <= 0) {
          continue;
        }
        rowsByStudent.putIfAbsent(studentId, () => row);
      }

      if (payload is! Map<String, dynamic>) {
        break;
      }

      final next = payload['next'];
      if (next == null || next.toString().trim().isEmpty) {
        break;
      }

      page += 1;
    }

    return rowsByStudent;
  }

  Future<int> _ensureExamSessionForCurrentPeriod() async {
    final academicYearId = _selectedAcademicYear;
    final term = _currentTermOrDefault();
    if (academicYearId == null || term.isEmpty) {
      throw Exception('Année scolaire ou période invalide pour l\'examen.');
    }

    final dio = ref.read(dioProvider);
    final sessionsById = <int, Map<String, dynamic>>{};

    int page = 1;
    while (page <= 30) {
      final response = await dio.get(
        '/exam-sessions/',
        queryParameters: {'page': page, 'page_size': 200},
      );
      final payload = response.data;
      final rows = _extractRows(payload);
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row);
        final id = _asInt(map['id']);
        if (id > 0) {
          sessionsById[id] = map;
        }
      }

      if (payload is! Map<String, dynamic>) {
        break;
      }
      final next = payload['next'];
      if (next == null || next.toString().trim().isEmpty) {
        break;
      }
      page += 1;
    }

    final normalizedTerm = _normalizeTerm(term);
    for (final row in sessionsById.values) {
      if (_asInt(row['academic_year']) != academicYearId) {
        continue;
      }
      if (_normalizeTerm(row['term']) != normalizedTerm) {
        continue;
      }
      final existingId = _asInt(row['id']);
      if (existingId > 0) {
        return existingId;
      }
    }

    final yearRow = _findById(_years, academicYearId);
    final now = DateTime.now();
    final startDate = (yearRow?['start_date'] ?? '').toString().trim();
    final endDate = (yearRow?['end_date'] ?? '').toString().trim();
    final start = startDate.isNotEmpty ? startDate : _apiDate(now);
    final end = endDate.isNotEmpty
        ? endDate
        : _apiDate(now.add(const Duration(days: 1)));

    final created = await dio.post(
      '/exam-sessions/',
      data: {
        'title': 'Examen $term - Notes',
        'term': term,
        'academic_year': academicYearId,
        'start_date': start,
        'end_date': end,
      },
    );

    final data = created.data;
    if (data is! Map<String, dynamic>) {
      throw Exception(
        'Réponse invalide lors de la création de la session examen.',
      );
    }

    final sessionId = _asInt(data['id']);
    if (sessionId <= 0) {
      throw Exception('Impossible de créer la session examen.');
    }
    return sessionId;
  }

  Future<Map<int, Map<String, dynamic>>> _fetchExistingExamResultsForDialog({
    required int sessionId,
    required int subjectId,
  }) async {
    final dio = ref.read(dioProvider);
    final rowsByStudent = <int, Map<String, dynamic>>{};

    int page = 1;
    while (page <= 30) {
      final response = await dio.get(
        '/exam-results/',
        queryParameters: {
          'session': sessionId,
          'subject': subjectId,
          'ordering': '-id',
          'page': page,
          'page_size': 200,
        },
      );

      final payload = response.data;
      final rows = _extractRows(payload);
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row);
        if (_asInt(map['session']) != sessionId ||
            _asInt(map['subject']) != subjectId) {
          continue;
        }
        final studentId = _asInt(map['student']);
        if (studentId <= 0) {
          continue;
        }
        rowsByStudent.putIfAbsent(studentId, () => map);
      }

      if (payload is! Map<String, dynamic>) {
        break;
      }

      final next = payload['next'];
      if (next == null || next.toString().trim().isEmpty) {
        break;
      }
      page += 1;
    }

    return rowsByStudent;
  }

  Future<void> _openExamEntryDialog() async {
    if (_isValidated) {
      _showMessage('Période validée par la direction: saisie verrouillée.');
      return;
    }

    if (_selectedClassroom == null ||
        _selectedAcademicYear == null ||
        _termController.text.trim().isEmpty) {
      _showMessage(
        'Sélectionnez classe, année et période avant la saisie examen.',
      );
      return;
    }

    final visibleClassrooms = _classroomsForCurrentRole();
    if (_students.isEmpty || visibleClassrooms.isEmpty) {
      _showMessage('Aucun élève ou matière disponible pour la saisie examen.');
      return;
    }

    int selectedClassroom =
        _selectedClassroom ?? _asInt(visibleClassrooms.first['id']);
    final initialSubjects = _subjectsForClassroom(selectedClassroom);
    if (initialSubjects.isEmpty) {
      _showMessage('Aucune matière attribuée à cette classe.');
      return;
    }

    int selectedSubject = _asInt(initialSubjects.first['id']);
    List<Map<String, dynamic>> dialogStudents = _studentsForClassroom(
      selectedClassroom,
    );
    final scoreControllers = <int, TextEditingController>{};
    Map<int, Map<String, dynamic>> existingByStudent = {};
    bool loadingRows = false;
    bool savingRows = false;
    bool initialized = false;
    String? dialogError;
    int createdCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;

    void disposeDialogControllers() {
      for (final controller in scoreControllers.values) {
        controller.dispose();
      }
      scoreControllers.clear();
    }

    Future<void> loadDialogRows(StateSetter setDialogState) async {
      setDialogState(() {
        loadingRows = true;
        dialogError = null;
      });

      try {
        final loadedStudents = _studentsForClassroom(selectedClassroom);
        final sessionId = await _ensureExamSessionForCurrentPeriod();
        final loadedExisting = await _fetchExistingExamResultsForDialog(
          sessionId: sessionId,
          subjectId: selectedSubject,
        );

        disposeDialogControllers();
        for (final student in loadedStudents) {
          final studentId = _asInt(student['id']);
          final existing = loadedExisting[studentId];
          scoreControllers[studentId] = TextEditingController(
            text: (existing?['score'] ?? '').toString(),
          );
        }

        setDialogState(() {
          dialogStudents = loadedStudents;
          existingByStudent = loadedExisting;
          loadingRows = false;
        });
      } catch (error) {
        setDialogState(() {
          loadingRows = false;
          dialogError =
              'Erreur chargement notes examen: ${_extractFriendlyError(error)}';
        });
      }
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (!initialized) {
              initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  loadDialogRows(setDialogState);
                }
              });
            }

            return AlertDialog(
              title: const Text('Saisie des notes examen'),
              content: SizedBox(
                width: 760,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Classe ID $selectedClassroom • Période ${_currentTermOrDefault()}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedClassroom,
                            decoration: const InputDecoration(
                              labelText: 'Classe',
                            ),
                            items: _classroomsForCurrentRole()
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text('${row['name']}'),
                                  ),
                                )
                                .toList(),
                            onChanged: loadingRows || savingRows
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      selectedClassroom = value;
                                      final classSubjects =
                                          _subjectsForClassroom(
                                            selectedClassroom,
                                          );
                                      selectedSubject = classSubjects.isNotEmpty
                                          ? _asInt(classSubjects.first['id'])
                                          : 0;
                                    });
                                    loadDialogRows(setDialogState);
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedSubject > 0
                                ? selectedSubject
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Matière',
                            ),
                            items: _subjectsForClassroom(selectedClassroom)
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text(
                                      '${row['code']} - ${row['name']}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: loadingRows || savingRows
                                ? null
                                : (value) {
                                    if (value == null || value <= 0) return;
                                    setDialogState(
                                      () => selectedSubject = value,
                                    );
                                    loadDialogRows(setDialogState);
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    if (loadingRows)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (dialogStudents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Aucun élève trouvé pour cette classe.'),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 340),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: dialogStudents.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final student = dialogStudents[index];
                            final studentId = _asInt(student['id']);
                            final controller =
                                scoreControllers[studentId] ??
                                TextEditingController();
                            scoreControllers[studentId] = controller;
                            final existing = existingByStudent[studentId];

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${student['matricule'] ?? ''} • ${(student['user_full_name'] ?? '').toString().trim()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (existing != null)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Tooltip(
                                        message:
                                            'Note examen existante: modification',
                                        child: Icon(
                                          Icons.edit_note_outlined,
                                          size: 18,
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ),
                                  SizedBox(
                                    width: 130,
                                    child: TextField(
                                      controller: controller,
                                      enabled: !savingRows,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        labelText: 'Examen /20',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingRows
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingRows || loadingRows || dialogStudents.isEmpty
                      ? null
                      : () async {
                          for (final student in dialogStudents) {
                            final studentId = _asInt(student['id']);
                            final raw =
                                scoreControllers[studentId]?.text.trim() ?? '';
                            if (raw.isEmpty) {
                              continue;
                            }
                            final score = double.tryParse(
                              raw.replaceAll(',', '.'),
                            );
                            if (score == null || score < 0 || score > 20) {
                              setDialogState(() {
                                dialogError =
                                    'Note examen invalide pour ${(student['user_full_name'] ?? student['matricule'] ?? 'un élève')}.';
                              });
                              return;
                            }
                          }

                          setDialogState(() {
                            savingRows = true;
                            dialogError = null;
                          });

                          createdCount = 0;
                          updatedCount = 0;
                          skippedCount = 0;

                          try {
                            final dio = ref.read(dioProvider);
                            final sessionId =
                                await _ensureExamSessionForCurrentPeriod();
                            final existingMap =
                                await _fetchExistingExamResultsForDialog(
                                  sessionId: sessionId,
                                  subjectId: selectedSubject,
                                );

                            for (final student in dialogStudents) {
                              final studentId = _asInt(student['id']);
                              final raw =
                                  scoreControllers[studentId]?.text.trim() ??
                                  '';
                              if (raw.isEmpty) {
                                skippedCount += 1;
                                continue;
                              }
                              final score = double.tryParse(
                                raw.replaceAll(',', '.'),
                              );
                              if (score == null) {
                                continue;
                              }

                              final existing = existingMap[studentId];
                              if (existing != null) {
                                final resultId = _asInt(existing['id']);
                                await dio.patch(
                                  '/exam-results/$resultId/',
                                  data: {'score': score},
                                );
                                updatedCount += 1;
                              } else {
                                await dio.post(
                                  '/exam-results/',
                                  data: {
                                    'session': sessionId,
                                    'student': studentId,
                                    'subject': selectedSubject,
                                    'score': score,
                                  },
                                );
                                createdCount += 1;
                              }
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setDialogState(() {
                              savingRows = false;
                              dialogError =
                                  'Erreur enregistrement examen: ${_extractFriendlyError(error)}';
                            });
                          }
                        },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    disposeDialogControllers();

    if (shouldSave != true) {
      return;
    }

    await _reloadGradesForCurrentFilters(showError: false);
    final touched = createdCount + updatedCount;
    if (touched > 0) {
      _showMessage(
        'Notes examen enregistrées: $createdCount ajoutées, $updatedCount modifiées, $skippedCount ignorées.',
        isSuccess: true,
      );
    } else {
      _showMessage('Aucune note examen enregistrée (champs vides).');
    }
  }

  List<double> _homeworkScoresFromGradeRow(Map<String, dynamic>? row) {
    if (row == null) {
      return const [];
    }

    final raw = row['homework_scores'];
    final scores = <double>[];
    if (raw is List) {
      for (final item in raw) {
        final parsed = double.tryParse(item.toString().replaceAll(',', '.'));
        if (parsed == null) {
          continue;
        }
        if (parsed < 0 || parsed > 20) {
          continue;
        }
        scores.add(parsed);
      }
    }

    if (scores.isNotEmpty) {
      return scores;
    }

    final value = double.tryParse(
      (row['value'] ?? '').toString().replaceAll(',', '.'),
    );
    if (value != null && value >= 0 && value <= 20) {
      return [value];
    }

    return const [];
  }

  double? _averageHomeworkScores(List<double> scores) {
    if (scores.isEmpty) {
      return null;
    }
    final sum = scores.fold<double>(0, (acc, value) => acc + value);
    return sum / scores.length;
  }

  Future<void> _openGradeEntryDialog() async {
    if (_isValidated) {
      _showMessage('Période validée par la direction: saisie verrouillée.');
      return;
    }

    if (_selectedClassroom == null ||
        _selectedAcademicYear == null ||
        _termController.text.trim().isEmpty) {
      _showMessage('Sélectionnez classe, année et période avant la saisie.');
      return;
    }

    final visibleClassrooms = _classroomsForCurrentRole();
    if (_students.isEmpty || visibleClassrooms.isEmpty) {
      _showMessage('Aucun élève ou matière disponible pour la saisie.');
      return;
    }

    int selectedClassroom =
        _selectedClassroom ?? _asInt(visibleClassrooms.first['id']);
    final initialSubjects = _subjectsForClassroom(selectedClassroom);
    if (initialSubjects.isEmpty) {
      _showMessage(
        'Aucune matière attribuée à cette classe. Configurez les attributions enseignant/matière.',
      );
      return;
    }

    int selectedSubject = _asInt(initialSubjects.first['id']);
    List<Map<String, dynamic>> dialogStudents = _studentsForClassroom(
      selectedClassroom,
    );
    final devoirControllers = <int, List<TextEditingController>>{};
    Map<int, Map<String, dynamic>> existingByStudent = {};
    int devoirCount = 3;
    bool loadingRows = false;
    bool savingRows = false;
    bool initialized = false;
    String? dialogError;
    int createdCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;

    void disposeDialogControllers() {
      for (final controllers in devoirControllers.values) {
        for (final controller in controllers) {
          controller.dispose();
        }
      }
      devoirControllers.clear();
    }

    List<TextEditingController> ensureControllers(int studentId) {
      final existing = devoirControllers[studentId];
      if (existing == null) {
        final created = List.generate(
          devoirCount,
          (_) => TextEditingController(),
        );
        devoirControllers[studentId] = created;
        return created;
      }

      if (existing.length > devoirCount) {
        for (var i = devoirCount; i < existing.length; i++) {
          existing[i].dispose();
        }
        existing.removeRange(devoirCount, existing.length);
      }
      while (existing.length < devoirCount) {
        existing.add(TextEditingController());
      }
      return existing;
    }

    List<double> parseStudentScores(List<TextEditingController> controllers) {
      final scores = <double>[];
      for (final controller in controllers) {
        final raw = controller.text.trim();
        if (raw.isEmpty) {
          continue;
        }
        final parsed = double.tryParse(raw.replaceAll(',', '.'));
        if (parsed == null || parsed < 0 || parsed > 20) {
          throw const FormatException('INVALID_SCORE');
        }
        scores.add(parsed);
      }
      return scores;
    }

    Future<void> loadDialogRows(StateSetter setDialogState) async {
      setDialogState(() {
        loadingRows = true;
        dialogError = null;
      });

      try {
        final term = _currentTermOrDefault();
        final loadedStudents = _studentsForClassroom(selectedClassroom);

        final classSubjects = _subjectsForClassroom(selectedClassroom);
        final validSubjectIds = classSubjects
            .map((row) => _asInt(row['id']))
            .where((id) => id > 0)
            .toSet();

        if (validSubjectIds.isEmpty ||
            !validSubjectIds.contains(selectedSubject)) {
          disposeDialogControllers();
          setDialogState(() {
            dialogStudents = loadedStudents;
            existingByStudent = <int, Map<String, dynamic>>{};
            loadingRows = false;
            dialogError =
                'Aucune matière attribuée à cette classe. Configurez les attributions enseignant/matière.';
          });
          return;
        }

        final loadedExisting = await _fetchExistingGradesForDialog(
          classroomId: selectedClassroom,
          subjectId: selectedSubject,
          academicYearId: _selectedAcademicYear!,
          term: term,
        );

        disposeDialogControllers();
        var maxCount = 1;
        for (final student in loadedStudents) {
          final studentId = _asInt(student['id']);
          final scores = _homeworkScoresFromGradeRow(loadedExisting[studentId]);
          if (scores.length > maxCount) {
            maxCount = scores.length;
          }
        }

        devoirCount = math.max(devoirCount, maxCount);
        for (final student in loadedStudents) {
          final studentId = _asInt(student['id']);
          final scores = _homeworkScoresFromGradeRow(loadedExisting[studentId]);
          final controllers = <TextEditingController>[];
          for (var index = 0; index < devoirCount; index++) {
            final value = index < scores.length
                ? scores[index].toStringAsFixed(2)
                : '';
            controllers.add(TextEditingController(text: value));
          }
          devoirControllers[studentId] = controllers;
        }

        setDialogState(() {
          dialogStudents = loadedStudents;
          existingByStudent = loadedExisting;
          loadingRows = false;
        });
      } on DioException catch (error) {
        setDialogState(() {
          loadingRows = false;
          dialogError =
              'Erreur chargement élèves/notes: ${_extractDioErrorMessage(error)}';
        });
      } catch (error) {
        setDialogState(() {
          loadingRows = false;
          dialogError =
              'Erreur chargement élèves/notes: ${_extractFriendlyError(error)}';
        });
      }
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (!initialized) {
              initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) {
                  loadDialogRows(setDialogState);
                }
              });
            }

            return AlertDialog(
              title: const Text('Saisie des notes par classe'),
              content: SizedBox(
                width: 860,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Classe ID $selectedClassroom • Période ${_currentTermOrDefault()}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedClassroom,
                            decoration: const InputDecoration(
                              labelText: 'Classe',
                            ),
                            items: _classroomsForCurrentRole()
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text('${row['name']}'),
                                  ),
                                )
                                .toList(),
                            onChanged: loadingRows || savingRows
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      selectedClassroom = value;
                                      final classSubjects =
                                          _subjectsForClassroom(
                                            selectedClassroom,
                                          );
                                      selectedSubject = classSubjects.isNotEmpty
                                          ? _asInt(classSubjects.first['id'])
                                          : 0;
                                    });
                                    loadDialogRows(setDialogState);
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedSubject > 0
                                ? selectedSubject
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Matière',
                            ),
                            items: _subjectsForClassroom(selectedClassroom)
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text(
                                      '${row['code']} - ${row['name']}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: loadingRows || savingRows
                                ? null
                                : (value) {
                                    if (value == null || value <= 0) return;
                                    setDialogState(
                                      () => selectedSubject = value,
                                    );
                                    loadDialogRows(setDialogState);
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Devoirs: $devoirCount'),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: savingRows
                              ? null
                              : () {
                                  setDialogState(() {
                                    devoirCount += 1;
                                    for (final student in dialogStudents) {
                                      final studentId = _asInt(student['id']);
                                      ensureControllers(studentId);
                                    }
                                  });
                                },
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter devoir'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: (savingRows || devoirCount <= 1)
                              ? null
                              : () {
                                  setDialogState(() {
                                    devoirCount -= 1;
                                    for (final controllers
                                        in devoirControllers.values) {
                                      if (controllers.length > devoirCount) {
                                        final removed = controllers
                                            .removeLast();
                                        removed.dispose();
                                      }
                                    }
                                  });
                                },
                          icon: const Icon(Icons.remove),
                          label: const Text('Retirer devoir'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    if (loadingRows)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (dialogStudents.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Aucun élève trouvé pour cette classe.'),
                      )
                    else
                      Container(
                        constraints: const BoxConstraints(maxHeight: 360),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: dialogStudents.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final student = dialogStudents[index];
                            final studentId = _asInt(student['id']);
                            final controllers = ensureControllers(studentId);
                            final existing = existingByStudent[studentId];

                            double? average;
                            try {
                              average = _averageHomeworkScores(
                                parseStudentScores(controllers),
                              );
                            } catch (_) {
                              average = null;
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${student['matricule'] ?? ''} • ${(student['user_full_name'] ?? '').toString().trim()}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (existing != null)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Tooltip(
                                        message:
                                            'Notes existantes: modification',
                                        child: Icon(
                                          Icons.edit_note_outlined,
                                          size: 18,
                                          color: Colors.orangeAccent,
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    flex: 2,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (
                                            var devoirIndex = 0;
                                            devoirIndex < devoirCount;
                                            devoirIndex++
                                          )
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: SizedBox(
                                                width: 82,
                                                child: TextField(
                                                  controller:
                                                      controllers[devoirIndex],
                                                  enabled: !savingRows,
                                                  onChanged: (_) =>
                                                      setDialogState(() {}),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  decoration: InputDecoration(
                                                    isDense: true,
                                                    labelText:
                                                        'D${devoirIndex + 1}',
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      average == null
                                          ? 'Classe: -'
                                          : 'Classe: ${average.toStringAsFixed(2)}',
                                      textAlign: TextAlign.right,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: savingRows
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: savingRows || loadingRows || dialogStudents.isEmpty
                      ? null
                      : () async {
                          final term = _currentTermOrDefault();
                          final academicYear = _selectedAcademicYear;
                          if (academicYear == null) {
                            setDialogState(() {
                              dialogError =
                                  'Année scolaire introuvable pour cet enregistrement.';
                            });
                            return;
                          }

                          for (final student in dialogStudents) {
                            final studentId = _asInt(student['id']);
                            try {
                              parseStudentScores(ensureControllers(studentId));
                            } on FormatException {
                              setDialogState(() {
                                dialogError =
                                    'Notes de devoir invalides pour ${(student['user_full_name'] ?? student['matricule'] ?? 'un élève')}.';
                              });
                              return;
                            }
                          }

                          setDialogState(() {
                            savingRows = true;
                            dialogError = null;
                          });

                          createdCount = 0;
                          updatedCount = 0;
                          skippedCount = 0;

                          try {
                            final dio = ref.read(dioProvider);
                            for (final student in dialogStudents) {
                              final studentId = _asInt(student['id']);
                              final scores = parseStudentScores(
                                ensureControllers(studentId),
                              );

                              if (scores.isEmpty) {
                                skippedCount += 1;
                                continue;
                              }

                              final existing = existingByStudent[studentId];
                              if (existing != null) {
                                final gradeId = _asInt(existing['id']);
                                await dio.patch(
                                  '/grades/$gradeId/',
                                  data: {'homework_scores': scores},
                                );
                                updatedCount += 1;
                              } else {
                                await dio.post(
                                  '/grades/',
                                  data: {
                                    'student': studentId,
                                    'subject': selectedSubject,
                                    'classroom': selectedClassroom,
                                    'academic_year': academicYear,
                                    'term': term,
                                    'homework_scores': scores,
                                  },
                                );
                                createdCount += 1;
                              }
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            setDialogState(() {
                              savingRows = false;
                              dialogError =
                                  'Erreur enregistrement: ${_extractFriendlyError(error)}';
                            });
                          }
                        },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    disposeDialogControllers();

    if (shouldSave != true) {
      return;
    }

    setState(() {
      _selectedClassroom = selectedClassroom;
      _selectedSubject = selectedSubject;
      final students = _studentsForClassroom(selectedClassroom);
      if (students.isNotEmpty) {
        _selectedStudent = _asInt(students.first['id']);
      }
    });

    await _refreshValidationStatus();
    await _reloadGradesForCurrentFilters(showError: true);

    final touched = createdCount + updatedCount;
    if (touched > 0) {
      _showMessage(
        'Enregistrement terminé: $createdCount ajoutées, $updatedCount modifiées, $skippedCount ignorées.',
        isSuccess: true,
      );
    } else {
      _showMessage('Aucune note enregistrée (champs vides).');
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
              'term': _currentTermOrDefault(),
            },
          );

      if (!mounted) return;
      _showMessage('Classement recalculé.', isSuccess: true);
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

  Future<Uint8List> _fetchBulletinPdfBytes({
    required int studentId,
    int? yearId,
    String? term,
  }) async {
    final effectiveYearId = yearId ?? _selectedAcademicYear;
    final effectiveTerm = _normalizeTerm(term ?? _currentTermOrDefault());

    if (effectiveYearId == null || effectiveTerm.isEmpty) {
      throw Exception('Sélectionnez année et période pour le bulletin.');
    }

    final response = await ref
        .read(dioProvider)
        .get(
          '/reports/bulletin/$studentId/$effectiveYearId/${Uri.encodeComponent(effectiveTerm)}/',
          options: Options(responseType: ResponseType.bytes),
        );

    return _toUint8List(response.data);
  }

  Future<Uint8List> _fetchClassBulletinsPdfBytes({
    required int classroomId,
    int? yearId,
    String? term,
  }) async {
    final effectiveYearId = yearId ?? _selectedAcademicYear;
    final effectiveTerm = _normalizeTerm(term ?? _currentTermOrDefault());

    if (effectiveYearId == null || effectiveTerm.isEmpty) {
      throw Exception('Sélectionnez année et période pour les bulletins.');
    }

    final response = await ref
        .read(dioProvider)
        .get(
          '/reports/bulletins/class/$classroomId/$effectiveYearId/${Uri.encodeComponent(effectiveTerm)}/',
          options: Options(responseType: ResponseType.bytes),
        );

    return _toUint8List(response.data);
  }

  Future<void> _printBulletin({
    int? studentId,
    int? yearId,
    String? term,
  }) async {
    final effectiveStudentId = studentId ?? _selectedStudent;
    if (effectiveStudentId == null) {
      _showMessage('Sélectionnez un élève pour le bulletin.');
      return;
    }

    setState(() => _saving = true);
    try {
      final bytes = await _fetchBulletinPdfBytes(
        studentId: effectiveStudentId,
        yearId: yearId,
        term: term,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur génération bulletin: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printClassBulletins({
    int? classroomId,
    int? yearId,
    String? term,
  }) async {
    final effectiveClassroomId = classroomId ?? _selectedClassroom;
    if (effectiveClassroomId == null) {
      _showMessage('Sélectionnez une classe.');
      return;
    }

    setState(() => _saving = true);
    try {
      final bytes = await _fetchClassBulletinsPdfBytes(
        classroomId: effectiveClassroomId,
        yearId: yearId,
        term: term,
      );
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur impression bulletins classe: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openNotesFloatingWindow() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Saisie des notes'),
          content: const Text('Choisissez une action.'),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openGradeEntryDialog();
              },
              icon: const Icon(Icons.assignment_outlined),
              label: const Text('Saisir note classe'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openExamEntryDialog();
              },
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Saisir note examen'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openBulletinFloatingWindow() async {
    if (_years.isEmpty) {
      _showMessage('Aucune année scolaire disponible.');
      return;
    }

    final visibleClassrooms = _classroomsForCurrentRole();
    if (visibleClassrooms.isEmpty) {
      _showMessage('Aucune classe disponible.');
      return;
    }

    var selectedClassroom = _selectedClassroom;
    if (selectedClassroom == null ||
        !visibleClassrooms.any(
          (row) => _asInt(row['id']) == selectedClassroom,
        )) {
      selectedClassroom = _asInt(visibleClassrooms.first['id']);
    }

    var selectedYear = _selectedAcademicYear;
    if (selectedYear == null ||
        !_years.any((row) => _asInt(row['id']) == selectedYear)) {
      selectedYear = _asInt(_years.first['id']);
    }

    var selectedTerm = _currentTermOrDefault();
    var search = '';

    final initialStudents = _studentsForClassroom(selectedClassroom)
      ..sort(
        (a, b) => '${a['user_full_name'] ?? ''}'.toLowerCase().compareTo(
          '${b['user_full_name'] ?? ''}'.toLowerCase(),
        ),
      );

    int? selectedStudent = initialStudents.isNotEmpty
        ? _asInt(initialStudents.first['id'])
        : null;
    Future<Uint8List>? previewFuture = selectedStudent == null
        ? null
        : _fetchBulletinPdfBytes(
            studentId: selectedStudent,
            yearId: selectedYear,
            term: selectedTerm,
          );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final classStudents = _studentsForClassroom(selectedClassroom)
              ..sort(
                (a, b) => '${a['user_full_name'] ?? ''}'
                    .toLowerCase()
                    .compareTo('${b['user_full_name'] ?? ''}'.toLowerCase()),
              );

            final visibleStudents = classStudents.where((row) {
              if (search.isEmpty) return true;
              final label =
                  '${row['matricule'] ?? ''} ${(row['user_full_name'] ?? '').toString().trim()}';
              return label.toLowerCase().contains(search);
            }).toList();

            return Dialog(
              insetPadding: const EdgeInsets.all(14),
              child: SizedBox(
                width: 1200,
                height: 760,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Impression bulletins',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: 260,
                            child: DropdownButtonFormField<int>(
                              initialValue: selectedClassroom,
                              decoration: const InputDecoration(
                                labelText: 'Classe',
                              ),
                              items: visibleClassrooms
                                  .map(
                                    (row) => DropdownMenuItem<int>(
                                      value: _asInt(row['id']),
                                      child: Text('${row['name'] ?? 'Classe'}'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedClassroom = value;
                                  final nextStudents =
                                      _studentsForClassroom(
                                        selectedClassroom,
                                      )..sort(
                                        (a, b) => '${a['user_full_name'] ?? ''}'
                                            .toLowerCase()
                                            .compareTo(
                                              '${b['user_full_name'] ?? ''}'
                                                  .toLowerCase(),
                                            ),
                                      );
                                  selectedStudent = nextStudents.isNotEmpty
                                      ? _asInt(nextStudents.first['id'])
                                      : null;
                                  previewFuture = selectedStudent == null
                                      ? null
                                      : _fetchBulletinPdfBytes(
                                          studentId: selectedStudent!,
                                          yearId: selectedYear,
                                          term: selectedTerm,
                                        );
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<int>(
                              initialValue: selectedYear,
                              decoration: const InputDecoration(
                                labelText: 'Année scolaire',
                              ),
                              items: _years
                                  .map(
                                    (row) => DropdownMenuItem<int>(
                                      value: _asInt(row['id']),
                                      child: Text('${row['name'] ?? 'Année'}'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() {
                                  selectedYear = value;
                                  previewFuture = selectedStudent == null
                                      ? null
                                      : _fetchBulletinPdfBytes(
                                          studentId: selectedStudent!,
                                          yearId: selectedYear,
                                          term: selectedTerm,
                                        );
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 170,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedTerm,
                              decoration: const InputDecoration(
                                labelText: 'Période',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'T1',
                                  child: Text('T1'),
                                ),
                                DropdownMenuItem(
                                  value: 'T2',
                                  child: Text('T2'),
                                ),
                                DropdownMenuItem(
                                  value: 'T3',
                                  child: Text('T3'),
                                ),
                              ],
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedTerm = value ?? 'T1';
                                  previewFuture = selectedStudent == null
                                      ? null
                                      : _fetchBulletinPdfBytes(
                                          studentId: selectedStudent!,
                                          yearId: selectedYear,
                                          term: selectedTerm,
                                        );
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          children: [
                            SizedBox(
                              width: 320,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextField(
                                    decoration: const InputDecoration(
                                      labelText: 'Rechercher un élève',
                                      prefixIcon: Icon(Icons.search),
                                    ),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        search = value.trim().toLowerCase();
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.black12,
                                        ),
                                      ),
                                      child: visibleStudents.isEmpty
                                          ? const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(12),
                                                child: Text(
                                                  'Aucun élève trouvé.',
                                                ),
                                              ),
                                            )
                                          : ListView.separated(
                                              itemCount: visibleStudents.length,
                                              separatorBuilder: (_, _) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, index) {
                                                final row =
                                                    visibleStudents[index];
                                                final rowId = _asInt(row['id']);
                                                final selected =
                                                    rowId == selectedStudent;
                                                final label =
                                                    '${row['matricule'] ?? ''} ${(row['user_full_name'] ?? '').toString().trim()}';
                                                return ListTile(
                                                  dense: true,
                                                  selected: selected,
                                                  title: Text(
                                                    label.trim(),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  onTap: () {
                                                    setDialogState(() {
                                                      selectedStudent = rowId;
                                                      previewFuture =
                                                          _fetchBulletinPdfBytes(
                                                            studentId: rowId,
                                                            yearId:
                                                                selectedYear,
                                                            term: selectedTerm,
                                                          );
                                                    });
                                                  },
                                                );
                                              },
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: selectedStudent == null
                                    ? const Center(
                                        child: Text(
                                          'Sélectionnez un élève pour afficher l\'aperçu.',
                                        ),
                                      )
                                    : FutureBuilder<Uint8List>(
                                        future: previewFuture,
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            );
                                          }
                                          if (snapshot.hasError) {
                                            return Center(
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  12,
                                                ),
                                                child: Text(
                                                  'Erreur aperçu: ${snapshot.error}',
                                                ),
                                              ),
                                            );
                                          }

                                          final bytes = snapshot.data;
                                          if (bytes == null || bytes.isEmpty) {
                                            return const Center(
                                              child: Text(
                                                'Aperçu indisponible.',
                                              ),
                                            );
                                          }

                                          return PdfPreview(
                                            build: (_) async => bytes,
                                            allowSharing: false,
                                            allowPrinting: false,
                                            canChangeOrientation: false,
                                            canChangePageFormat: false,
                                            canDebug: false,
                                            maxPageWidth: 780,
                                            initialPageFormat:
                                                PdfPageFormat.a4.landscape,
                                          );
                                        },
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Fermer'),
                          ),
                          FilledButton.icon(
                            onPressed: selectedStudent == null
                                ? null
                                : () async {
                                    Navigator.of(dialogContext).pop();
                                    await _printBulletin(
                                      studentId: selectedStudent,
                                      yearId: selectedYear,
                                      term: selectedTerm,
                                    );
                                  },
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Imprimer élève'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: classStudents.isEmpty
                                ? null
                                : () async {
                                    Navigator.of(dialogContext).pop();
                                    await _printClassBulletins(
                                      classroomId: selectedClassroom,
                                      yearId: selectedYear,
                                      term: selectedTerm,
                                    );
                                  },
                            icon: const Icon(Icons.groups_2_outlined),
                            label: const Text('Imprimer classe entière'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportFilteredNotesCsv(
    List<Map<String, dynamic>> grades,
    Map<int, Map<String, dynamic>> studentById,
    Map<int, Map<String, dynamic>> subjectById,
  ) async {
    if (grades.isEmpty) {
      _showMessage('Aucune note à exporter pour les filtres actuels.');
      return;
    }

    final classroomName =
        (_findById(_classrooms, _selectedClassroom ?? 0)?['name'] ?? 'Toutes')
            .toString();
    final academicYearName =
        (_findById(_years, _selectedAcademicYear ?? 0)?['name'] ?? 'Toutes')
            .toString();
    final period = _currentTermOrDefault();

    setState(() => _saving = true);
    try {
      final buffer = StringBuffer();
      buffer.writeln('Export Notes Filtrees');
      buffer.writeln('Classe;$classroomName');
      buffer.writeln('Annee;$academicYearName');
      buffer.writeln('Periode;$period');
      buffer.writeln('');
      buffer.writeln('Eleve;Matiere;Periode;Note classe');

      for (final grade in grades) {
        final student = studentById[_asInt(grade['student'])];
        final subject = subjectById[_asInt(grade['subject'])];

        final studentLabel =
            '${student?['matricule'] ?? ''} ${(student?['user_full_name'] ?? 'Eleve').toString().trim()}';
        final subjectLabel =
            '${subject?['code'] ?? 'MAT'} ${(subject?['name'] ?? 'Matiere').toString().trim()}';

        final row = [
          _csvCell(studentLabel),
          _csvCell(subjectLabel),
          _csvCell(grade['term']),
          _csvCell(grade['value']),
        ].join(';');
        buffer.writeln(row);
      }

      final fileName =
          'notes_filtrees_${DateTime.now().millisecondsSinceEpoch}.csv';
      final contentWithBom = '\uFEFF${buffer.toString()}';
      final bytes = Uint8List.fromList(utf8.encode(contentWithBom));
      await Printing.sharePdf(bytes: bytes, filename: fileName);

      if (!mounted) return;
      _showMessage('Export Excel (CSV) lancé: $fileName', isSuccess: true);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur export Excel (CSV): $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportFilteredNotesPdf(
    List<Map<String, dynamic>> grades,
    Map<int, Map<String, dynamic>> studentById,
    Map<int, Map<String, dynamic>> subjectById,
  ) async {
    if (grades.isEmpty) {
      _showMessage('Aucune note à exporter pour les filtres actuels.');
      return;
    }

    final classroomName =
        (_findById(_classrooms, _selectedClassroom ?? 0)?['name'] ?? 'Toutes')
            .toString();
    final academicYearName =
        (_findById(_years, _selectedAcademicYear ?? 0)?['name'] ?? 'Toutes')
            .toString();
    final period = _currentTermOrDefault();

    final tableRows = grades.map((grade) {
      final student = studentById[_asInt(grade['student'])];
      final subject = subjectById[_asInt(grade['subject'])];

      return [
        '${student?['matricule'] ?? ''} ${(student?['user_full_name'] ?? 'Eleve').toString().trim()}',
        '${subject?['code'] ?? 'MAT'} ${(subject?['name'] ?? 'Matiere').toString().trim()}',
        '${grade['term'] ?? '-'}',
        '${grade['value'] ?? '-'} /20',
      ];
    }).toList();

    setState(() => _saving = true);
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (context) {
            return [
              pw.Text(
                'Export des notes filtrées',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Classe: $classroomName'),
              pw.Text('Année scolaire: $academicYearName'),
              pw.Text('Période: $period'),
              pw.SizedBox(height: 10),
              pw.TableHelper.fromTextArray(
                headers: const ['Élève', 'Matière', 'Période', 'Note classe'],
                data: tableRows,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ];
          },
        ),
      );

      final bytes = await doc.save();
      final fileName =
          'notes_filtrees_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur export PDF: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEditGradeDialog(Map<String, dynamic> gradeRow) async {
    final gradeId = _asInt(gradeRow['id']);
    if (gradeId <= 0) {
      _showMessage('Impossible de modifier cette note (ID invalide).');
      return;
    }

    var devoirCount = 3;
    final initialScores = _homeworkScoresFromGradeRow(gradeRow);
    if (initialScores.length > devoirCount) {
      devoirCount = initialScores.length;
    }
    final controllers = List.generate(
      devoirCount,
      (index) => TextEditingController(
        text: index < initialScores.length
            ? initialScores[index].toStringAsFixed(2)
            : '',
      ),
    );

    final student = _findById(_students, _asInt(gradeRow['student']));
    final subject = _findById(_subjects, _asInt(gradeRow['subject']));

    List<double> parseScores() {
      final scores = <double>[];
      for (final controller in controllers) {
        final raw = controller.text.trim();
        if (raw.isEmpty) {
          continue;
        }
        final parsed = double.tryParse(raw.replaceAll(',', '.'));
        if (parsed == null || parsed < 0 || parsed > 20) {
          throw const FormatException('INVALID_SCORE');
        }
        scores.add(parsed);
      }
      return scores;
    }

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double? average;
            try {
              average = _averageHomeworkScores(parseScores());
            } catch (_) {
              average = null;
            }

            return AlertDialog(
              title: const Text('Modifier les notes de devoir'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${student?['matricule'] ?? ''} • ${(student?['user_full_name'] ?? '').toString().trim()}',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${subject?['code'] ?? 'MAT'} - ${subject?['name'] ?? ''}',
                    ),
                    const SizedBox(height: 4),
                    Text('Période: ${gradeRow['term'] ?? '-'}'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('Devoirs: $devoirCount'),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              devoirCount += 1;
                              controllers.add(TextEditingController());
                            });
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: devoirCount <= 1
                              ? null
                              : () {
                                  setDialogState(() {
                                    devoirCount -= 1;
                                    final removed = controllers.removeLast();
                                    removed.dispose();
                                  });
                                },
                          icon: const Icon(Icons.remove),
                          label: const Text('Retirer'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (
                            var index = 0;
                            index < controllers.length;
                            index++
                          )
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: SizedBox(
                                width: 84,
                                child: TextField(
                                  controller: controllers[index],
                                  onChanged: (_) => setDialogState(() {}),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: InputDecoration(
                                    labelText: 'D${index + 1}',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      average == null
                          ? 'Note de classe automatique: -'
                          : 'Note de classe automatique: ${average.toStringAsFixed(2)} /20',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () {
                          try {
                            final scores = parseScores();
                            if (scores.isEmpty) {
                              _showMessage(
                                'Ajoutez au moins une note de devoir.',
                              );
                              return;
                            }
                          } catch (_) {
                            _showMessage(
                              'Chaque note doit être numérique entre 0 et 20.',
                            );
                            return;
                          }
                          Navigator.of(dialogContext).pop(true);
                        },
                  child: const Text('Enregistrer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave != true) {
      for (final controller in controllers) {
        controller.dispose();
      }
      return;
    }

    final scores = <double>[];
    try {
      scores.addAll(parseScores());
    } catch (_) {
      for (final controller in controllers) {
        controller.dispose();
      }
      _showMessage('Chaque note doit être numérique entre 0 et 20.');
      return;
    }
    for (final controller in controllers) {
      controller.dispose();
    }

    if (scores.isEmpty) {
      _showMessage('Ajoutez au moins une note de devoir.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .patch('/grades/$gradeId/', data: {'homework_scores': scores});

      if (!mounted) return;
      _showMessage('Note modifiée avec succès.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur modification note: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteGrade(Map<String, dynamic> gradeRow) async {
    final gradeId = _asInt(gradeRow['id']);
    if (gradeId <= 0) {
      _showMessage('Impossible de supprimer cette note (ID invalide).');
      return;
    }

    final student = _findById(_students, _asInt(gradeRow['student']));
    final subject = _findById(_subjects, _asInt(gradeRow['subject']));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer la note'),
          content: Text(
            'Confirmer la suppression de la note de '
            '${student?['user_full_name'] ?? 'cet élève'} en '
            '${subject?['name'] ?? 'matière'} ?',
          ),
          actions: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton.tonal(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete('/grades/$gradeId/');

      if (!mounted) return;
      _showMessage('Note supprimée avec succès.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur suppression note: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshValidationStatus() async {
    final classroom = _selectedClassroom;
    final academicYear = _selectedAcademicYear;
    final term = _currentTermOrDefault();

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
              'term': _currentTermOrDefault(),
              if (validate) 'notes': _validationNotesController.text.trim(),
            },
          );

      if (!mounted) return;
      _showMessage(
        validate
            ? 'Période validée par la direction.'
            : 'Validation retirée. Période réouverte.',
        isSuccess: true,
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

  Future<void> _refreshGrades() async {
    await _loadData();
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

  List<Map<String, dynamic>> _studentsForClassroom(int? classroomId) {
    var pool = _students;

    if (_isTeacherUser) {
      if (_allowedClassroomIds.isEmpty) {
        return const [];
      }
      pool = pool
          .where(
            (row) => _allowedClassroomIds.contains(_asInt(row['classroom'])),
          )
          .toList();
    }

    if (classroomId == null || classroomId <= 0) return pool;
    return pool
        .where((row) => _asInt(row['classroom']) == classroomId)
        .toList();
  }

  List<Map<String, dynamic>> _subjectsForClassroom(int? classroomId) {
    if (classroomId == null || classroomId <= 0) {
      return _subjects;
    }

    final assignedRows = _teacherAssignments.where((row) {
      if (_asInt(row['classroom']) != classroomId) {
        return false;
      }
      if (_isTeacherUser && (_loggedTeacherId ?? 0) > 0) {
        return _asInt(row['teacher']) == _loggedTeacherId;
      }
      return true;
    });

    final assignedSubjectIds = assignedRows
        .map((row) => _asInt(row['subject']))
        .where((id) => id > 0)
        .toSet();

    if (assignedSubjectIds.isEmpty) {
      return const [];
    }

    return _subjects
        .where((row) => assignedSubjectIds.contains(_asInt(row['id'])))
        .toList();
  }

  List<Map<String, dynamic>> _classroomsForCurrentRole() {
    if (!_isTeacherUser) {
      return _classrooms;
    }
    if (_allowedClassroomIds.isEmpty) {
      return const [];
    }
    return _classrooms
        .where((row) => _allowedClassroomIds.contains(_asInt(row['id'])))
        .toList();
  }

  String _extractFriendlyError(Object error) {
    if (error is DioException) {
      return _extractDioErrorMessage(error);
    }

    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.replaceFirst('Exception: ', '');
    }
    return raw;
  }

  String _extractDioErrorMessage(DioException error) {
    final data = error.response?.data;

    if (data is Map<String, dynamic>) {
      final detail = data['detail']?.toString().trim() ?? '';
      if (detail.isNotEmpty) {
        return detail;
      }

      final parts = <String>[];
      data.forEach((key, value) {
        if (value is List && value.isNotEmpty) {
          parts.add('$key: ${value.first}');
          return;
        }
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          parts.add('$key: $text');
        }
      });

      if (parts.isNotEmpty) {
        return parts.join(' | ');
      }
    }

    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }

    return error.message?.trim().isNotEmpty == true
        ? error.message!.trim()
        : 'Erreur serveur';
  }

  Map<String, dynamic>? _findById(List<Map<String, dynamic>> rows, int id) {
    for (final row in rows) {
      if (_asInt(row['id']) == id) {
        return row;
      }
    }
    return null;
  }

  String _normalizeTerm(dynamic value) {
    final raw = (value ?? '').toString().trim().toUpperCase();
    if (raw.isEmpty) return '';

    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) {
      return 'T$digits';
    }

    return raw.replaceAll(' ', '');
  }

  String _apiDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return RefreshIndicator(
        onRefresh: _refreshGrades,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: const [
            SizedBox(
              height: 460,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final visibleClassrooms = _classroomsForCurrentRole();

    final studentById = {for (final s in _students) _asInt(s['id']): s};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};

    final validationLabel = _isValidated ? 'Validee' : 'Non validee';
    final validationBy = (_validationStatus?['validated_by_name'] ?? '')
        .toString();
    final validationDate = (_validationStatus?['validated_at'] ?? '-')
        .toString();

    final termFilter = _normalizeTerm(_termController.text);
    final search = _gradesSearchController.text.trim().toLowerCase();

    final scopedGrades = _grades.where((grade) {
      final matchesClass =
          _selectedClassroom == null ||
          _asInt(grade['classroom']) == _selectedClassroom;
      final matchesYear =
          _selectedAcademicYear == null ||
          _asInt(grade['academic_year']) == _selectedAcademicYear;
      final matchesTerm =
          termFilter.isEmpty || _normalizeTerm(grade['term']) == termFilter;

      if (!(matchesClass && matchesYear && matchesTerm)) {
        return false;
      }

      if (search.isEmpty) {
        return true;
      }

      final student = studentById[_asInt(grade['student'])];
      final subject = subjectById[_asInt(grade['subject'])];

      final studentText =
          '${student?['matricule'] ?? ''} ${student?['user_full_name'] ?? ''}'
              .toLowerCase();
      final subjectText = '${subject?['code'] ?? ''} ${subject?['name'] ?? ''}'
          .toLowerCase();

      return studentText.contains(search) || subjectText.contains(search);
    }).toList()..sort((a, b) => _asInt(b['id']).compareTo(_asInt(a['id'])));

    final scopedAverage = scopedGrades.isEmpty
        ? 0.0
        : (scopedGrades.fold<double>(
                0.0,
                (sum, grade) => sum + _toDouble(grade['value']),
              ) /
              scopedGrades.length);

    final notesTotalPages = scopedGrades.isEmpty
        ? 1
        : ((scopedGrades.length + _notesRowsPerPage - 1) ~/ _notesRowsPerPage);
    final notesCurrentPage = notesTotalPages <= 0
        ? 1
        : math.min(math.max(_notesPage, 1), notesTotalPages);
    final notesStart = scopedGrades.isEmpty
        ? 0
        : (notesCurrentPage - 1) * _notesRowsPerPage;
    final notesEnd = scopedGrades.isEmpty
        ? 0
        : math.min(notesStart + _notesRowsPerPage, scopedGrades.length);
    final pagedGrades = scopedGrades.isEmpty
        ? <Map<String, dynamic>>[]
        : scopedGrades.sublist(notesStart, notesEnd);

    final validationPanel = _sectionCard(
      title: 'Validation direction',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isValidated
                ? 'Statut: $validationLabel • Par: ${validationBy.isEmpty ? 'N/A' : validationBy} • Date: $validationDate'
                : 'Statut: $validationLabel',
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
                child: const Text('Valider periode'),
              ),
              FilledButton.tonal(
                onPressed: _saving
                    ? null
                    : () => _toggleValidation(validate: false),
                child: const Text('Reouvrir periode'),
              ),
            ],
          ),
        ],
      ),
    );

    final entryPanel = _sectionCard(
      title: 'Saisie des notes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'La saisie se fait en lot: ajoutez des notes de devoir (D1, D2, D3...) puis la note de classe est calculée automatiquement.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: (_saving || _isValidated)
                    ? null
                    : _openGradeEntryDialog,
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Saisir note classe'),
              ),
              FilledButton.tonalIcon(
                onPressed: (_saving || _isValidated)
                    ? null
                    : _openExamEntryDialog,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Saisir note examen'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isValidated)
            const Text(
              'Période validée: la fenêtre de saisie reste verrouillée.',
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedClassroom,
            decoration: const InputDecoration(labelText: 'Classe'),
            items: visibleClassrooms
                .map(
                  (c) => DropdownMenuItem<int>(
                    value: _asInt(c['id']),
                    child: Text('${c['name']} (ID ${c['id']})'),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() {
                _selectedClassroom = v;
                _notesPage = 1;
                final scopedStudents = _studentsForClassroom(v);
                if (scopedStudents.isNotEmpty) {
                  _selectedStudent = _asInt(scopedStudents.first['id']);
                }
              });
              _refreshValidationStatus();
              _reloadGradesForCurrentFilters();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _selectedAcademicYear,
            decoration: const InputDecoration(labelText: 'Annee scolaire'),
            items: _years
                .map(
                  (y) => DropdownMenuItem<int>(
                    value: _asInt(y['id']),
                    child: Text('${y['name']}'),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() {
                _selectedAcademicYear = v;
                _notesPage = 1;
              });
              _refreshValidationStatus();
              _reloadGradesForCurrentFilters();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _currentTermOrDefault(),
            decoration: const InputDecoration(labelText: 'Période'),
            items: const [
              DropdownMenuItem(value: 'T1', child: Text('T1')),
              DropdownMenuItem(value: 'T2', child: Text('T2')),
              DropdownMenuItem(value: 'T3', child: Text('T3')),
            ],
            onChanged: (value) {
              setState(() {
                _termController.text = value ?? 'T1';
                _notesPage = 1;
              });
              _refreshValidationStatus();
              _reloadGradesForCurrentFilters();
            },
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: (_saving || _isValidated) ? null : _recalculateRanking,
            child: const Text('Recalculer classement'),
          ),
        ],
      ),
    );

    final bulletinPanel = _sectionCard(
      title: 'Bulletin scolaire',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Utilisez le bouton flottant en bas a droite pour ouvrir la fenetre d\'aperçu et impression des bulletins par classe.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Selection actuelle: ${_findById(_classrooms, _selectedClassroom ?? 0)?['name'] ?? '-'} • ${_findById(_years, _selectedAcademicYear ?? 0)?['name'] ?? '-'} • ${_currentTermOrDefault()}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );

    final latestGradesPanel = _sectionCard(
      title: 'Dernieres notes (classe/période sélectionnées)',
      child: scopedGrades.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucune note enregistree'),
            )
          : SizedBox(
              height: 740,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricChip('Filtrées', '${scopedGrades.length}'),
                      _metricChip('Moyenne', scopedAverage.toStringAsFixed(2)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _gradesSearchController,
                    onChanged: (_) => setState(() => _notesPage = 1),
                    decoration: InputDecoration(
                      labelText: 'Rechercher élève / matière',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _gradesSearchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _gradesSearchController.clear();
                                setState(() => _notesPage = 1);
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _exportFilteredNotesCsv(
                                scopedGrades,
                                studentById,
                                subjectById,
                              ),
                        icon: const Icon(Icons.grid_on_outlined),
                        label: const Text('Exporter Excel (CSV)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _exportFilteredNotesPdf(
                                scopedGrades,
                                studentById,
                                subjectById,
                              ),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Exporter PDF'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Affichage ${notesStart + 1}-$notesEnd sur ${scopedGrades.length} notes',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: DropdownButtonFormField<int>(
                          initialValue: _notesRowsPerPage,
                          isDense: true,
                          decoration: const InputDecoration(
                            labelText: 'Lignes',
                          ),
                          items: const [8, 12, 20, 30]
                              .map(
                                (value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('$value'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _notesRowsPerPage = value;
                              _notesPage = 1;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    child: Row(
                      children: const [
                        Expanded(flex: 4, child: Text('Élève')),
                        Expanded(flex: 3, child: Text('Matière')),
                        Expanded(
                          flex: 2,
                          child: Text('Période', textAlign: TextAlign.center),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Note classe',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(
                          width: 96,
                          child: Text('Actions', textAlign: TextAlign.center),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: pagedGrades.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final grade = pagedGrades[index];
                        final student = studentById[_asInt(grade['student'])];
                        final subject = subjectById[_asInt(grade['subject'])];
                        final studentLabel =
                            '${student?['matricule'] ?? ''} • ${student?['user_full_name'] ?? 'Eleve'}';
                        final subjectLabel =
                            '${subject?['code'] ?? 'MAT'} • ${subject?['name'] ?? 'Matiere'}';

                        return Card(
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    studentLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    subjectLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${grade['term']}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${grade['value']}/20',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                SizedBox(
                                  width: 96,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        tooltip: 'Modifier',
                                        onPressed: (_saving || _isValidated)
                                            ? null
                                            : () => _openEditGradeDialog(grade),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Supprimer',
                                        onPressed: (_saving || _isValidated)
                                            ? null
                                            : () => _deleteGrade(grade),
                                        icon: const Icon(Icons.delete_outline),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Page $notesCurrentPage / $notesTotalPages',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: notesCurrentPage > 1
                            ? () {
                                setState(
                                  () => _notesPage = notesCurrentPage - 1,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Précédent'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: notesCurrentPage < notesTotalPages
                            ? () {
                                setState(
                                  () => _notesPage = notesCurrentPage + 1,
                                );
                              }
                            : null,
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Suivant'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refreshGrades,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 92),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _loadData,
                    icon: const Icon(Icons.sync),
                    label: const Text('Actualiser'),
                  ),
                ],
              ),
              if (_saving) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metricChip('Eleves', '${_students.length}'),
                    _metricChip('Matieres', '${_subjects.length}'),
                    _metricChip('Classes', '${visibleClassrooms.length}'),
                    _metricChip('Annees', '${_years.length}'),
                    _metricChip('Notes', '${_grades.length}'),
                    _metricChip('Validation', validationLabel),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 1120;
                  final leftPanel = Column(
                    children: [
                      validationPanel,
                      const SizedBox(height: 12),
                      entryPanel,
                      const SizedBox(height: 12),
                      bulletinPanel,
                    ],
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: leftPanel),
                        const SizedBox(width: 12),
                        Expanded(flex: 5, child: latestGradesPanel),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      leftPanel,
                      const SizedBox(height: 12),
                      latestGradesPanel,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'fab_saisir_notes',
                onPressed: _saving ? null : _openNotesFloatingWindow,
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text('Saisir notes'),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'fab_imprimer_bulletins',
                onPressed: _saving ? null : _openBulletinFloatingWindow,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Imprimer bulletins'),
              ),
            ],
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

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _csvCell(dynamic value) {
    final raw = (value ?? '').toString().replaceAll('"', '""');
    final flattened = raw.replaceAll('\n', ' ').replaceAll('\r', ' ');
    final safe = RegExp(r'^[=+\-@]').hasMatch(flattened)
        ? "'$flattened"
        : flattened;
    return '"$safe"';
  }

  Uint8List _toUint8List(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) return Uint8List.fromList(data.cast<int>());
    throw Exception('Réponse binaire invalide');
  }
}
