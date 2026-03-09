import 'dart:io';
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
  bool _loading = true;
  bool _busy = false;

  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _payments = [];

  int? _selectedStudentId;
  int? _selectedYearId;
  String _term = '1';
  int? _selectedPaymentId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get('/reports/context/');
      final payload = response.data is Map<String, dynamic>
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};

      final students = _extractRows(payload['students']);
      final years = _extractRows(payload['academic_years']);
      final payments = _extractRows(payload['payments']);

      if (!mounted) return;
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

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Rapports', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Générez les bulletins, reçus et exports Excel à partir des données réelles.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bulletin scolaire (PDF)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
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
                  onChanged: (value) =>
                      setState(() => _selectedStudentId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
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
                  onChanged: (value) => setState(() => _selectedYearId = value),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _term,
                  decoration: const InputDecoration(labelText: 'Trimestre'),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('Trimestre 1')),
                    DropdownMenuItem(value: '2', child: Text('Trimestre 2')),
                    DropdownMenuItem(value: '3', child: Text('Trimestre 3')),
                  ],
                  onChanged: (value) => setState(() => _term = value ?? '1'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _printBulletin,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Ouvrir / Imprimer le bulletin'),
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
                  'Reçu de paiement (PDF)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedPaymentId,
                  decoration: const InputDecoration(labelText: 'Paiement'),
                  items: _payments
                      .map(
                        (row) => DropdownMenuItem<int>(
                          value: _asInt(row['id']),
                          child: Text(_paymentLabel(row)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedPaymentId = value),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _printReceipt,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Ouvrir / Imprimer le reçu'),
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

  Uint8List _toUint8List(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) return Uint8List.fromList(data.cast<int>());
    throw Exception('Réponse binaire invalide');
  }
}
