import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'timetable_workload.dart';

class TimetablePage extends ConsumerStatefulWidget {
  const TimetablePage({super.key});

  @override
  ConsumerState<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends ConsumerState<TimetablePage> {
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _assignments = [];
  List<Map<String, dynamic>> _scheduleSlots = [];
  List<Map<String, dynamic>> _timetablePublications = [];

  final _slotsSearchController = TextEditingController();
  int? _selectedClassroom;
  String _viewMode = 'classroom';
  String _teacherScope = 'selected';
  String _mobileDayFilter = 'ALL';
  bool _scheduleApiSupported = true;
  String _activeApiBaseUrl = ApiConstants.baseUrl;
  bool _usingCustomApiBaseUrl = false;
  bool _apiUrlResetAttempted = false;

  static const List<String> _dayOrder = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
  ];

  static const Map<String, String> _dayLabels = {
    'MON': 'Lundi',
    'TUE': 'Mardi',
    'WED': 'Mercredi',
    'THU': 'Jeudi',
    'FRI': 'Vendredi',
    'SAT': 'Samedi',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _slotsSearchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadRowsSafely(
    Dio dio, {
    required String path,
    required List<String> failures,
  }) async {
    try {
      final response = await dio.get(path);
      return _extractRows(response.data);
    } on DioException catch (error) {
      final endpoint = error.requestOptions.path.isNotEmpty
          ? error.requestOptions.path
          : path;
      final status = error.response?.statusCode;
      failures.add(status == null ? endpoint : '$endpoint ($status)');
      return <Map<String, dynamic>>[];
    } catch (_) {
      failures.add(path);
      return <Map<String, dynamic>>[];
    }
  }

  Future<bool?> _detectScheduleApiSupportFromSchema(Dio dio) async {
    try {
      final response = await dio.get(
        '/schema/',
        queryParameters: const {'format': 'json'},
        options: Options(validateStatus: (status) => (status ?? 0) < 500),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 400) {
        return null;
      }

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final paths = data['paths'];
        if (paths is Map) {
          return paths.containsKey('/api/teacher-schedule-slots/') ||
              paths.containsKey('/teacher-schedule-slots/');
        }
      }

      final raw = data?.toString() ?? '';
      if (raw.isNotEmpty) {
        return raw.contains('teacher-schedule-slots');
      }
    } catch (_) {
      // Ignore schema parsing failures and keep fallback heuristics.
    }
    return null;
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final storedBaseUrl = await ref.read(tokenStorageProvider).apiBaseUrl();
    final activeApiUrl =
        (storedBaseUrl != null && storedBaseUrl.trim().isNotEmpty)
        ? storedBaseUrl
        : ApiConstants.baseUrl;
    final failures = <String>[];

    try {
      final results = await Future.wait([
        _loadRowsSafely(dio, path: '/teachers/', failures: failures),
        _loadRowsSafely(dio, path: '/subjects/', failures: failures),
        _loadRowsSafely(dio, path: '/classrooms/', failures: failures),
        _loadRowsSafely(dio, path: '/teacher-assignments/', failures: failures),
        _loadRowsSafely(
          dio,
          path: '/teacher-schedule-slots/',
          failures: failures,
        ),
        _loadRowsSafely(
          dio,
          path: '/timetable-publications/',
          failures: failures,
        ),
      ]);

      if (!mounted) return;

      final hasSlotEndpoint404 = failures.any(
        (entry) =>
            entry.contains('/teacher-schedule-slots/') &&
            entry.contains('(404)'),
      );
      final hasPublicationEndpoint404 = failures.any(
        (entry) =>
            entry.contains('/timetable-publications/') &&
            entry.contains('(404)'),
      );
      var scheduleApiSupported =
          !(hasSlotEndpoint404 || hasPublicationEndpoint404);

      final schemaSupport = await _detectScheduleApiSupportFromSchema(dio);
      if (schemaSupport != null) {
        scheduleApiSupported = schemaSupport;
      }

      final hasStoredCustomApi =
          storedBaseUrl != null && storedBaseUrl.trim().isNotEmpty;
      final looksLikeLegacyPlanningApi =
          hasSlotEndpoint404 &&
          hasPublicationEndpoint404 &&
          results[0].isNotEmpty &&
          results[3].isNotEmpty;
      if (looksLikeLegacyPlanningApi &&
          hasStoredCustomApi &&
          !_apiUrlResetAttempted) {
        _apiUrlResetAttempted = true;
        await ref.read(tokenStorageProvider).clearApiBaseUrl();
        if (!mounted) return;
        _showMessage(
          'API personnalisée obsolète détectée pour le module planning. '
          'Nouvelle tentative avec l\'URL API par défaut...',
        );
        await _loadData();
        return;
      }

      setState(() {
        _teachers = results[0];
        _subjects = results[1];
        _classrooms = results[2];
        _assignments = results[3];
        _scheduleSlots = results[4];
        _timetablePublications = results[5];
        _activeApiBaseUrl = activeApiUrl;
        _usingCustomApiBaseUrl = hasStoredCustomApi;
        _scheduleApiSupported = scheduleApiSupported;

        final classIds = _classrooms.map((row) => _asInt(row['id'])).toSet();
        if (_selectedClassroom == null ||
            !classIds.contains(_selectedClassroom)) {
          _selectedClassroom = _classrooms.isNotEmpty
              ? _asInt(_classrooms.first['id'])
              : null;
        }
      });

      final allEndpoints404 =
          failures.length >= 6 &&
          failures.every((entry) => entry.contains('(404)'));
      if (allEndpoints404 && !_apiUrlResetAttempted) {
        _apiUrlResetAttempted = true;
        await ref.read(tokenStorageProvider).clearApiBaseUrl();
        if (!mounted) return;
        _showMessage(
          'URL API personnalisée introuvable, tentative automatique avec l\'URL par défaut...',
        );
        await _loadData();
        return;
      }

      if (failures.isEmpty) {
        _apiUrlResetAttempted = false;
      }

      if (failures.isNotEmpty && mounted) {
        final endpoints = failures.toSet().toList()..sort();
        _showMessage(
          'Certaines routes planning sont indisponibles: ${endpoints.join(', ')}. '
          'Vérifiez l\'URL API (Connexion > Configuration API).',
        );
      }

      if (!scheduleApiSupported && mounted) {
        _showMessage(
          'Votre backend ne supporte pas encore les horaires '
          '(endpoint manquant). API active: $_activeApiBaseUrl',
        );
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'Erreur chargement emploi du temps: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCurrentClassCsv() async {
    final classroomId = _selectedClassroom;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionnez une classe avant export.');
      return;
    }

    final assignmentById = _assignmentById();
    final slotsByClass = _slotsByClass(assignmentById);
    final classSlots = slotsByClass[classroomId] ?? <Map<String, dynamic>>[];

    if (classSlots.isEmpty) {
      _showMessage('Aucun horaire planifié pour cette classe.');
      return;
    }

    final matrix = _classMatrix(classSlots);
    final ranges = matrix.keys.toList()
      ..sort((a, b) => _rangeStartMinutes(a).compareTo(_rangeStartMinutes(b)));

    final className = _classNameById(classroomId);
    final buffer = StringBuffer();
    buffer.writeln('Emploi du temps (grille hebdomadaire)');
    buffer.writeln('Classe;${_csvCell(className)}');
    buffer.writeln('Genere le;${_csvCell(_dateTimeLabel(DateTime.now()))}');
    buffer.writeln('');
    buffer.writeln('Horaire;Lundi;Mardi;Mercredi;Jeudi;Vendredi;Samedi');

    for (final range in ranges) {
      final dayMap =
          matrix[range] ?? const <String, List<Map<String, dynamic>>>{};
      final rowCells = [
        _csvCell(range),
        ..._dayOrder.map((dayCode) {
          final slots = dayMap[dayCode] ?? const <Map<String, dynamic>>[];
          return _csvCell(_slotsExportCell(slots));
        }),
      ];
      buffer.writeln(rowCells.join(';'));
    }

    final bytes = Uint8List.fromList(utf8.encode('\uFEFF${buffer.toString()}'));
    final fileName =
        'emploi_du_temps_${_slugify(className)}_${DateTime.now().millisecondsSinceEpoch}.csv';

    await Printing.sharePdf(bytes: bytes, filename: fileName);
    _showMessage('Export Excel (CSV) lancé: $fileName', isSuccess: true);
  }

  Future<void> _refreshTimetable() async {
    await _loadData();
  }

  Map<int, Map<String, dynamic>> _publicationByClassroom() {
    final map = <int, Map<String, dynamic>>{};
    for (final row in _timetablePublications) {
      final classId = _asInt(row['classroom']);
      if (classId <= 0) continue;
      map[classId] = row;
    }
    return map;
  }

  bool _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = (value ?? '').toString().trim().toLowerCase();
    return {'1', 'true', 'yes', 'on'}.contains(text);
  }

  bool _isClassLockedById(int? classId) {
    if (classId == null || classId <= 0) return false;
    final publication = _publicationByClassroom()[classId];
    return _asBool(publication?['is_locked']);
  }

  String _publicationLabel(Map<String, dynamic>? publication) {
    if (publication == null) return 'Brouillon';
    final published = _asBool(publication['is_published']);
    final locked = _asBool(publication['is_locked']);
    if (!published) return 'Brouillon';
    if (locked) return 'Publié • Verrouillé';
    return 'Publié';
  }

  Future<void> _publishSelectedClass({required bool lockAfterPublish}) async {
    if (!_requireScheduleApiSupported('publication du planning')) {
      return;
    }

    final classId = _selectedClassroom;
    if (classId == null || classId <= 0) {
      _showMessage('Sélectionnez une classe.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            '/teacher-schedule-slots/publish_class/',
            data: {'classroom': classId, 'lock': lockAfterPublish},
          );

      if (!mounted) return;
      _showMessage(
        lockAfterPublish
            ? 'Planning publié et verrouillé.'
            : 'Planning publié sans verrouillage.',
        isSuccess: true,
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur publication: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setSelectedClassLock({required bool lock}) async {
    if (!_requireScheduleApiSupported('verrouillage du planning')) {
      return;
    }

    final classId = _selectedClassroom;
    if (classId == null || classId <= 0) {
      _showMessage('Sélectionnez une classe.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            lock
                ? '/teacher-schedule-slots/lock_class/'
                : '/teacher-schedule-slots/unlock_class/',
            data: {'classroom': classId},
          );

      if (!mounted) return;
      _showMessage(
        lock ? 'Planning verrouillé.' : 'Planning déverrouillé.',
        isSuccess: true,
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur verrouillage: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unpublishSelectedClass() async {
    if (!_requireScheduleApiSupported('retour en brouillon')) {
      return;
    }

    final classId = _selectedClassroom;
    if (classId == null || classId <= 0) {
      _showMessage('Sélectionnez une classe.');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(dioProvider)
          .post(
            '/teacher-schedule-slots/unpublish_class/',
            data: {'classroom': classId},
          );

      if (!mounted) return;
      _showMessage('Planning remis en brouillon.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur retour brouillon: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Uint8List _toUint8List(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) return Uint8List.fromList(data.cast<int>());
    throw Exception('Réponse binaire invalide');
  }

  Future<void> _downloadTimetableBinary({
    required String endpoint,
    required String filename,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (!_requireScheduleApiSupported('export du planning')) {
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await ref
          .read(dioProvider)
          .get(
            endpoint,
            queryParameters: queryParameters,
            options: Options(responseType: ResponseType.bytes),
          );

      final bytes = _toUint8List(response.data);
      await Printing.sharePdf(bytes: bytes, filename: filename);

      if (!mounted) return;
      _showMessage('Export lancé: $filename', isSuccess: true);
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur export: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _exportGlobalXlsx() async {
    await _downloadTimetableBinary(
      endpoint: '/teacher-schedule-slots/export_excel/',
      filename: 'planning_global_multi_classes.xlsx',
    );
  }

  Future<void> _exportGlobalPdf() async {
    await _downloadTimetableBinary(
      endpoint: '/teacher-schedule-slots/export_pdf/',
      filename: 'planning_global_multi_classes.pdf',
    );
  }

  Future<void> _exportSelectedClassXlsx() async {
    final classId = _selectedClassroom;
    if (classId == null || classId <= 0) {
      _showMessage('Sélectionnez une classe avant export XLSX.');
      return;
    }

    await _downloadTimetableBinary(
      endpoint: '/teacher-schedule-slots/export_excel/',
      filename: 'planning_classe_${classId}_xlsx.xlsx',
      queryParameters: {'classroom': classId},
    );
  }

  Future<void> _printSelectedClassPdfFromBackend() async {
    if (!_requireScheduleApiSupported('impression PDF')) {
      return;
    }

    final classId = _selectedClassroom;
    if (classId == null || classId <= 0) {
      _showMessage('Sélectionnez une classe avant impression.');
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await ref
          .read(dioProvider)
          .get(
            '/teacher-schedule-slots/export_pdf/',
            queryParameters: {'classroom': classId},
            options: Options(responseType: ResponseType.bytes),
          );

      final bytes = _toUint8List(response.data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur impression PDF: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openDuplicateScheduleDialog() async {
    if (!_requireScheduleApiSupported('duplication de planning')) {
      return;
    }

    if (_classrooms.length < 2) {
      _showMessage(
        'Au moins deux classes sont nécessaires pour la duplication.',
      );
      return;
    }

    int sourceClass = _selectedClassroom ?? _asInt(_classrooms.first['id']);
    int targetClass = _asInt(_classrooms.first['id']);
    if (targetClass == sourceClass && _classrooms.length > 1) {
      targetClass = _asInt(_classrooms[1]['id']);
    }

    var overwrite = false;
    var keepRoom = true;
    final selectedDays = <String>{..._dayOrder};

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Duplication intelligente du planning'),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: sourceClass,
                      decoration: const InputDecoration(
                        labelText: 'Classe source',
                      ),
                      items: _classrooms
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _asInt(row['id']),
                              child: Text((row['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          sourceClass = value;
                          if (targetClass == sourceClass) {
                            final alternative = _classrooms
                                .map((row) => _asInt(row['id']))
                                .firstWhere(
                                  (id) => id != sourceClass,
                                  orElse: () => sourceClass,
                                );
                            targetClass = alternative;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: targetClass,
                      decoration: const InputDecoration(
                        labelText: 'Classe cible',
                      ),
                      items: _classrooms
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _asInt(row['id']),
                              child: Text((row['name'] ?? '').toString()),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => targetClass = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _dayOrder.map((dayCode) {
                        return FilterChip(
                          selected: selectedDays.contains(dayCode),
                          label: Text(_dayLabel(dayCode)),
                          onSelected: (enabled) {
                            setDialogState(() {
                              if (enabled) {
                                selectedDays.add(dayCode);
                              } else {
                                selectedDays.remove(dayCode);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: overwrite,
                      onChanged: (value) =>
                          setDialogState(() => overwrite = value),
                      title: const Text(
                        'Remplacer les horaires existants cible',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: keepRoom,
                      onChanged: (value) =>
                          setDialogState(() => keepRoom = value),
                      title: const Text('Conserver les salles'),
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
                          if (sourceClass == targetClass) {
                            _showMessage(
                              'La classe source et la classe cible doivent être différentes.',
                            );
                            return;
                          }
                          if (selectedDays.isEmpty) {
                            _showMessage('Sélectionnez au moins un jour.');
                            return;
                          }
                          Navigator.of(dialogContext).pop(true);
                        },
                  child: const Text('Dupliquer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await ref
          .read(dioProvider)
          .post(
            '/teacher-schedule-slots/duplicate_schedule/',
            data: {
              'source_classroom': sourceClass,
              'target_classroom': targetClass,
              'days': selectedDays.toList()..sort(),
              'overwrite': overwrite,
              'keep_room': keepRoom,
            },
          );

      final payload = Map<String, dynamic>.from(response.data as Map);
      final created = _asInt(payload['created']);
      final updated = _asInt(payload['updated']);
      final skippedConflicts = _asInt(payload['skipped_conflicts']);
      final skippedUnmapped = _asInt(payload['skipped_unmapped']);

      if (!mounted) return;
      _showMessage(
        'Duplication terminée: créés $created, mis à jour $updated, '
        'conflits $skippedConflicts, non mappés $skippedUnmapped.',
        isSuccess: true,
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage('Erreur duplication: ${_extractErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  List<String> _predictSlotConflicts({
    required int assignmentId,
    required String dayCode,
    required TimeOfDay start,
    required TimeOfDay end,
    required String room,
    int? excludeSlotId,
  }) {
    final assignmentById = _assignmentById();
    final selected = assignmentById[assignmentId];
    if (selected == null) return const <String>[];

    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final selectedClassId = _asInt(selected['classroom']);
    final selectedTeacherId = _asInt(selected['teacher']);
    final selectedRoom = room.trim().toLowerCase();

    final messages = <String>{};
    for (final slot in _scheduleSlots) {
      final slotId = _asInt(slot['id']);
      if (excludeSlotId != null && slotId == excludeSlotId) {
        continue;
      }

      final slotDay = (slot['day_of_week'] ?? '').toString();
      if (slotDay != dayCode) {
        continue;
      }

      final slotStart = _timeToMinutes(slot['start_time']);
      final slotEnd = _timeToMinutes(slot['end_time']);
      final isOverlap = slotStart < endMinutes && slotEnd > startMinutes;
      if (!isOverlap) {
        continue;
      }

      final otherAssignment = assignmentById[_asInt(slot['assignment'])];
      if (otherAssignment == null) {
        continue;
      }

      final label =
          '${_hhmm(slot['start_time'])}-${_hhmm(slot['end_time'])} • '
          '${otherAssignment['subjectCode']} '
          '(${_teacherDisplayLabel(otherAssignment['teacherName'], otherAssignment['teacherCode'])})';

      final otherClassId = _asInt(otherAssignment['classroom']);
      if (otherClassId == selectedClassId) {
        messages.add('Conflit classe: $label');
      }

      final otherTeacherId = _asInt(otherAssignment['teacher']);
      if (otherTeacherId == selectedTeacherId) {
        messages.add('Conflit enseignant: $label');
      }

      final otherRoom = (slot['room'] ?? '').toString().trim().toLowerCase();
      if (selectedRoom.isNotEmpty &&
          otherRoom.isNotEmpty &&
          selectedRoom == otherRoom) {
        messages.add('Conflit salle: $label');
      }
    }

    return messages.toList()..sort();
  }

  String _extractErrorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        final nonFieldErrors = data['non_field_errors'];
        if (nonFieldErrors is List && nonFieldErrors.isNotEmpty) {
          return nonFieldErrors.map((item) => item.toString()).join(' | ');
        }

        final detail = data['detail'];
        if (detail != null && detail.toString().trim().isNotEmpty) {
          return detail.toString();
        }

        for (final entry in data.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return value.map((item) => item.toString()).join(' | ');
          }
          if (value is String && value.trim().isNotEmpty) {
            return value;
          }
        }
      }

      final status = error.response?.statusCode;
      if (status != null) {
        final endpoint = error.requestOptions.path;
        if (endpoint.trim().isNotEmpty) {
          return 'HTTP $status sur $endpoint';
        }
        return 'HTTP $status';
      }

      final message = error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }

    return error.toString();
  }

  Future<void> _openSlotDialog({
    Map<String, dynamic>? slot,
    int? forceClassroomId,
  }) async {
    if (!_requireScheduleApiSupported('gestion des horaires')) {
      return;
    }

    final classroomId = forceClassroomId ?? _selectedClassroom;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionnez une classe avant d\'ajouter un horaire.');
      return;
    }

    if (_isClassLockedById(classroomId)) {
      _showMessage(
        'Emploi du temps verrouillé pour cette classe. Déverrouillez avant modification.',
      );
      return;
    }

    final assignmentById = _assignmentById();
    final assignmentsByClass = _assignmentsByClass(assignmentById);
    final classAssignments =
        assignmentsByClass[classroomId] ?? <Map<String, dynamic>>[];

    if (classAssignments.isEmpty) {
      _showMessage(
        'Aucune affectation disponible pour cette classe. Créez d\'abord une affectation.',
      );
      return;
    }

    var selectedAssignment = _asInt(slot?['assignment']);
    final assignmentIds = classAssignments
        .map((row) => _asInt(row['id']))
        .toSet();
    if (selectedAssignment <= 0 ||
        !assignmentIds.contains(selectedAssignment)) {
      selectedAssignment = _asInt(classAssignments.first['id']);
    }

    var selectedDay = (slot?['day_of_week'] ?? _dayOrder.first).toString();
    if (!_dayOrder.contains(selectedDay)) {
      selectedDay = _dayOrder.first;
    }

    final startController = TextEditingController(
      text: _hhmm(slot?['start_time']),
    );
    final endController = TextEditingController(text: _hhmm(slot?['end_time']));
    final roomController = TextEditingController(
      text: (slot?['room'] ?? '').toString(),
    );
    final isEdit = slot != null;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        Future<void> pickTime(TextEditingController controller) async {
          final parsed = _parseTimeOfDay(controller.text.trim());
          final picked = await showTimePicker(
            context: dialogContext,
            initialTime: parsed ?? const TimeOfDay(hour: 8, minute: 0),
          );
          if (picked != null) {
            controller.text = _formatTimeOfDay(picked);
          }
        }

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            List<String> computeDialogConflicts() {
              final start = _parseTimeOfDay(startController.text.trim());
              final end = _parseTimeOfDay(endController.text.trim());
              if (start == null || end == null) {
                return const <String>[];
              }

              final startMinutes = start.hour * 60 + start.minute;
              final endMinutes = end.hour * 60 + end.minute;
              if (endMinutes <= startMinutes) {
                return const <String>[];
              }

              final excludeSlotId = isEdit
                  ? _asInt(slot['slotId'] ?? slot['id'])
                  : null;
              return _predictSlotConflicts(
                assignmentId: selectedAssignment,
                dayCode: selectedDay,
                start: start,
                end: end,
                room: roomController.text.trim(),
                excludeSlotId: excludeSlotId,
              );
            }

            final dialogConflicts = computeDialogConflicts();

            return AlertDialog(
              title: Text(
                isEdit ? 'Modifier un horaire' : 'Ajouter un horaire',
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Classe: ${_classNameById(classroomId)}'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: selectedAssignment,
                      decoration: const InputDecoration(
                        labelText: 'Affectation (matière / enseignant)',
                      ),
                      items: classAssignments
                          .map(
                            (row) => DropdownMenuItem<int>(
                              value: _asInt(row['id']),
                              child: Text(
                                '${row['subjectCode']} - ${row['subjectName']} • '
                                '${_teacherDisplayLabel(row['teacherName'], row['teacherCode'])}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedAssignment = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDay,
                      decoration: const InputDecoration(labelText: 'Jour'),
                      items: _dayOrder
                          .map(
                            (dayCode) => DropdownMenuItem<String>(
                              value: dayCode,
                              child: Text(_dayLabel(dayCode)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedDay = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: startController,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Heure début (HH:MM)',
                              suffixIcon: IconButton(
                                onPressed: () => pickTime(startController),
                                icon: const Icon(Icons.access_time),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: endController,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Heure fin (HH:MM)',
                              suffixIcon: IconButton(
                                onPressed: () => pickTime(endController),
                                icon: const Icon(Icons.access_time_filled),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: roomController,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Salle (optionnel)',
                      ),
                    ),
                    if (dialogConflicts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Conflits détectés',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            ...dialogConflicts
                                .take(5)
                                .map(
                                  (message) => Text(
                                    '- $message',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
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
                          final start = _parseTimeOfDay(
                            startController.text.trim(),
                          );
                          final end = _parseTimeOfDay(
                            endController.text.trim(),
                          );

                          if (start == null || end == null) {
                            _showMessage(
                              'Heures invalides. Format attendu: HH:MM',
                            );
                            return;
                          }

                          final startMinutes = start.hour * 60 + start.minute;
                          final endMinutes = end.hour * 60 + end.minute;
                          if (endMinutes <= startMinutes) {
                            _showMessage(
                              'L\'heure de fin doit être après l\'heure de début.',
                            );
                            return;
                          }

                          if (dialogConflicts.isNotEmpty) {
                            _showMessage(
                              'Conflits détectés. Ajustez l\'horaire avant validation.',
                            );
                            return;
                          }

                          Navigator.of(dialogContext).pop(true);
                        },
                  child: Text(isEdit ? 'Modifier' : 'Ajouter'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) {
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final start = _parseTimeOfDay(startController.text.trim());
    final end = _parseTimeOfDay(endController.text.trim());

    if (start == null || end == null) {
      _showMessage('Heures invalides. Format attendu: HH:MM');
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (endMinutes <= startMinutes) {
      _showMessage('L\'heure de fin doit être après l\'heure de début.');
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final liveConflicts = _predictSlotConflicts(
      assignmentId: selectedAssignment,
      dayCode: selectedDay,
      start: start,
      end: end,
      room: roomController.text.trim(),
      excludeSlotId: isEdit ? _asInt(slot['slotId'] ?? slot['id']) : null,
    );
    if (liveConflicts.isNotEmpty) {
      _showMessage('Conflits détectés. Ajustez l\'horaire avant validation.');
      startController.dispose();
      endController.dispose();
      roomController.dispose();
      return;
    }

    final payload = {
      'assignment': selectedAssignment,
      'day_of_week': selectedDay,
      'start_time': _toApiTime(start),
      'end_time': _toApiTime(end),
      'room': roomController.text.trim(),
    };

    startController.dispose();
    endController.dispose();
    roomController.dispose();

    setState(() => _saving = true);
    try {
      final dio = ref.read(dioProvider);
      if (isEdit) {
        final slotId = _asInt(slot['slotId'] ?? slot['id']);
        await dio.patch('/teacher-schedule-slots/$slotId/', data: payload);
      } else {
        await dio.post('/teacher-schedule-slots/', data: payload);
      }

      if (!mounted) return;
      _showMessage(
        isEdit ? 'Horaire modifié avec succès.' : 'Horaire ajouté avec succès.',
        isSuccess: true,
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage(
        'Erreur enregistrement horaire: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteSlot(Map<String, dynamic> slot) async {
    if (!_requireScheduleApiSupported('suppression d\'horaire')) {
      return;
    }

    final slotId = _asInt(slot['slotId'] ?? slot['id']);
    if (slotId <= 0) {
      _showMessage('Horaire invalide.');
      return;
    }

    final classId = _asInt(slot['classroom']);
    if (_isClassLockedById(classId)) {
      _showMessage(
        'Emploi du temps verrouillé pour cette classe. Déverrouillez avant suppression.',
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer l\'horaire'),
          content: Text(
            'Supprimer ${slot['subjectCode'] ?? 'cours'} '
            '(${_dayLabel((slot['day_of_week'] ?? '').toString())} ${_slotRange(slot)}) ?',
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

    if (confirm != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete('/teacher-schedule-slots/$slotId/');
      if (!mounted) return;
      _showMessage('Horaire supprimé.', isSuccess: true);
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _markScheduleApiUnsupportedFromError(error);
      _showMessage(
        'Erreur suppression horaire: ${_extractErrorMessage(error)}',
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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

  Future<void> _resetCustomApiUrlAndReload() async {
    await ref.read(tokenStorageProvider).clearApiBaseUrl();
    if (!mounted) return;
    _showMessage('URL API personnalisée supprimée. Rechargement en cours...');
    await _loadData();
  }

  void _markScheduleApiUnsupportedFromError(Object error) {
    if (error is! DioException) {
      return;
    }

    final status = error.response?.statusCode;
    final path = error.requestOptions.path;
    final isSchedulePath =
        path.contains('/teacher-schedule-slots/') ||
        path.contains('/timetable-publications/');

    if (status == 404 && isSchedulePath && _scheduleApiSupported && mounted) {
      setState(() => _scheduleApiSupported = false);
      _showMessage(
        'API planning non disponible sur $_activeApiBaseUrl: $path (404).',
      );
    }
  }

  bool _requireScheduleApiSupported([String action = 'cette action']) {
    if (_scheduleApiSupported) {
      return true;
    }
    _showMessage(
      'Action indisponible: backend planning non compatible pour $action. '
      'API active: $_activeApiBaseUrl',
    );
    return false;
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
        onRefresh: _refreshTimetable,
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

    final assignmentById = _assignmentById();
    final assignmentsByClass = _assignmentsByClass(assignmentById);
    final slotsByClass = _slotsByClass(assignmentById);
    final publicationByClass = _publicationByClassroom();

    final colorScheme = Theme.of(context).colorScheme;
    final classesWithSlots = _classrooms
        .where((row) => (slotsByClass[_asInt(row['id'])] ?? []).isNotEmpty)
        .length;
    final classesPublished = _classrooms
        .where(
          (row) =>
              _asBool(publicationByClass[_asInt(row['id'])]?['is_published']),
        )
        .length;
    final classesLocked = _classrooms
        .where(
          (row) => _asBool(publicationByClass[_asInt(row['id'])]?['is_locked']),
        )
        .length;

    final selectedClassId = _selectedClassroom;
    final selectedClassName = _classNameById(selectedClassId);
    final selectedAssignments = selectedClassId == null
        ? <Map<String, dynamic>>[]
        : (assignmentsByClass[selectedClassId] ?? <Map<String, dynamic>>[]);
    final selectedSlots = selectedClassId == null
        ? <Map<String, dynamic>>[]
        : (slotsByClass[selectedClassId] ?? <Map<String, dynamic>>[]);
    final selectedPublication = selectedClassId == null
        ? null
        : publicationByClass[selectedClassId];
    final selectedIsPublished = _asBool(selectedPublication?['is_published']);
    final selectedIsLocked = _asBool(selectedPublication?['is_locked']);
    final selectedPublicationLabel = _publicationLabel(selectedPublication);
    final isNarrow = MediaQuery.of(context).size.width < 980;

    final teacherWorkloads = buildTeacherWorkloadRows(
      teachers: _teachers,
      assignmentById: assignmentById,
      scheduleSlots: _scheduleSlots,
      classroomFilter: _teacherScope == 'selected' ? selectedClassId : null,
    );

    final controlsPanel = _sectionCard(
      title: 'Filtres et actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_scheduleApiSupported) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                'Backend planning non compatible: les routes horaires ne sont pas disponibles sur\n'
                '$_activeApiBaseUrl\n'
                'Configurez une API mise à jour via Connexion > Configuration API.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retester compatibilité API'),
                ),
                if (_usingCustomApiBaseUrl)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _resetCustomApiUrlAndReload,
                    icon: const Icon(Icons.settings_backup_restore_outlined),
                    label: const Text('Réinitialiser URL API'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: 'classroom',
                label: Text('Par classe'),
                icon: Icon(Icons.grid_view_outlined),
              ),
              ButtonSegment<String>(
                value: 'teacher',
                label: Text('Par enseignant'),
                icon: Icon(Icons.badge_outlined),
              ),
            ],
            selected: {_viewMode},
            onSelectionChanged: (values) {
              final next = values.first;
              setState(() => _viewMode = next);
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _selectedClassroom,
            decoration: const InputDecoration(labelText: 'Classe'),
            items: _classrooms
                .map(
                  (row) => DropdownMenuItem<int>(
                    value: _asInt(row['id']),
                    child: Text('${row['name']}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _selectedClassroom = value);
            },
          ),
          if (selectedClassId != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip('Statut planning', selectedPublicationLabel),
                _metricChip('Horaires', '${selectedSlots.length}'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    (_saving ||
                        !_scheduleApiSupported ||
                        selectedClassId == null ||
                        selectedIsLocked)
                    ? null
                    : () => _openSlotDialog(forceClassroomId: selectedClassId),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Ajouter horaire'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    (_saving ||
                        !_scheduleApiSupported ||
                        selectedClassId == null)
                    ? null
                    : _printSelectedClassPdfFromBackend,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Imprimer tableau PDF'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    (_saving ||
                        !_scheduleApiSupported ||
                        selectedClassId == null)
                    ? null
                    : _exportSelectedClassXlsx,
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Exporter XLSX classe'),
              ),
              FilledButton.tonalIcon(
                onPressed: (_saving || selectedClassId == null)
                    ? null
                    : _exportCurrentClassCsv,
                icon: const Icon(Icons.grid_on_outlined),
                label: const Text('Exporter Excel (CSV)'),
              ),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              ),
              FilledButton.tonalIcon(
                onPressed: (_saving || !_scheduleApiSupported)
                    ? null
                    : _openDuplicateScheduleDialog,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Dupliquer planning'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: (_saving || !_scheduleApiSupported)
                    ? null
                    : _exportGlobalXlsx,
                icon: const Icon(Icons.dataset_outlined),
                label: const Text('Export global XLSX'),
              ),
              OutlinedButton.icon(
                onPressed: (_saving || !_scheduleApiSupported)
                    ? null
                    : _exportGlobalPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export global PDF'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed:
                    (_saving ||
                        !_scheduleApiSupported ||
                        selectedClassId == null ||
                        selectedAssignments.isEmpty)
                    ? null
                    : () => _publishSelectedClass(lockAfterPublish: true),
                icon: const Icon(Icons.publish),
                label: const Text('Publier + verrouiller'),
              ),
              OutlinedButton.icon(
                onPressed:
                    (_saving ||
                        !_scheduleApiSupported ||
                        selectedClassId == null ||
                        selectedAssignments.isEmpty)
                    ? null
                    : () => _publishSelectedClass(lockAfterPublish: false),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Publier sans verrou'),
              ),
              OutlinedButton.icon(
                onPressed:
                    (_saving ||
                        !_scheduleApiSupported ||
                        selectedClassId == null ||
                        !selectedIsPublished)
                    ? null
                    : () => _setSelectedClassLock(lock: !selectedIsLocked),
                icon: Icon(
                  selectedIsLocked
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
                label: Text(selectedIsLocked ? 'Déverrouiller' : 'Verrouiller'),
              ),
              OutlinedButton.icon(
                onPressed:
                    (_saving ||
                        !_scheduleApiSupported ||
                        selectedClassId == null ||
                        !selectedIsPublished)
                    ? null
                    : _unpublishSelectedClass,
                icon: const Icon(Icons.unpublished_outlined),
                label: const Text('Repasser brouillon'),
              ),
            ],
          ),
          if (_viewMode == 'teacher') ...[
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'selected',
                  label: Text('Classe sélectionnée'),
                  icon: Icon(Icons.filter_1_outlined),
                ),
                ButtonSegment<String>(
                  value: 'all',
                  label: Text('Toutes classes'),
                  icon: Icon(Icons.filter_none_outlined),
                ),
              ],
              selected: {_teacherScope},
              onSelectionChanged: (values) {
                setState(() => _teacherScope = values.first);
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Charge calculée sur ${teacherWorkloads.length} enseignant(s).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );

    final selectedClassPanel = _sectionCard(
      title: 'Tableau horaire - $selectedClassName',
      child: selectedClassId == null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Sélectionnez une classe.'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricChip(
                      'Affectations classe',
                      '${selectedAssignments.length}',
                    ),
                    _metricChip('Horaires classe', '${selectedSlots.length}'),
                    _metricChip('Statut', selectedPublicationLabel),
                  ],
                ),
                const SizedBox(height: 10),
                if (selectedIsLocked)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Planning verrouillé: les modifications d\'horaires sont temporairement bloquées.',
                    ),
                  ),
                if (selectedAssignments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Aucune affectation pour cette classe. Créez des affectations puis des horaires.',
                    ),
                  )
                else ...[
                  TextField(
                    controller: _slotsSearchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Filtre rapide (matière, enseignant, salle)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _slotsSearchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _slotsSearchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('Tous jours'),
                        selected: _mobileDayFilter == 'ALL',
                        onSelected: (_) {
                          setState(() => _mobileDayFilter = 'ALL');
                        },
                      ),
                      ..._dayOrder.map(
                        (dayCode) => ChoiceChip(
                          label: Text(_dayLabel(dayCode)),
                          selected: _mobileDayFilter == dayCode,
                          onSelected: (_) {
                            setState(() => _mobileDayFilter = dayCode);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildClassWeeklyGrid(
                    classId: selectedClassId,
                    classSlots: selectedSlots,
                    dayFilter: _mobileDayFilter,
                    searchTerm: _slotsSearchController.text,
                    compact: isNarrow,
                  ),
                ],
              ],
            ),
    );

    final teacherWorkloadPanel = _sectionCard(
      title: _teacherScope == 'selected'
          ? 'Charge horaire - classe sélectionnée'
          : 'Charge horaire - toutes classes',
      child: teacherWorkloads.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucune charge disponible pour le filtre courant.'),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.surfaceContainer,
                ),
                columns: const [
                  DataColumn(label: Text('Enseignant')),
                  DataColumn(label: Text('Horaires')),
                  DataColumn(label: Text('Classes')),
                  DataColumn(label: Text('Lundi')),
                  DataColumn(label: Text('Mardi')),
                  DataColumn(label: Text('Mercredi')),
                  DataColumn(label: Text('Jeudi')),
                  DataColumn(label: Text('Vendredi')),
                  DataColumn(label: Text('Samedi')),
                  DataColumn(label: Text('Total h/sem.')),
                  DataColumn(label: Text('Niveau')),
                ],
                rows: teacherWorkloads.map((row) {
                  final levelColor = row.level == 'Surcharge'
                      ? Colors.red
                      : (row.level == 'A surveiller'
                            ? Colors.orange
                            : Colors.green);
                  final perDay = row.perDayMinutes;

                  String hours(String day) {
                    final minutes = perDay[day] ?? 0;
                    return (minutes / 60).toStringAsFixed(2);
                  }

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          _teacherDisplayLabel(
                            row.teacherName,
                            row.teacherCode,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DataCell(Text('${row.slotCount}')),
                      DataCell(Text('${row.classCount}')),
                      DataCell(Text(hours('MON'))),
                      DataCell(Text(hours('TUE'))),
                      DataCell(Text(hours('WED'))),
                      DataCell(Text(hours('THU'))),
                      DataCell(Text(hours('FRI'))),
                      DataCell(Text(hours('SAT'))),
                      DataCell(Text(row.totalHours.toStringAsFixed(2))),
                      DataCell(
                        Text(
                          row.level,
                          style: TextStyle(
                            color: levelColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );

    final perClassPanel = _sectionCard(
      title: 'Chaque classe a son emploi du temps',
      child: _classrooms.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucune classe disponible.'),
            )
          : Column(
              children: _classrooms.map((classroom) {
                final classId = _asInt(classroom['id']);
                final className = (classroom['name'] ?? 'Classe $classId')
                    .toString();
                final classAssignments =
                    assignmentsByClass[classId] ?? <Map<String, dynamic>>[];
                final classSlots =
                    slotsByClass[classId] ?? <Map<String, dynamic>>[];
                final publication = publicationByClass[classId];
                final classIsLocked = _asBool(publication?['is_locked']);
                final publicationLabel = _publicationLabel(publication);

                return Card(
                  child: ExpansionTile(
                    initiallyExpanded: classId == _selectedClassroom,
                    onExpansionChanged: (expanded) {
                      if (expanded) {
                        setState(() => _selectedClassroom = classId);
                      }
                    },
                    title: Text(className),
                    subtitle: Text(
                      '$publicationLabel • ${classSlots.length} horaire(s) • ${classAssignments.length} affectation(s)',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed:
                              (_saving ||
                                  !_scheduleApiSupported ||
                                  classIsLocked)
                              ? null
                              : () =>
                                    _openSlotDialog(forceClassroomId: classId),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter horaire'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (classAssignments.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Aucune affectation pour cette classe.'),
                        )
                      else
                        _buildClassWeeklyGrid(
                          classId: classId,
                          classSlots: classSlots,
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );

    return RefreshIndicator(
      onRefresh: _refreshTimetable,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emploi du temps',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Vue pedagogique basee sur les affectations enseignants/matieres/classes.',
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
                _metricChip('Enseignants', '${_teachers.length}'),
                _metricChip('Matieres', '${_subjects.length}'),
                _metricChip('Classes', '${_classrooms.length}'),
                _metricChip('Affectations', '${_assignments.length}'),
                _metricChip('Horaires', '${_scheduleSlots.length}'),
                _metricChip('Classes planifiées', '$classesWithSlots'),
                _metricChip('Classes publiées', '$classesPublished'),
                _metricChip('Classes verrouillées', '$classesLocked'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          controlsPanel,
          if (_viewMode == 'classroom') ...[
            const SizedBox(height: 12),
            selectedClassPanel,
            const SizedBox(height: 12),
            perClassPanel,
          ] else ...[
            const SizedBox(height: 12),
            teacherWorkloadPanel,
          ],
        ],
      ),
    );
  }

  Map<int, Map<String, dynamic>> _assignmentById() {
    final teacherById = {for (final t in _teachers) _asInt(t['id']): t};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};
    final classroomById = {for (final c in _classrooms) _asInt(c['id']): c};

    final map = <int, Map<String, dynamic>>{};

    for (final row in _assignments) {
      final assignmentId = _asInt(row['id']);
      if (assignmentId <= 0) continue;

      final classId = _asInt(row['classroom']);
      final teacher = teacherById[_asInt(row['teacher'])];
      final subject = subjectById[_asInt(row['subject'])];
      final classroom = classroomById[classId];

      final teacherCode = (teacher?['employee_code'] ?? 'ENS-${row['teacher']}')
          .toString();
      final teacherName = _teacherNameFromTeacherRow(teacher);
      final classroomName = (classroom?['name'] ?? 'Classe $classId')
          .toString();
      final subjectCode = (subject?['code'] ?? 'MAT').toString();
      final subjectName = (subject?['name'] ?? '').toString();
      final coefficient = (subject?['coefficient'] ?? '').toString();

      map[assignmentId] = {
        ...row,
        'teacherCode': teacherCode,
        'teacherName': teacherName,
        'classroomName': classroomName,
        'subjectCode': subjectCode,
        'subjectName': subjectName,
        'coefficient': coefficient,
      };
    }

    return map;
  }

  Map<int, List<Map<String, dynamic>>> _assignmentsByClass(
    Map<int, Map<String, dynamic>> assignmentById,
  ) {
    final grouped = <int, List<Map<String, dynamic>>>{};

    for (final assignment in assignmentById.values) {
      final classId = _asInt(assignment['classroom']);
      grouped.putIfAbsent(classId, () => []).add(assignment);
    }

    for (final rows in grouped.values) {
      rows.sort((a, b) {
        final byCode = (a['subjectCode'] ?? '').toString().compareTo(
          (b['subjectCode'] ?? '').toString(),
        );
        if (byCode != 0) return byCode;
        return _asInt(a['id']).compareTo(_asInt(b['id']));
      });
    }

    return grouped;
  }

  Map<int, List<Map<String, dynamic>>> _slotsByClass(
    Map<int, Map<String, dynamic>> assignmentById,
  ) {
    final grouped = <int, List<Map<String, dynamic>>>{};

    for (final slot in _scheduleSlots) {
      final assignmentId = _asInt(slot['assignment']);
      final assignment = assignmentById[assignmentId];
      if (assignment == null) continue;

      final classId = _asInt(assignment['classroom']);
      final enriched = {
        ...slot,
        'slotId': _asInt(slot['id']),
        'classroom': classId,
        'classroomName': assignment['classroomName'],
        'subjectCode': assignment['subjectCode'],
        'subjectName': assignment['subjectName'],
        'teacherCode': assignment['teacherCode'],
        'teacherName': assignment['teacherName'],
        'coefficient': assignment['coefficient'],
      };

      grouped.putIfAbsent(classId, () => []).add(enriched);
    }

    for (final rows in grouped.values) {
      rows.sort((a, b) {
        final byDay = _dayIndex(
          (a['day_of_week'] ?? '').toString(),
        ).compareTo(_dayIndex((b['day_of_week'] ?? '').toString()));
        if (byDay != 0) return byDay;

        final byStart = _timeToMinutes(
          a['start_time'],
        ).compareTo(_timeToMinutes(b['start_time']));
        if (byStart != 0) return byStart;

        final byEnd = _timeToMinutes(
          a['end_time'],
        ).compareTo(_timeToMinutes(b['end_time']));
        if (byEnd != 0) return byEnd;

        return _asInt(a['slotId']).compareTo(_asInt(b['slotId']));
      });
    }

    return grouped;
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _classMatrix(
    List<Map<String, dynamic>> classSlots,
  ) {
    final matrix = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final slot in classSlots) {
      final dayCode = (slot['day_of_week'] ?? '').toString();
      if (!_dayOrder.contains(dayCode)) continue;

      final range = _slotRange(slot);
      final dayMap = matrix.putIfAbsent(
        range,
        () => {for (final day in _dayOrder) day: <Map<String, dynamic>>[]},
      );
      dayMap[dayCode]!.add(slot);
    }

    for (final dayMap in matrix.values) {
      for (final slots in dayMap.values) {
        slots.sort((a, b) {
          final byCode = (a['subjectCode'] ?? '').toString().compareTo(
            (b['subjectCode'] ?? '').toString(),
          );
          if (byCode != 0) return byCode;
          return _teacherDisplayLabel(
            a['teacherName'],
            a['teacherCode'],
          ).compareTo(_teacherDisplayLabel(b['teacherName'], b['teacherCode']));
        });
      }
    }

    return matrix;
  }

  Widget _buildClassWeeklyGrid({
    required int classId,
    required List<Map<String, dynamic>> classSlots,
    String dayFilter = 'ALL',
    String searchTerm = '',
    bool compact = false,
  }) {
    final normalizedSearch = searchTerm.trim().toLowerCase();

    final filteredSlots = classSlots.where((slot) {
      final dayCode = (slot['day_of_week'] ?? '').toString();
      if (dayFilter != 'ALL' && dayCode != dayFilter) {
        return false;
      }
      if (normalizedSearch.isEmpty) {
        return true;
      }

      final haystack = [
        (slot['subjectCode'] ?? '').toString(),
        (slot['subjectName'] ?? '').toString(),
        (slot['teacherName'] ?? '').toString(),
        (slot['teacherCode'] ?? '').toString(),
        (slot['room'] ?? '').toString(),
        _slotRange(slot),
      ].join(' ').toLowerCase();
      return haystack.contains(normalizedSearch);
    }).toList();

    if (filteredSlots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('Aucun horaire ne correspond au filtre sélectionné.'),
      );
    }

    if (compact) {
      return _buildCompactDayCards(
        classId: classId,
        classSlots: filteredSlots,
        dayFilter: dayFilter,
      );
    }

    final matrix = _classMatrix(filteredSlots);
    final ranges = matrix.keys.toList()
      ..sort((a, b) => _rangeStartMinutes(a).compareTo(_rangeStartMinutes(b)));
    final visibleDays = dayFilter == 'ALL'
        ? _dayOrder
        : _dayOrder.where((day) => day == dayFilter).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        dataRowMinHeight: 72,
        dataRowMaxHeight: 220,
        headingRowColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surfaceContainer,
        ),
        columns: [
          const DataColumn(label: Text('Horaire')),
          ...visibleDays.map(
            (dayCode) => DataColumn(label: Text(_dayLabel(dayCode))),
          ),
        ],
        rows: ranges.map((range) {
          final dayMap =
              matrix[range] ?? const <String, List<Map<String, dynamic>>>{};
          return DataRow(
            cells: [
              DataCell(Text(range)),
              ...visibleDays.map((dayCode) {
                final slots = dayMap[dayCode] ?? const <Map<String, dynamic>>[];
                return DataCell(
                  _buildMatrixCell(classId: classId, slots: slots),
                );
              }),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCompactDayCards({
    required int classId,
    required List<Map<String, dynamic>> classSlots,
    required String dayFilter,
  }) {
    final visibleDays = dayFilter == 'ALL'
        ? _dayOrder
        : _dayOrder.where((day) => day == dayFilter).toList();
    final grouped = {
      for (final day in visibleDays) day: <Map<String, dynamic>>[],
    };

    for (final slot in classSlots) {
      final dayCode = (slot['day_of_week'] ?? '').toString();
      if (!grouped.containsKey(dayCode)) {
        continue;
      }
      grouped[dayCode]!.add(slot);
    }

    for (final slots in grouped.values) {
      slots.sort((a, b) {
        final byStart = _timeToMinutes(
          a['start_time'],
        ).compareTo(_timeToMinutes(b['start_time']));
        if (byStart != 0) return byStart;
        return _asInt(a['slotId']).compareTo(_asInt(b['slotId']));
      });
    }

    final daysWithContent = visibleDays
        .where((day) => (grouped[day] ?? []).isNotEmpty)
        .toList();
    if (daysWithContent.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('Aucun horaire planifié.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final dayCode in daysWithContent) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: _dayAccent(dayCode).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _dayAccent(dayCode).withValues(alpha: 0.30),
              ),
            ),
            child: Text(
              _dayLabel(dayCode),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _dayAccent(dayCode),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...grouped[dayCode]!.map(
            (slot) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildCompactSlotCard(classId: classId, slot: slot),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildCompactSlotCard({
    required int classId,
    required Map<String, dynamic> slot,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final classLocked = _isClassLockedById(classId);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${slot['subjectCode']} - ${slot['subjectName']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _slotRange(slot),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Ens: ${_teacherDisplayLabel(slot['teacherName'], slot['teacherCode'])}',
          ),
          if ((slot['room'] ?? '').toString().trim().isNotEmpty)
            Text('Salle: ${slot['room']}'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: (_saving || !_scheduleApiSupported || classLocked)
                    ? null
                    : () => _openSlotDialog(
                        slot: slot,
                        forceClassroomId: classId,
                      ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Modifier'),
              ),
              OutlinedButton.icon(
                onPressed: (_saving || !_scheduleApiSupported || classLocked)
                    ? null
                    : () => _deleteSlot(slot),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Supprimer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _dayAccent(String dayCode) {
    switch (dayCode) {
      case 'MON':
        return Colors.blue;
      case 'TUE':
        return Colors.teal;
      case 'WED':
        return Colors.indigo;
      case 'THU':
        return Colors.orange;
      case 'FRI':
        return Colors.green;
      case 'SAT':
        return Colors.brown;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _buildMatrixCell({
    required int classId,
    required List<Map<String, dynamic>> slots,
  }) {
    if (slots.isEmpty) {
      return const SizedBox(
        width: 180,
        child: Text('-', textAlign: TextAlign.center),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final classLocked = _isClassLockedById(classId);
    return SizedBox(
      width: 180,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < slots.length; i++) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${slots[i]['subjectCode']} - ${slots[i]['subjectName']}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ens: ${_teacherDisplayLabel(slots[i]['teacherName'], slots[i]['teacherCode'])}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if ((slots[i]['room'] ?? '').toString().trim().isNotEmpty)
                    Text(
                      'Salle: ${slots[i]['room']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Modifier horaire',
                        onPressed:
                            (_saving || !_scheduleApiSupported || classLocked)
                            ? null
                            : () => _openSlotDialog(
                                slot: slots[i],
                                forceClassroomId: classId,
                              ),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        tooltip: 'Supprimer horaire',
                        onPressed:
                            (_saving || !_scheduleApiSupported || classLocked)
                            ? null
                            : () => _deleteSlot(slots[i]),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (i < slots.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  int _rangeStartMinutes(String range) {
    final start = range.split('-').first.trim();
    return _timeToMinutes(start);
  }

  String _slotsExportCell(List<Map<String, dynamic>> slots) {
    if (slots.isEmpty) return '';
    return slots.map(_slotShortLabel).join(' | ');
  }

  String _slotShortLabel(Map<String, dynamic> slot) {
    final room = (slot['room'] ?? '').toString().trim();
    final teacherLabel = _teacherDisplayLabel(
      slot['teacherName'],
      slot['teacherCode'],
    );
    final base = '${slot['subjectCode'] ?? 'MAT'} ($teacherLabel)';
    if (room.isEmpty) return base;
    return '$base [$room]';
  }

  String _slotRange(Map<String, dynamic> slot) {
    return '${_hhmm(slot['start_time'])}-${_hhmm(slot['end_time'])}';
  }

  String _dayLabel(String dayCode) {
    return _dayLabels[dayCode] ?? dayCode;
  }

  int _dayIndex(String dayCode) {
    return _dayOrder.indexOf(dayCode);
  }

  String _hhmm(dynamic value) {
    final raw = (value ?? '').toString().trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw);
    if (match == null) {
      return raw;
    }
    final h = int.tryParse(match.group(1) ?? '') ?? 0;
    final m = int.tryParse(match.group(2) ?? '') ?? 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int _timeToMinutes(dynamic value) {
    final parsed = _parseTimeOfDay(_hhmm(value));
    if (parsed == null) return 0;
    return parsed.hour * 60 + parsed.minute;
  }

  TimeOfDay? _parseTimeOfDay(String raw) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})(?::\d{2})?$',
    ).firstMatch(raw.trim());
    if (match == null) return null;

    final hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTimeOfDay(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  String _toApiTime(TimeOfDay value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:00';
  }

  String _classNameById(int? classId) {
    if (classId == null || classId <= 0) return 'Classe';
    for (final row in _classrooms) {
      if (_asInt(row['id']) == classId) {
        return (row['name'] ?? 'Classe $classId').toString();
      }
    }
    return 'Classe $classId';
  }

  String _teacherNameFromTeacherRow(Map<String, dynamic>? teacher) {
    if (teacher == null) {
      return '';
    }

    final explicitFullName = (teacher['user_full_name'] ?? '')
        .toString()
        .trim();
    if (explicitFullName.isNotEmpty) {
      return explicitFullName;
    }

    final firstName = (teacher['user_first_name'] ?? '').toString().trim();
    final lastName = (teacher['user_last_name'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }

    final username = (teacher['user_username'] ?? '').toString().trim();
    if (username.isNotEmpty) {
      return username;
    }

    return '';
  }

  String _teacherDisplayLabel(dynamic teacherName, dynamic teacherCode) {
    final name = (teacherName ?? '').toString().trim();
    if (name.isNotEmpty) {
      return name;
    }

    final code = (teacherCode ?? '').toString().trim();
    if (code.isNotEmpty) {
      return code;
    }

    return 'Enseignant';
  }

  String _csvCell(dynamic value) {
    final raw = (value ?? '').toString().replaceAll('"', '""');
    final flattened = raw.replaceAll('\n', ' ').replaceAll('\r', ' ');
    final safe = RegExp(r'^[=+\-@]').hasMatch(flattened)
        ? "'$flattened"
        : flattened;
    return '"$safe"';
  }

  String _slugify(String value) {
    final cleaned = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'classe' : cleaned;
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

  String _dateTimeLabel(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm';
  }
}
