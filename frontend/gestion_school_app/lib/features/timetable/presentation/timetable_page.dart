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
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _classrooms = [];
  List<Map<String, dynamic>> _assignments = [];
  int? _selectedClassroom;

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
      ]);

      if (!mounted) return;

      setState(() {
        _teachers = _extractRows(results[0].data);
        _subjects = _extractRows(results[1].data);
        _classrooms = _extractRows(results[2].data);
        _assignments = _extractRows(results[3].data);

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

    final byClass = _classTimetableRows();
    final rows = byClass[classroomId] ?? <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      _showMessage('Aucune affectation disponible pour cette classe.');
      return;
    }

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
              'EMPLOI DU TEMPS - TABLEAU PAR CLASSE',
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

          widgets.add(
            pw.TableHelper.fromTextArray(
              headers: const [
                'N°',
                'Code matière',
                'Matière',
                'Coefficient',
                'Code enseignant',
              ],
              data: List<List<String>>.generate(rows.length, (index) {
                final row = rows[index];
                return [
                  '${index + 1}',
                  '${row['subjectCode']}',
                  '${row['subjectName']}',
                  '${row['coefficient']}',
                  '${row['teacherCode']}',
                ];
              }),
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

    final byClass = _classTimetableRows();
    final rows = byClass[classroomId] ?? <Map<String, dynamic>>[];
    if (rows.isEmpty) {
      _showMessage('Aucune affectation disponible pour cette classe.');
      return;
    }

    final className = _classNameById(classroomId);
    final buffer = StringBuffer();
    buffer.writeln('Emploi du temps (tableau classe)');
    buffer.writeln('Classe;${_csvCell(className)}');
    buffer.writeln('Genere le;${_csvCell(_dateTimeLabel(DateTime.now()))}');
    buffer.writeln('');
    buffer.writeln('N°;Code matière;Matière;Coefficient;Code enseignant');

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      buffer.writeln(
        '${i + 1};${_csvCell(row['subjectCode'])};${_csvCell(row['subjectName'])};${_csvCell(row['coefficient'])};${_csvCell(row['teacherCode'])}',
      );
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

    final byClass = _classTimetableRows();
    final colorScheme = Theme.of(context).colorScheme;
    final classesWithAssignments = _classrooms
        .where((row) => (byClass[_asInt(row['id'])] ?? []).isNotEmpty)
        .length;

    final selectedClassId = _selectedClassroom;
    final selectedClassName = _classNameById(selectedClassId);
    final selectedRows = selectedClassId == null
        ? <Map<String, dynamic>>[]
        : (byClass[selectedClassId] ?? <Map<String, dynamic>>[]);

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
              FilledButton.tonalIcon(
                onPressed: _printCurrentClassTablePdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Imprimer tableau PDF'),
              ),
              FilledButton.tonalIcon(
                onPressed: _exportCurrentClassCsv,
                icon: const Icon(Icons.grid_on_outlined),
                label: const Text('Exporter Excel (CSV)'),
              ),
              FilledButton.tonalIcon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualiser'),
              ),
            ],
          ),
        ],
      ),
    );

    final selectedClassPanel = _sectionCard(
      title: 'Tableau Excel - $selectedClassName',
      child: selectedRows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Aucune affectation disponible pour cette classe.'),
            )
          : _buildClassExcelTable(selectedRows, showClassColumn: false),
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
                final rows = byClass[classId] ?? <Map<String, dynamic>>[];

                return Card(
                  child: ExpansionTile(
                    initiallyExpanded: classId == _selectedClassroom,
                    title: Text(className),
                    subtitle: Text('${rows.length} affectation(s)'),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      rows.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'Aucune affectation pour cette classe.',
                              ),
                            )
                          : _buildClassExcelTable(rows, showClassColumn: false),
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
                onPressed: _loadData,
                icon: const Icon(Icons.sync),
                label: const Text('Actualiser'),
              ),
            ],
          ),
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
                _metricChip('Classes planifiees', '$classesWithAssignments'),
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

  Map<int, List<Map<String, dynamic>>> _classTimetableRows() {
    final teacherById = {for (final t in _teachers) _asInt(t['id']): t};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};
    final classroomById = {for (final c in _classrooms) _asInt(c['id']): c};

    final Map<int, List<Map<String, dynamic>>> grouped = {};

    for (final row in _assignments) {
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

      final enriched = {
        ...row,
        'classroomId': classId,
        'teacherCode': teacherCode,
        'classroomName': classroomName,
        'subjectCode': subjectCode,
        'subjectName': subjectName,
        'coefficient': coefficient,
      };

      grouped.putIfAbsent(classId, () => []).add(enriched);
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

  String _classNameById(int? classId) {
    if (classId == null || classId <= 0) return 'Classe';
    for (final row in _classrooms) {
      if (_asInt(row['id']) == classId) {
        return (row['name'] ?? 'Classe $classId').toString();
      }
    }
    return 'Classe $classId';
  }

  Widget _buildClassExcelTable(
    List<Map<String, dynamic>> rows, {
    required bool showClassColumn,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 22,
        headingRowColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surfaceContainer,
        ),
        columns: [
          const DataColumn(label: Text('N°')),
          if (showClassColumn) const DataColumn(label: Text('Classe')),
          const DataColumn(label: Text('Code matière')),
          const DataColumn(label: Text('Matière')),
          const DataColumn(label: Text('Coefficient')),
          const DataColumn(label: Text('Code enseignant')),
        ],
        rows: List<DataRow>.generate(rows.length, (index) {
          final row = rows[index];

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              if (showClassColumn) DataCell(Text('${row['classroomName']}')),
              DataCell(Text('${row['subjectCode']}')),
              DataCell(Text('${row['subjectName']}')),
              DataCell(Text('${row['coefficient']}')),
              DataCell(Text('${row['teacherCode']}')),
            ],
          );
        }),
      ),
    );
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
