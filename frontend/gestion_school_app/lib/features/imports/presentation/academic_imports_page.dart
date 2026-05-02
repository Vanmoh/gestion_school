import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/academic_imports_ui_reference.dart';
import '../../../core/widgets/foreground_notice.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../students/presentation/students_controller.dart';
import '../../exams/presentation/exams_controller.dart';
import 'academic_imports_controller.dart';

enum _AcademicImportType { students, controls, exams, timetable }

class AcademicImportsPage extends ConsumerStatefulWidget {
  const AcademicImportsPage({super.key});

  @override
  ConsumerState<AcademicImportsPage> createState() =>
      _AcademicImportsPageState();
}

class _AcademicImportsPageState extends ConsumerState<AcademicImportsPage> {
  static const List<String> _terms = <String>['T1', 'T2', 'T3'];

  bool _loading = true;
  bool _previewLoading = false;
  bool _confirmLoading = false;
  bool _templateLoading = false;

  _AcademicImportType _selectedType = _AcademicImportType.students;
  PlatformFile? _selectedFile;

  int? _selectedClassroomId;
  int? _selectedAcademicYearId;
  int? _selectedSessionId;
  String _selectedTerm = 'T1';
  bool _confirmTimetableConflicts = false;

  List<Map<String, dynamic>> _classrooms = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _academicYears = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _examSessions = <Map<String, dynamic>>[];
  Map<String, dynamic>? _lastPreview;

  bool get _isReadOnly {
    final role = ref.read(authControllerProvider).value?.role;
    return role == 'teacher' ||
        role == 'supervisor' ||
        role == 'accountant' ||
        role == 'parent' ||
        role == 'student';
  }

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
  }

  Future<void> _loadReferenceData() async {
    setState(() => _loading = true);
    try {
      final repository = ref.read(academicImportsRepositoryProvider);
      final results = await Future.wait(<Future<List<Map<String, dynamic>>>>[
        repository.fetchClassrooms(),
        repository.fetchAcademicYears(),
        repository.fetchExamSessions(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _classrooms = results[0];
        _academicYears = results[1];
        _examSessions = results[2];
        final classroomIds = _classrooms.map((row) => _asInt(row['id'])).toSet();
        final yearIds = _academicYears.map((row) => _asInt(row['id'])).toSet();
        final sessionIds = _examSessions.map((row) => _asInt(row['id'])).toSet();
        if (_selectedClassroomId == null || !classroomIds.contains(_selectedClassroomId)) {
          _selectedClassroomId = _firstPositiveId(_classrooms);
        }
        if (_selectedAcademicYearId == null || !yearIds.contains(_selectedAcademicYearId)) {
          _selectedAcademicYearId = _preferredAcademicYearId(_academicYears);
        }
        if (_selectedSessionId == null || !sessionIds.contains(_selectedSessionId)) {
          _selectedSessionId = _firstPositiveId(_examSessions);
        }
      });
    } catch (error) {
      _showMessage('Chargement impossible: ${_extractApiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int? _firstPositiveId(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final id = _asInt(row['id']);
      if (id > 0) {
        return id;
      }
    }
    return null;
  }

  int? _preferredAcademicYearId(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      if (row['is_active'] == true) {
        final id = _asInt(row['id']);
        if (id > 0) {
          return id;
        }
      }
    }
    return _firstPositiveId(rows);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      withData: true,
      allowedExtensions: const <String>['csv', 'xlsx', 'xls'],
    );
    final file = result?.files.firstOrNull;
    if (file == null) {
      return;
    }
    setState(() {
      _selectedFile = file;
      _lastPreview = null;
      _confirmTimetableConflicts = false;
    });
  }

  Future<void> _previewImport() async {
    final validationMessage = _validateSelections();
    if (validationMessage != null) {
      _showMessage(validationMessage);
      return;
    }

    setState(() {
      _previewLoading = true;
      _lastPreview = null;
      _confirmTimetableConflicts = false;
    });

    try {
      final repository = ref.read(academicImportsRepositoryProvider);
      final file = _selectedFile!;
      late final Map<String, dynamic> preview;
      switch (_selectedType) {
        case _AcademicImportType.students:
          preview = await repository.previewStudentsImport(
            classroomId: _selectedClassroomId!,
            file: file,
          );
          break;
        case _AcademicImportType.controls:
          preview = await repository.previewControlsImport(
            classroomId: _selectedClassroomId!,
            academicYearId: _selectedAcademicYearId!,
            term: _selectedTerm,
            file: file,
          );
          break;
        case _AcademicImportType.exams:
          preview = await repository.previewExamsImport(
            classroomId: _selectedClassroomId!,
            sessionId: _selectedSessionId!,
            file: file,
          );
          break;
        case _AcademicImportType.timetable:
          preview = await repository.previewTimetableImport(
            classroomId: _selectedClassroomId!,
            file: file,
          );
          break;
      }
      if (!mounted) {
        return;
      }
      setState(() => _lastPreview = preview);
      final detail = _asText(preview['detail']);
      if (detail.isNotEmpty) {
        _showMessage(detail, isSuccess: true);
      }
    } catch (error) {
      _showMessage('Prévisualisation impossible: ${_extractApiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _previewLoading = false);
      }
    }
  }

  Future<void> _confirmImport() async {
    final preview = _lastPreview;
    if (preview == null) {
      _showMessage('Lancez d\'abord une prévisualisation.');
      return;
    }
    if (!_canConfirm(preview)) {
      _showMessage('Corrigez les erreurs ou les conflits bloquants avant confirmation.');
      return;
    }

    setState(() => _confirmLoading = true);
    try {
      final repository = ref.read(academicImportsRepositoryProvider);
      final file = _selectedFile!;
      late final Map<String, dynamic> result;
      switch (_selectedType) {
        case _AcademicImportType.students:
          result = await repository.confirmStudentsImport(
            classroomId: _selectedClassroomId!,
            file: file,
          );
          ref.invalidate(studentsProvider);
          break;
        case _AcademicImportType.controls:
          result = await repository.confirmControlsImport(
            classroomId: _selectedClassroomId!,
            academicYearId: _selectedAcademicYearId!,
            term: _selectedTerm,
            file: file,
          );
          break;
        case _AcademicImportType.exams:
          result = await repository.confirmExamsImport(
            classroomId: _selectedClassroomId!,
            sessionId: _selectedSessionId!,
            file: file,
          );
          ref.invalidate(examResultsProvider);
          break;
        case _AcademicImportType.timetable:
          result = await repository.confirmTimetableImport(
            classroomId: _selectedClassroomId!,
            file: file,
            confirmConflicts: _confirmTimetableConflicts,
          );
          break;
      }
      if (!mounted) {
        return;
      }
      setState(() => _lastPreview = result);
      _showMessage(
        _asText(result['detail']).isEmpty
            ? 'Import terminé.'
            : _asText(result['detail']),
        isSuccess: true,
      );
    } catch (error) {
      _showMessage('Confirmation impossible: ${_extractApiError(error)}');
    } finally {
      if (mounted) {
        setState(() => _confirmLoading = false);
      }
    }
  }

  Map<String, dynamic> _templateSpec(_AcademicImportType type) {
    switch (type) {
      case _AcademicImportType.students:
        return <String, dynamic>{
          'filename': 'import_students',
          'headers': <String>[
            'matricule',
            'first_name',
            'last_name',
            'username',
            'email',
            'phone',
            'birth_date',
          ],
          'rows': <List<String>>[
            <String>['MAT001', 'Aminata', 'Diallo', 'mat001', 'aminata@example.com', '770000001', '2012-05-11'],
            <String>['MAT002', 'Ibrahima', 'Sow', 'mat002', 'ibrahima@example.com', '770000002', '2011-10-03'],
          ],
        };
      case _AcademicImportType.controls:
        return <String, dynamic>{
          'filename': 'import_controls',
          'headers': <String>[
            'student_matricule',
            'subject_code',
            'subject_name',
            'value',
          ],
          'rows': <List<String>>[
            <String>['MAT001', 'MAT', 'Mathematiques', '14.5'],
            <String>['MAT002', 'PHY', 'Physique', '12'],
          ],
        };
      case _AcademicImportType.exams:
        return <String, dynamic>{
          'filename': 'import_exams',
          'headers': <String>[
            'student_matricule',
            'subject_code',
            'subject_name',
            'score',
          ],
          'rows': <List<String>>[
            <String>['MAT001', 'MAT', 'Mathematiques', '13'],
            <String>['MAT002', 'PHY', 'Physique', '11.75'],
          ],
        };
      case _AcademicImportType.timetable:
        return <String, dynamic>{
          'filename': 'import_timetable',
          'headers': <String>[
            'day_of_week',
            'start_time',
            'end_time',
            'subject_code',
            'subject_name',
            'room',
          ],
          'rows': <List<String>>[
            <String>['MON', '08:00', '09:00', 'MAT', 'Mathematiques', 'Salle A'],
            <String>['TUE', '10:00', '11:00', 'PHY', 'Physique', 'Salle B'],
          ],
        };
    }
  }

  Uint8List _buildTemplateCsvBytes(Map<String, dynamic> spec) {
    final headers = (spec['headers'] as List<dynamic>)
        .map((value) => value.toString())
        .toList();
    final rows = (spec['rows'] as List<dynamic>)
        .map(
          (row) => (row as List<dynamic>)
              .map((value) => value.toString())
              .toList(),
        )
        .toList();

    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));
    for (final row in rows) {
      buffer.writeln(row.map(_csvEscape).join(','));
    }

    return Uint8List.fromList(utf8.encode('\uFEFF${buffer.toString()}'));
  }

  Uint8List _buildTemplateXlsxBytes(Map<String, dynamic> spec) {
    final headers = (spec['headers'] as List<dynamic>)
        .map((value) => value.toString())
        .toList();
    final rows = (spec['rows'] as List<dynamic>)
        .map(
          (row) => (row as List<dynamic>)
              .map((value) => value.toString())
              .toList(),
        )
        .toList();

    final workbook = xl.Excel.createExcel();
    const sheetName = 'template';
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      workbook.rename(defaultSheet, sheetName);
    }
    final sheet = workbook[sheetName];
    sheet.appendRow(headers.map((value) => xl.TextCellValue(value)).toList());
    for (final row in rows) {
      sheet.appendRow(row.map((value) => xl.TextCellValue(value)).toList());
    }

    final bytes = workbook.save();
    if (bytes == null || bytes.isEmpty) {
      return Uint8List(0);
    }
    return Uint8List.fromList(bytes);
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    final needsQuotes =
        escaped.contains(',') || escaped.contains('"') || escaped.contains('\n');
    return needsQuotes ? '"$escaped"' : escaped;
  }

  Future<void> _downloadTemplate(String format) async {
    if (_templateLoading) {
      return;
    }

    setState(() => _templateLoading = true);
    try {
      await _downloadTemplateFormat(format, showSuccessMessage: true);
    } finally {
      if (mounted) {
        setState(() => _templateLoading = false);
      }
    }
  }

  Future<bool> _downloadTemplateFormat(
    String format, {
    required bool showSuccessMessage,
  }) async {
    try {
      final spec = _templateSpec(_selectedType);
      final normalizedFormat = format.toLowerCase();
      final bytes = normalizedFormat == 'xlsx'
          ? _buildTemplateXlsxBytes(spec)
          : _buildTemplateCsvBytes(spec);
      if (bytes.isEmpty) {
        _showMessage('Impossible de générer le modèle ${format.toUpperCase()}.');
        return false;
      }
      final fileName = '${spec['filename']}_template.$normalizedFormat';

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Télécharger le modèle ${format.toUpperCase()}',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: <String>[format],
        bytes: bytes,
      );

      if (savedPath == null && !kIsWeb) {
        if (showSuccessMessage) {
          _showMessage('Téléchargement annulé.');
        }
        return false;
      }

      if (showSuccessMessage) {
        _showMessage('Modèle téléchargé: $fileName', isSuccess: true);
      }
      return true;
    } catch (error) {
      _showMessage('Téléchargement impossible: ${_extractApiError(error)}');
      return false;
    }
  }

  String? _validateSelections() {
    if (_isReadOnly) {
      return 'Votre profil ne peut pas lancer d\'import.';
    }
    if (_selectedFile == null) {
      return 'Sélectionnez un fichier CSV ou Excel.';
    }
    if (_selectedClassroomId == null || _selectedClassroomId! <= 0) {
      return 'Sélectionnez une classe.';
    }
    if (_selectedType == _AcademicImportType.controls &&
        (_selectedAcademicYearId == null || _selectedAcademicYearId! <= 0)) {
      return 'Sélectionnez une année scolaire.';
    }
    if (_selectedType == _AcademicImportType.exams &&
        (_selectedSessionId == null || _selectedSessionId! <= 0)) {
      return 'Sélectionnez une session d\'examen.';
    }
    return null;
  }

  bool _canConfirm(Map<String, dynamic> preview) {
    final summary = _summary(preview);
    final hasRows = _asInt(summary['valid_rows']) > 0;
    final hasErrors = _asInt(summary['errors']) > 0;
    final hasBlockingConflicts = _asInt(summary['blocking_conflicts']) > 0;
    final requiresConflictConfirmation = preview['confirm_conflicts_required'] == true;

    if (!hasRows || hasErrors || hasBlockingConflicts) {
      return false;
    }
    if (_selectedType == _AcademicImportType.timetable &&
        requiresConflictConfirmation &&
        !_confirmTimetableConflicts) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> _summary(Map<String, dynamic> payload) {
    final summary = payload['summary'];
    if (summary is Map<String, dynamic>) {
      return summary;
    }
    if (summary is Map) {
      return Map<String, dynamic>.from(summary);
    }
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) {
      return;
    }
    ForegroundNotice.show(
      context,
      message,
      isSuccess: isSuccess,
      isError: !isSuccess,
    );
  }

  String _extractApiError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        for (final key in const <String>['detail', 'message', 'error']) {
          final value = data[key];
          if (value != null && value.toString().trim().isNotEmpty) {
            return value.toString();
          }
        }
        for (final entry in data.entries) {
          final value = entry.value;
          if (value is List && value.isNotEmpty) {
            return '${entry.key}: ${value.first}';
          }
          if (value != null && value.toString().trim().isNotEmpty) {
            return '${entry.key}: $value';
          }
        }
      }
      final status = error.response?.statusCode;
      if (status != null) {
        return 'HTTP $status';
      }
    }
    return error.toString();
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _asText(dynamic value) => value?.toString().trim() ?? '';

  int _listCount(dynamic value) {
    if (value is List) {
      return value.length;
    }
    return 0;
  }

  String _classroomLabel(int? classroomId) {
    final row = _classrooms.where((item) => _asInt(item['id']) == classroomId).firstOrNull;
    if (row == null) {
      return 'Classe';
    }
    return _asText(row['name']).isEmpty ? 'Classe ${row['id']}' : _asText(row['name']);
  }

  String _yearLabel(int? yearId) {
    final row = _academicYears.where((item) => _asInt(item['id']) == yearId).firstOrNull;
    if (row == null) {
      return 'Année';
    }
    final label = _asText(row['label']);
    return label.isEmpty ? _asText(row['name']) : label;
  }

  String _sessionLabel(int? sessionId) {
    final row = _examSessions.where((item) => _asInt(item['id']) == sessionId).firstOrNull;
    if (row == null) {
      return 'Session';
    }
    final title = _asText(row['title']);
    final name = _asText(row['name']);
    final term = _asText(row['term']);
    final base = title.isNotEmpty ? title : name;
    return term.isEmpty ? base : '[$term] $base';
  }

  List<String> _expectedColumns() {
    switch (_selectedType) {
      case _AcademicImportType.students:
        return const <String>[
          'matricule',
          'first_name ou prenom',
          'last_name ou nom',
          'username optionnel',
          'email optionnel',
          'phone ou telephone optionnel',
          'birth_date ou date_naissance optionnel',
        ];
      case _AcademicImportType.controls:
        return const <String>[
          'student_matricule ou matricule',
          'subject_code ou matiere_code',
          'subject_name ou matiere',
          'value ou note ou score',
        ];
      case _AcademicImportType.exams:
        return const <String>[
          'student_matricule ou matricule',
          'subject_code ou matiere_code',
          'subject_name ou matiere',
          'score ou note',
        ];
      case _AcademicImportType.timetable:
        return const <String>[
          'day_of_week ou jour',
          'start_time ou debut',
          'end_time ou fin',
          'subject_code ou matiere_code',
          'subject_name ou matiere',
          'room ou salle optionnel',
        ];
    }
  }

  String _typeTitle(_AcademicImportType type) {
    switch (type) {
      case _AcademicImportType.students:
        return 'Élèves par classe';
      case _AcademicImportType.controls:
        return 'Notes de contrôles';
      case _AcademicImportType.exams:
        return 'Notes d\'examens';
      case _AcademicImportType.timetable:
        return 'Emploi du temps';
    }
  }

  String _typeDescription(_AcademicImportType type) {
    switch (type) {
      case _AcademicImportType.students:
        return 'Création et mise à jour d\'élèves à partir du matricule.';
      case _AcademicImportType.controls:
        return 'Upsert des notes sur la période choisie, avec blocage si période validée.';
      case _AcademicImportType.exams:
        return 'Import des résultats d\'examen sur une session existante.';
      case _AcademicImportType.timetable:
        return 'Prévisualise les conflits avant remplacement des créneaux de classe.';
    }
  }

  Future<void> _closePage() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final didPop = await navigator.maybePop();
    if (!didPop && mounted) {
      _showMessage('Aucune page précédente à fermer.');
    }
  }

  Widget _panelCard({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: AcademicImportsUiReference.panelBackground(scheme),
      shape: AcademicImportsUiReference.panelShape(scheme),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _lastPreview;
    final summary = preview == null ? const <String, dynamic>{} : _summary(preview);
    final hasPreview = preview != null;
    final isBusy = _loading || _previewLoading || _confirmLoading || _templateLoading;
    final previewRows = preview == null ? const <Map<String, dynamic>>[] : _mapList(preview['preview']);
    final errors = preview == null ? const <Map<String, dynamic>>[] : _mapList(preview['errors']);
    final conflicts = preview == null ? const <Map<String, dynamic>>[] : _mapList(preview['conflicts']);
    final result = preview == null ? const <String, dynamic>{} : (preview['result'] is Map ? Map<String, dynamic>.from(preview['result'] as Map) : const <String, dynamic>{});
    final compact = MediaQuery.of(context).size.width < 900;

    return RefreshIndicator(
      onRefresh: _loadReferenceData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AcademicImportsUiReference.pagePadding,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Imports académiques',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Charge un fichier CSV ou Excel, contrôle les effets puis confirme l\'import seulement après prévisualisation.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AcademicImportsUiReference.subtleText(scheme),
                      ),
                    ),
                    if (_isReadOnly) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Mode lecture seule: ce profil peut consulter la mécanique d\'import mais ne peut pas exécuter d\'écriture.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _loadReferenceData,
                    icon: const Icon(Icons.sync),
                    label: const Text('Actualiser'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : _closePage,
                    icon: const Icon(Icons.close),
                    label: const Text('Fermer'),
                  ),
                ],
              ),
            ],
          ),
          if (isBusy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          _panelCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type d\'import',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_AcademicImportType>(
                    segments: _AcademicImportType.values
                        .map(
                          (type) => ButtonSegment<_AcademicImportType>(
                            value: type,
                            label: Text(_typeTitle(type)),
                            icon: Icon(
                              switch (type) {
                                _AcademicImportType.students => Icons.school_outlined,
                                _AcademicImportType.controls => Icons.fact_check_outlined,
                                _AcademicImportType.exams => Icons.quiz_outlined,
                                _AcademicImportType.timetable => Icons.calendar_month_outlined,
                              },
                            ),
                          ),
                        )
                        .toList(),
                    selected: <_AcademicImportType>{_selectedType},
                    onSelectionChanged: isBusy
                        ? null
                        : (selection) {
                            final next = selection.firstOrNull;
                            if (next == null || next == _selectedType) {
                              return;
                            }
                            setState(() {
                              _selectedType = next;
                              _lastPreview = null;
                              _confirmTimetableConflicts = false;
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _typeDescription(_selectedType),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: _panelCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paramètres',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: _selectedClassroomId,
                          items: _classrooms
                              .map(
                                (row) => DropdownMenuItem<int>(
                                  value: _asInt(row['id']),
                                  child: Text(_classroomLabel(_asInt(row['id']))),
                                ),
                              )
                              .toList(),
                          onChanged: isBusy
                              ? null
                              : (value) {
                                  setState(() {
                                    _selectedClassroomId = value;
                                    _lastPreview = null;
                                  });
                                },
                          decoration: const InputDecoration(
                            labelText: 'Classe cible',
                          ),
                        ),
                        if (_selectedType == _AcademicImportType.controls) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: _selectedAcademicYearId,
                            items: _academicYears
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text(_yearLabel(_asInt(row['id']))),
                                  ),
                                )
                                .toList(),
                            onChanged: isBusy
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedAcademicYearId = value;
                                      _lastPreview = null;
                                    });
                                  },
                            decoration: const InputDecoration(
                              labelText: 'Année scolaire',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedTerm,
                            items: _terms
                                .map(
                                  (term) => DropdownMenuItem<String>(
                                    value: term,
                                    child: Text(term),
                                  ),
                                )
                                .toList(),
                            onChanged: isBusy
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedTerm = value ?? 'T1';
                                      _lastPreview = null;
                                    });
                                  },
                            decoration: const InputDecoration(
                              labelText: 'Période',
                            ),
                          ),
                        ],
                        if (_selectedType == _AcademicImportType.exams) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            initialValue: _selectedSessionId,
                            items: _examSessions
                                .map(
                                  (row) => DropdownMenuItem<int>(
                                    value: _asInt(row['id']),
                                    child: Text(_sessionLabel(_asInt(row['id']))),
                                  ),
                                )
                                .toList(),
                            onChanged: isBusy
                                ? null
                                : (value) {
                                    setState(() {
                                      _selectedSessionId = value;
                                      _lastPreview = null;
                                    });
                                  },
                            decoration: const InputDecoration(
                              labelText: 'Session d\'examen',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: compact ? 0 : 12, height: compact ? 12 : 0),
              Expanded(
                flex: 4,
                child: _panelCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fichier source',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedFile == null
                              ? 'Aucun fichier sélectionné'
                              : '${_selectedFile!.name} (${(_selectedFile!.size / 1024).toStringAsFixed(1)} Ko)',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: isBusy || _isReadOnly ? null : _pickFile,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('Choisir un fichier'),
                            ),
                            OutlinedButton.icon(
                              onPressed: isBusy || _isReadOnly ? null : _previewImport,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Prévisualiser'),
                            ),
                            OutlinedButton.icon(
                              onPressed: isBusy || _isReadOnly || !hasPreview || !_canConfirm(preview)
                                  ? null
                                  : _confirmImport,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Confirmer'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: isBusy ? null : () => _downloadTemplate('xlsx'),
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Modèle Excel'),
                            ),
                            OutlinedButton.icon(
                              onPressed: isBusy ? null : () => _downloadTemplate('csv'),
                              icon: const Icon(Icons.download_for_offline_outlined),
                              label: const Text('Modèle CSV'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Colonnes attendues'),
                          children: _expectedColumns()
                              .map(
                                (column) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.label_outline, size: 18),
                                  title: Text(column),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (hasPreview) ...[
            const SizedBox(height: 12),
            _panelCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Synthèse de prévisualisation',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: summary.entries
                          .map(
                            (entry) => Container(
                              width: compact ? double.infinity : 150,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: AcademicImportsUiReference.metricBackground(scheme, entry.key),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AcademicImportsUiReference.panelBorder(scheme)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.key.replaceAll('_', ' '),
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${entry.value}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Contexte: ${_classroomLabel(_selectedClassroomId)}'
                      '${_selectedType == _AcademicImportType.controls ? ' • ${_yearLabel(_selectedAcademicYearId)} • $_selectedTerm' : ''}'
                      '${_selectedType == _AcademicImportType.exams ? ' • ${_sessionLabel(_selectedSessionId)}' : ''}',
                    ),
                    if (result.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Résultat: créé ${_asInt(result['created'])}, mis à jour ${_asInt(result['updated'])}'
                        '${result.containsKey('deleted_conflicts') ? ', conflits supprimés ${_asInt(result['deleted_conflicts'])}' : ''}',
                      ),
                    ],
                    if (_selectedType == _AcademicImportType.timetable &&
                        preview['confirm_conflicts_required'] == true) ...[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _confirmTimetableConflicts,
                        onChanged: isBusy
                            ? null
                            : (value) {
                                setState(() {
                                  _confirmTimetableConflicts = value ?? false;
                                });
                              },
                        title: const Text(
                          'J\'autorise le remplacement des créneaux de classe en conflit.',
                        ),
                        subtitle: const Text(
                          'Les conflits enseignant/salle restent bloquants et doivent être corrigés dans le fichier.',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              _panelCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Erreurs détectées',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ...errors.take(20).map(
                        (row) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.error_outline, color: Color(0xFFB3261E)),
                          title: Text('Ligne ${_asInt(row['row'])}'),
                          subtitle: Text(_asText(row['error']).isEmpty ? row.toString() : _asText(row['error'])),
                        ),
                      ),
                      if (errors.length > 20)
                        Text('... ${errors.length - 20} erreur(s) supplémentaires'),
                    ],
                  ),
                ),
              ),
            ],
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _panelCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conflits détectés',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      ...conflicts.take(12).map(
                        (row) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A6700)),
                          title: Text(
                            'Ligne ${_asInt(row['row'])} • ${_asText(row['day_of_week'])} ${_asText(row['start_time'])}-${_asText(row['end_time'])}',
                          ),
                          subtitle: Text(
                            'Matière ${_asText(row['subject'])} • classe ${_listCount(row['class_conflicts'])} • enseignant ${_listCount(row['teacher_conflicts'])} • salle ${_listCount(row['room_conflicts'])}',
                          ),
                        ),
                      ),
                      if (conflicts.length > 12)
                        Text('... ${conflicts.length - 12} conflit(s) supplémentaires'),
                    ],
                  ),
                ),
              ),
            ],
            if (previewRows.isNotEmpty) ...[
              const SizedBox(height: 12),
              _panelCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Aperçu des lignes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: previewRows.first.keys
                              .map(
                                (key) => DataColumn(
                                  label: Text(key.replaceAll('_', ' ')),
                                ),
                              )
                              .toList(),
                          rows: previewRows.take(25).map((row) {
                            return DataRow(
                              cells: row.keys
                                  .map(
                                    (key) => DataCell(
                                      Text(_asText(row[key]).isEmpty ? '-' : _asText(row[key])),
                                    ),
                                  )
                                  .toList(),
                            );
                          }).toList(),
                        ),
                      ),
                      if (previewRows.length > 25) ...[
                        const SizedBox(height: 8),
                        Text('Affichage limité aux 25 premières lignes sur ${previewRows.length}.'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}