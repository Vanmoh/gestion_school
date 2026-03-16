import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/constants/branding.dart';
import '../../../core/network/api_client.dart';

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
  int? _selectedClassroom;

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

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);

    try {
      final results = await Future.wait([
        dio.get('/teachers/'),
        dio.get('/subjects/'),
        dio.get('/classrooms/'),
        dio.get('/teacher-assignments/'),
        dio.get('/teacher-schedule-slots/'),
      ]);

      if (!mounted) return;

      setState(() {
        _teachers = _extractRows(results[0].data);
        _subjects = _extractRows(results[1].data);
        _classrooms = _extractRows(results[2].data);
        _assignments = _extractRows(results[3].data);
        _scheduleSlots = _extractRows(results[4].data);

        final classIds = _classrooms.map((row) => _asInt(row['id'])).toSet();
        if (_selectedClassroom == null ||
            !classIds.contains(_selectedClassroom)) {
          _selectedClassroom = _classrooms.isNotEmpty
              ? _asInt(_classrooms.first['id'])
              : null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement emploi du temps: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _printCurrentClassTablePdf() async {
    final classroomId = _selectedClassroom;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionnez une classe avant impression.');
      return;
    }

    final assignmentById = _assignmentById();
    final slotsByClass = _slotsByClass(assignmentById);
    final classSlots = slotsByClass[classroomId] ?? <Map<String, dynamic>>[];

    if (classSlots.isEmpty) {
      _showMessage('Aucun créneau planifié pour cette classe.');
      return;
    }

    final matrix = _classMatrix(classSlots);
    final ranges = matrix.keys.toList()
      ..sort((a, b) => _rangeStartMinutes(a).compareTo(_rangeStartMinutes(b)));

    final className = _classNameById(classroomId);

    pw.MemoryImage? logoImage;
    try {
      final logoData = await rootBundle.load(SchoolBranding.logoAsset);
      logoImage = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    final generatedAt = _dateTimeLabel(DateTime.now());

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    width: 46,
                    height: 46,
                    margin: const pw.EdgeInsets.only(right: 10),
                    child: pw.Image(logoImage),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        SchoolBranding.schoolName,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '${SchoolBranding.level} • Tel: ${SchoolBranding.phone}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                      pw.Text(
                        'Application: ${SchoolBranding.schoolShort} - GESTION SCHOOL',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Text(
              'EMPLOI DU TEMPS - GRILLE HEBDOMADAIRE',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Classe: $className',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Généré le $generatedAt',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 12),
          ];

          final headers = ['Créneau', ..._dayOrder.map(_dayLabel)];
          final data = ranges.map((range) {
            final dayMap =
                matrix[range] ?? const <String, List<Map<String, dynamic>>>{};
            return <String>[
              range,
              ..._dayOrder.map((dayCode) {
                final slots = dayMap[dayCode] ?? const <Map<String, dynamic>>[];
                return _slotsExportCell(slots);
              }),
            ];
          }).toList();

          widgets.add(
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerLeft,
            ),
          );

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
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
      _showMessage('Aucun créneau planifié pour cette classe.');
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
    buffer.writeln('Créneau;Lundi;Mardi;Mercredi;Jeudi;Vendredi;Samedi');

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
    _showMessage('Export Excel (CSV) lancé: $fileName');
  }

  Future<void> _refreshTimetable() async {
    await _loadData();
  }

  Future<void> _openSlotDialog({
    Map<String, dynamic>? slot,
    int? forceClassroomId,
  }) async {
    final classroomId = forceClassroomId ?? _selectedClassroom;
    if (classroomId == null || classroomId <= 0) {
      _showMessage('Sélectionnez une classe avant d\'ajouter un créneau.');
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
            return AlertDialog(
              title: Text(
                isEdit ? 'Modifier un créneau' : 'Ajouter un créneau',
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
                                '${row['subjectCode']} - ${row['subjectName']} • ${row['teacherCode']}',
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
                      decoration: const InputDecoration(
                        labelText: 'Salle (optionnel)',
                      ),
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
                      : () => Navigator.of(dialogContext).pop(true),
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
        isEdit ? 'Créneau modifié avec succès.' : 'Créneau ajouté avec succès.',
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur enregistrement créneau: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteSlot(Map<String, dynamic> slot) async {
    final slotId = _asInt(slot['slotId'] ?? slot['id']);
    if (slotId <= 0) {
      _showMessage('Créneau invalide.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer le créneau'),
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
      _showMessage('Créneau supprimé.');
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Erreur suppression créneau: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

    final colorScheme = Theme.of(context).colorScheme;
    final classesWithSlots = _classrooms
        .where((row) => (slotsByClass[_asInt(row['id'])] ?? []).isNotEmpty)
        .length;

    final selectedClassId = _selectedClassroom;
    final selectedClassName = _classNameById(selectedClassId);
    final selectedAssignments = selectedClassId == null
        ? <Map<String, dynamic>>[]
        : (assignmentsByClass[selectedClassId] ?? <Map<String, dynamic>>[]);
    final selectedSlots = selectedClassId == null
        ? <Map<String, dynamic>>[]
        : (slotsByClass[selectedClassId] ?? <Map<String, dynamic>>[]);

    final controlsPanel = _sectionCard(
      title: 'Filtres et actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: (_saving || selectedClassId == null)
                    ? null
                    : () => _openSlotDialog(forceClassroomId: selectedClassId),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Ajouter créneau'),
              ),
              FilledButton.tonalIcon(
                onPressed: (_saving || selectedClassId == null)
                    ? null
                    : _printCurrentClassTablePdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Imprimer tableau PDF'),
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
            ],
          ),
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
                    _metricChip('Créneaux classe', '${selectedSlots.length}'),
                  ],
                ),
                const SizedBox(height: 10),
                if (selectedAssignments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Aucune affectation pour cette classe. Créez des affectations puis des créneaux.',
                    ),
                  )
                else
                  _buildClassWeeklyGrid(
                    classId: selectedClassId,
                    classSlots: selectedSlots,
                  ),
              ],
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
                      '${classSlots.length} créneau(x) • ${classAssignments.length} affectation(s)',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () =>
                                    _openSlotDialog(forceClassroomId: classId),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter créneau'),
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
                _metricChip('Créneaux', '${_scheduleSlots.length}'),
                _metricChip('Classes planifiées', '$classesWithSlots'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          controlsPanel,
          const SizedBox(height: 12),
          selectedClassPanel,
          const SizedBox(height: 12),
          perClassPanel,
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
      final classroomName = (classroom?['name'] ?? 'Classe $classId')
          .toString();
      final subjectCode = (subject?['code'] ?? 'MAT').toString();
      final subjectName = (subject?['name'] ?? '').toString();
      final coefficient = (subject?['coefficient'] ?? '').toString();

      map[assignmentId] = {
        ...row,
        'teacherCode': teacherCode,
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
          return (a['teacherCode'] ?? '').toString().compareTo(
            (b['teacherCode'] ?? '').toString(),
          );
        });
      }
    }

    return matrix;
  }

  Widget _buildClassWeeklyGrid({
    required int classId,
    required List<Map<String, dynamic>> classSlots,
  }) {
    if (classSlots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('Aucun créneau planifié pour cette classe.'),
      );
    }

    final matrix = _classMatrix(classSlots);
    final ranges = matrix.keys.toList()
      ..sort((a, b) => _rangeStartMinutes(a).compareTo(_rangeStartMinutes(b)));

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
          const DataColumn(label: Text('Créneau')),
          ..._dayOrder.map(
            (dayCode) => DataColumn(label: Text(_dayLabel(dayCode))),
          ),
        ],
        rows: ranges.map((range) {
          final dayMap =
              matrix[range] ?? const <String, List<Map<String, dynamic>>>{};
          return DataRow(
            cells: [
              DataCell(Text(range)),
              ..._dayOrder.map((dayCode) {
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
                    'Ens: ${slots[i]['teacherCode']}',
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
                        tooltip: 'Modifier créneau',
                        onPressed: _saving
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
                        tooltip: 'Supprimer créneau',
                        onPressed: _saving ? null : () => _deleteSlot(slots[i]),
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
    final base =
        '${slot['subjectCode'] ?? 'MAT'} (${slot['teacherCode'] ?? 'ENS'})';
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
