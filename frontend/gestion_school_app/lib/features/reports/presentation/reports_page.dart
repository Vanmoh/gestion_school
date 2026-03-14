import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/network/api_client.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  static const int _rowsPerPage = 10;

  bool _loading = true;
  bool _busy = false;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _payments = [];

  final _bulletinSearchController = TextEditingController();
  final _receiptSearchController = TextEditingController();

  int? _selectedStudentId;
  int? _selectedYearId;
  String _term = '1';
  int? _selectedPaymentId;
  int? _selectedClassroomId;
  String _cardsLayoutMode = 'a4_6up';
  int _bulletinPage = 1;
  int _receiptPage = 1;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _bulletinSearchController.dispose();
    _receiptSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    try {
      List<Map<String, dynamic>> students;
      List<Map<String, dynamic>> years;
      List<Map<String, dynamic>> payments;

      try {
        final response = await dio.get('/reports/context/');
        final payload = response.data is Map<String, dynamic>
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};

        students = _extractRows(payload['students']);
        years = _extractRows(payload['academic_years']);
        payments = _extractRows(payload['payments']);
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        if (statusCode != 404) {
          rethrow;
        }

        final responses = await Future.wait([
          dio.get('/students/'),
          dio.get('/academic-years/'),
          dio.get('/payments/'),
        ]);

        students = _extractRows(responses[0].data);
        years = _extractRows(responses[1].data);
        payments = _extractRows(responses[2].data);
      }

      if (!mounted) return;
      final classroomOptions = _classroomsFromStudents(students);
      setState(() {
        _students = students;
        _years = years;
        _payments = payments;
        _selectedStudentId ??= students.isNotEmpty
            ? _asInt(students.first['id'])
            : null;
        _selectedYearId ??= years.isNotEmpty ? _asInt(years.first['id']) : null;
        _selectedPaymentId ??= payments.isNotEmpty
            ? _asInt(payments.first['id'])
            : null;
        _selectedClassroomId ??= classroomOptions.isNotEmpty
            ? _asInt(classroomOptions.first['id'])
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement rapports: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _printBulletin() async {
    if (_selectedStudentId == null || _selectedYearId == null) {
      _showMessage('Sélectionnez un élève et une année académique.');
      return;
    }

    await _runBusyTask(() async {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/reports/bulletin/$_selectedStudentId/$_selectedYearId/$_term/',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = _toUint8List(response.data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    });
  }

  Future<void> _printReceipt() async {
    if (_selectedPaymentId == null) {
      _showMessage('Sélectionnez un paiement.');
      return;
    }

    await _runBusyTask(() async {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/reports/receipt/$_selectedPaymentId/',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = _toUint8List(response.data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    });
  }

  Future<void> _printStudentCard() async {
    if (_selectedStudentId == null) {
      _showMessage('Sélectionnez un élève.');
      return;
    }

    await _runBusyTask(() async {
      final dio = ref.read(dioProvider);
      final cacheBust = DateTime.now().millisecondsSinceEpoch;
      final response = await dio.get(
        '/reports/student-card/$_selectedStudentId/',
        queryParameters: {'_ts': cacheBust},
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = _toUint8List(response.data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    });
  }

  Future<void> _printClassCards() async {
    if (_selectedClassroomId == null || _selectedClassroomId! <= 0) {
      _showMessage('Sélectionnez une classe.');
      return;
    }

    await _runBusyTask(() async {
      final dio = ref.read(dioProvider);
      final cacheBust = DateTime.now().millisecondsSinceEpoch;
      final response = await dio.get(
        '/reports/student-cards/class/$_selectedClassroomId/',
        queryParameters: {
          'layout_mode': _cardsLayoutMode,
          '_ts': cacheBust,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = _toUint8List(response.data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    });
  }

  Future<void> _downloadPaymentsExcel() async {
    await _runBusyTask(() async {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/reports/payments/export-excel/',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = _toUint8List(response.data);
      final file = File(
        '${Directory.systemTemp.path}/paiements_export_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      _showMessage('Export Excel enregistré: ${file.path}');
    });
  }

  Future<void> _runBusyTask(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      _showMessage('Opération impossible: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final bulletinSearch = _bulletinSearchController.text.trim().toLowerCase();
    final bulletinRows = _students.where((row) {
      if (bulletinSearch.isEmpty) return true;
      return _studentLabel(row).toLowerCase().contains(bulletinSearch);
    }).toList();
    final bulletinTotalPages = bulletinRows.isEmpty
        ? 1
        : ((bulletinRows.length + _rowsPerPage - 1) ~/ _rowsPerPage);
    final bulletinCurrentPage = math.min(_bulletinPage, bulletinTotalPages);
    final bulletinStart = bulletinRows.isEmpty
        ? 0
        : (bulletinCurrentPage - 1) * _rowsPerPage;
    final bulletinEnd = math.min(
      bulletinStart + _rowsPerPage,
      bulletinRows.length,
    );
    final pagedBulletinRows = bulletinRows.isEmpty
        ? <Map<String, dynamic>>[]
        : bulletinRows.sublist(bulletinStart, bulletinEnd);

    final receiptSearch = _receiptSearchController.text.trim().toLowerCase();
    final receiptRows = _payments.where((row) {
      if (receiptSearch.isEmpty) return true;
      return _paymentLabel(row).toLowerCase().contains(receiptSearch);
    }).toList();
    final receiptTotalPages = receiptRows.isEmpty
        ? 1
        : ((receiptRows.length + _rowsPerPage - 1) ~/ _rowsPerPage);
    final receiptCurrentPage = math.min(_receiptPage, receiptTotalPages);
    final receiptStart = receiptRows.isEmpty
        ? 0
        : (receiptCurrentPage - 1) * _rowsPerPage;
    final receiptEnd = math.min(
      receiptStart + _rowsPerPage,
      receiptRows.length,
    );
    final pagedReceiptRows = receiptRows.isEmpty
        ? <Map<String, dynamic>>[]
        : receiptRows.sublist(receiptStart, receiptEnd);
    final classRows = _classroomsFromStudents(_students);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rapports',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Générez les bulletins, reçus et exports Excel à partir des données réelles.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _loadData,
              icon: const Icon(Icons.sync),
              label: const Text('Actualiser'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Bulletin scolaire (PDF)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedYearId,
                        decoration: const InputDecoration(
                          labelText: 'Année académique',
                        ),
                        items: _years
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: _asInt(row['id']),
                                child: Text(_yearLabel(row)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedYearId = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: _term,
                        decoration: const InputDecoration(
                          labelText: 'Trimestre',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: '1',
                            child: Text('Trimestre 1'),
                          ),
                          DropdownMenuItem(
                            value: '2',
                            child: Text('Trimestre 2'),
                          ),
                          DropdownMenuItem(
                            value: '3',
                            child: Text('Trimestre 3'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _term = value ?? '1');
                        },
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _bulletinSearchController,
                        decoration: const InputDecoration(
                          labelText: 'Rechercher élève',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) {
                          setState(() => _bulletinPage = 1);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (pagedBulletinRows.isEmpty)
                  const Text('Aucun élève trouvé.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 46,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 62,
                      columns: const [
                        DataColumn(label: Text('Matricule')),
                        DataColumn(label: Text('Élève')),
                        DataColumn(label: Text('Classe')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: pagedBulletinRows.map((row) {
                        final rowId = _asInt(row['id']);
                        final selected = rowId == _selectedStudentId;
                        return DataRow(
                          selected: selected,
                          onSelectChanged: (_) {
                            setState(() => _selectedStudentId = rowId);
                          },
                          cells: [
                            DataCell(Text(_studentMatricule(row))),
                            DataCell(Text(_studentName(row))),
                            DataCell(Text(_studentClassName(row))),
                            DataCell(
                              Wrap(
                                spacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(
                                        () => _selectedStudentId = rowId,
                                      );
                                    },
                                    child: const Text('Voir'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedStudentId = rowId;
                                            });
                                            _printBulletin();
                                          },
                                    child: const Text('Imprimer'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      bulletinRows.isEmpty
                          ? 'Aucun résultat'
                          : 'Affichage ${bulletinStart + 1}-$bulletinEnd sur ${bulletinRows.length}',
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Page précédente',
                          onPressed: bulletinCurrentPage > 1
                              ? () {
                                  setState(() {
                                    _bulletinPage = bulletinCurrentPage - 1;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Page $bulletinCurrentPage / $bulletinTotalPages'),
                        IconButton(
                          tooltip: 'Page suivante',
                          onPressed: bulletinCurrentPage < bulletinTotalPages
                              ? () {
                                  setState(() {
                                    _bulletinPage = bulletinCurrentPage + 1;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _printBulletin,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Imprimer le bulletin sélectionné'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Carte scolaire (PDF)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Modèle de carte scolaire adapté à la maquette fournie.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedStudentId,
                        decoration: const InputDecoration(labelText: 'Élève'),
                        items: _students
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: _asInt(row['id']),
                                child: Text(_studentLabel(row)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedStudentId = value);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 260,
                      child: DropdownButtonFormField<int>(
                        initialValue: _selectedClassroomId,
                        decoration: const InputDecoration(labelText: 'Classe'),
                        items: classRows
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: _asInt(row['id']),
                                child: Text(row['name']?.toString() ?? ''),
                              ),
                            )
                            .toList(),
                        onChanged: classRows.isEmpty
                            ? null
                            : (value) {
                                setState(() => _selectedClassroomId = value);
                              },
                      ),
                    ),
                    SizedBox(
                      width: 250,
                      child: DropdownButtonFormField<String>(
                        initialValue: _cardsLayoutMode,
                        decoration: const InputDecoration(
                          labelText: 'Mode impression cartes classe',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'standard',
                            child: Text('Standard (1 carte / page)'),
                          ),
                          DropdownMenuItem(
                            value: 'a4_6up',
                            child: Text('A4 (6 cartes / page)'),
                          ),
                          DropdownMenuItem(
                            value: 'a4_9up',
                            child: Text('A4 (9 cartes / page)'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _cardsLayoutMode = value ?? 'a4_6up';
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _printStudentCard,
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('Imprimer carte élève'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy || classRows.isEmpty
                          ? null
                          : _printClassCards,
                      icon: const Icon(Icons.grid_view_outlined),
                      label: const Text('Imprimer cartes classe'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Reçu de paiement (PDF)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _receiptSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Rechercher paiement',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      setState(() => _receiptPage = 1);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (pagedReceiptRows.isEmpty)
                  const Text('Aucun paiement trouvé.')
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 46,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 62,
                      columns: const [
                        DataColumn(label: Text('ID')),
                        DataColumn(label: Text('Élève')),
                        DataColumn(label: Text('Type frais')),
                        DataColumn(label: Text('Montant')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: pagedReceiptRows.map((row) {
                        final rowId = _asInt(row['id']);
                        final selected = rowId == _selectedPaymentId;
                        return DataRow(
                          selected: selected,
                          onSelectChanged: (_) {
                            setState(() => _selectedPaymentId = rowId);
                          },
                          cells: [
                            DataCell(Text('#$rowId')),
                            DataCell(Text(_paymentStudentName(row))),
                            DataCell(Text(_paymentFeeType(row))),
                            DataCell(Text(_paymentAmount(row))),
                            DataCell(Text(_paymentDate(row))),
                            DataCell(
                              Wrap(
                                spacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      setState(
                                        () => _selectedPaymentId = rowId,
                                      );
                                    },
                                    child: const Text('Voir'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedPaymentId = rowId;
                                            });
                                            _printReceipt();
                                          },
                                    child: const Text('Imprimer'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      receiptRows.isEmpty
                          ? 'Aucun résultat'
                          : 'Affichage ${receiptStart + 1}-$receiptEnd sur ${receiptRows.length}',
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Page précédente',
                          onPressed: receiptCurrentPage > 1
                              ? () {
                                  setState(() {
                                    _receiptPage = receiptCurrentPage - 1;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('Page $receiptCurrentPage / $receiptTotalPages'),
                        IconButton(
                          tooltip: 'Page suivante',
                          onPressed: receiptCurrentPage < receiptTotalPages
                              ? () {
                                  setState(() {
                                    _receiptPage = receiptCurrentPage + 1;
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _printReceipt,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Imprimer le reçu sélectionné'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Export paiements (Excel)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Télécharge un fichier .xlsx avec l\'historique des paiements.',
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _downloadPaymentsExcel,
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Exporter Excel'),
                ),
              ],
            ),
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

  String _studentLabel(Map<String, dynamic> row) {
    final registration =
        row['matricule']?.toString() ??
        row['registration_number']?.toString() ??
        'N/A';
    final fullName = row['user_full_name']?.toString().trim() ?? '';
    final first = row['user_first_name']?.toString() ?? '';
    final last = row['user_last_name']?.toString() ?? '';
    final fromParts = '$first $last'.trim();
    final name = fullName.isNotEmpty
        ? fullName
        : (fromParts.isNotEmpty ? fromParts : 'Élève ${row['id']}');
    return '$registration — $name';
  }

  String _studentMatricule(Map<String, dynamic> row) {
    final value =
        row['matricule']?.toString() ?? row['registration_number']?.toString();
    if (value == null || value.trim().isEmpty) return 'N/A';
    return value;
  }

  String _studentName(Map<String, dynamic> row) {
    final fullName = row['user_full_name']?.toString().trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final first = row['user_first_name']?.toString().trim() ?? '';
    final last = row['user_last_name']?.toString().trim() ?? '';
    final fromParts = '$first $last'.trim();
    if (fromParts.isNotEmpty) return fromParts;
    return 'Élève ${row['id']}';
  }

  String _studentClassName(Map<String, dynamic> row) {
    final className =
        row['classroom_name']?.toString() ?? row['classroom']?.toString() ?? '';
    if (className.trim().isEmpty) return 'Non attribuée';
    return className;
  }

  String _yearLabel(Map<String, dynamic> row) {
    final name = row['name']?.toString();
    if (name != null && name.isNotEmpty) return name;
    final start = row['start_date']?.toString() ?? '';
    final end = row['end_date']?.toString() ?? '';
    return '$start - $end';
  }

  String _paymentLabel(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '?';
    final amount = row['amount']?.toString() ?? '0';
    final fee = row['fee_type']?.toString() ?? 'N/A';
    return '#$id — $fee — $amount';
  }

  String _paymentStudentName(Map<String, dynamic> row) {
    final fullName =
        row['student_full_name']?.toString().trim() ??
        row['student_name']?.toString().trim() ??
        '';
    if (fullName.isNotEmpty) return fullName;
    final fromNested = row['student'] is Map
        ? (row['student']['full_name']?.toString().trim() ?? '')
        : '';
    if (fromNested.isNotEmpty) return fromNested;
    return 'Élève';
  }

  List<Map<String, dynamic>> _classroomsFromStudents(
    List<Map<String, dynamic>> students,
  ) {
    final byId = <int, String>{};
    for (final row in students) {
      final rawClassId = row['classroom'] ?? row['classroom_id'];
      final classId = _asInt(rawClassId);
      if (classId <= 0) continue;

      final className = (row['classroom_name']?.toString() ?? '').trim();
      byId[classId] = className.isEmpty ? 'Classe $classId' : className;
    }

    final entries = byId.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

    return entries
        .map((entry) => {'id': entry.key, 'name': entry.value})
        .toList();
  }

  String _paymentFeeType(Map<String, dynamic> row) {
    final feeType =
        row['fee_type']?.toString() ?? row['type']?.toString() ?? '';
    if (feeType.trim().isEmpty) return 'N/A';
    return feeType;
  }

  String _paymentAmount(Map<String, dynamic> row) {
    final amount = row['amount']?.toString() ?? row['paid_amount']?.toString();
    if (amount == null || amount.trim().isEmpty) return '0';
    return amount;
  }

  String _paymentDate(Map<String, dynamic> row) {
    final date =
        row['payment_date']?.toString() ?? row['created_at']?.toString() ?? '';
    if (date.trim().isEmpty) return '-';
    return date.length > 10 ? date.substring(0, 10) : date;
  }

  Uint8List _toUint8List(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) return Uint8List.fromList(data.cast<int>());
    throw Exception('Réponse binaire invalide');
  }
}
