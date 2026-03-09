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

  String _viewMode = 'classroom';

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

  Future<void> _printCurrentView() async {
    final teacherById = {for (final t in _teachers) _asInt(t['id']): t};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};
    final classroomById = {for (final c in _classrooms) _asInt(c['id']): c};

    final grouped = _groupedAssignments();
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
        pageFormat: PdfPageFormat.a4,
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
              'EMPLOI DU TEMPS (AFFECTATIONS)',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _viewMode == 'classroom'
                  ? 'Vue par classe'
                  : 'Vue par enseignant',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Généré le $generatedAt',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 12),
          ];

          for (final entry in grouped.entries) {
            widgets.add(
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text(
                  entry.key,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            );

            for (final row in entry.value) {
              final subject = subjectById[_asInt(row['subject'])];
              final teacher = teacherById[_asInt(row['teacher'])];
              final classroom = classroomById[_asInt(row['classroom'])];

              widgets.add(
                pw.Bullet(
                  text:
                      '${subject?['code'] ?? 'MAT'} - ${subject?['name'] ?? ''} | '
                      'Classe: ${classroom?['name'] ?? row['classroom']} | '
                      'Enseignant: ${teacher?['employee_code'] ?? row['teacher']}',
                ),
              );
            }

            widgets.add(pw.SizedBox(height: 8));
          }

          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final grouped = _groupedAssignments();

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Emploi du temps',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Vue pédagogique basée sur les affectations enseignants/matières/classes.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'classroom',
                  label: Text('Par classe'),
                  icon: Icon(Icons.class_rounded),
                ),
                ButtonSegment(
                  value: 'teacher',
                  label: Text('Par enseignant'),
                  icon: Icon(Icons.badge_outlined),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (value) {
                setState(() => _viewMode = value.first);
              },
            ),
            FilledButton.tonalIcon(
              onPressed: _printCurrentView,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Imprimer PDF'),
            ),
            FilledButton.tonalIcon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_assignments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune affectation disponible.'),
            ),
          )
        else
          ...grouped.entries.map(
            (entry) => Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    ...entry.value.map(
                      (row) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: Text(
                          '${row['subjectCode']} - ${row['subjectName']}',
                        ),
                        subtitle: Text(
                          'Classe: ${row['classroomName']} • Enseignant: ${row['teacherCode']}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupedAssignments() {
    final teacherById = {for (final t in _teachers) _asInt(t['id']): t};
    final subjectById = {for (final s in _subjects) _asInt(s['id']): s};
    final classroomById = {for (final c in _classrooms) _asInt(c['id']): c};

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final row in _assignments) {
      final teacher = teacherById[_asInt(row['teacher'])];
      final subject = subjectById[_asInt(row['subject'])];
      final classroom = classroomById[_asInt(row['classroom'])];

      final teacherCode = (teacher?['employee_code'] ?? 'ENS-${row['teacher']}')
          .toString();
      final classroomName = (classroom?['name'] ?? 'Classe ${row['classroom']}')
          .toString();
      final subjectCode = (subject?['code'] ?? 'MAT').toString();
      final subjectName = (subject?['name'] ?? '').toString();

      final groupKey = _viewMode == 'classroom' ? classroomName : teacherCode;
      final enriched = {
        ...row,
        'teacherCode': teacherCode,
        'classroomName': classroomName,
        'subjectCode': subjectCode,
        'subjectName': subjectName,
      };

      grouped.putIfAbsent(groupKey, () => []).add(enriched);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    return {for (final key in sortedKeys) key: grouped[key]!};
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
