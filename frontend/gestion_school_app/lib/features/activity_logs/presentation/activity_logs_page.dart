import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/network/api_client.dart';

class ActivityLogsPage extends ConsumerStatefulWidget {
  const ActivityLogsPage({super.key});

  @override
  ConsumerState<ActivityLogsPage> createState() => _ActivityLogsPageState();
}

class _ActivityLogsPageState extends ConsumerState<ActivityLogsPage> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _logs = [];

  final _searchController = TextEditingController();
  String _methodFilter = '';
  String _successFilter = '';
  String _ordering = '-created_at';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final response = await ref
          .read(dioProvider)
          .get('/activity-logs/', queryParameters: _query());

      final rows = _extractRows(response.data);
      if (!mounted) return;
      setState(() => _logs = rows);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur chargement logs: $error')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _query() {
    final query = <String, dynamic>{};
    if (_searchController.text.trim().isNotEmpty) {
      query['search'] = _searchController.text.trim();
    }
    if (_methodFilter.isNotEmpty) {
      query['method'] = _methodFilter;
    }
    if (_successFilter.isNotEmpty) {
      query['success'] = _successFilter;
    }
    if (_dateFrom != null) {
      query['date_from'] = _apiDate(_dateFrom!);
    }
    if (_dateTo != null) {
      query['date_to'] = _apiDate(_dateTo!);
    }
    if (_ordering.isNotEmpty) {
      query['ordering'] = _ordering;
    }
    return query;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_dateFrom ?? DateTime.now())
        : (_dateTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  Future<void> _exportExcel() async {
    await _runBusyTask(() async {
      final response = await ref
          .read(dioProvider)
          .get(
            '/activity-logs/export-excel/',
            queryParameters: _query(),
            options: Options(responseType: ResponseType.bytes),
          );
      final bytes = _toUint8List(response.data);
      final file = File(
        '${Directory.systemTemp.path}/activity_logs_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      await file.writeAsBytes(bytes, flush: true);
      _showMessage('Export Excel enregistré: ${file.path}');
    });
  }

  Future<void> _exportPdf() async {
    await _runBusyTask(() async {
      final response = await ref
          .read(dioProvider)
          .get(
            '/activity-logs/export-pdf/',
            queryParameters: _query(),
            options: Options(responseType: ResponseType.bytes),
          );
      final bytes = _toUint8List(response.data);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
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
        Text(
          'Logs d\'activités',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          'Historique des actions utilisateurs (audit et sécurité).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Recherche (action, path, user...)',
                    ),
                    onSubmitted: (_) => _loadData(),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _methodFilter,
                    decoration: const InputDecoration(labelText: 'Méthode'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Toutes')),
                      DropdownMenuItem(value: 'POST', child: Text('POST')),
                      DropdownMenuItem(value: 'PUT', child: Text('PUT')),
                      DropdownMenuItem(value: 'PATCH', child: Text('PATCH')),
                      DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
                    ],
                    onChanged: (value) =>
                        setState(() => _methodFilter = value ?? ''),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _successFilter,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Tous')),
                      DropdownMenuItem(value: 'true', child: Text('Succès')),
                      DropdownMenuItem(value: 'false', child: Text('Échec')),
                    ],
                    onChanged: (value) =>
                        setState(() => _successFilter = value ?? ''),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String>(
                    initialValue: _ordering,
                    decoration: const InputDecoration(labelText: 'Tri'),
                    items: const [
                      DropdownMenuItem(
                        value: '-created_at',
                        child: Text('Date (récent → ancien)'),
                      ),
                      DropdownMenuItem(
                        value: 'created_at',
                        child: Text('Date (ancien → récent)'),
                      ),
                      DropdownMenuItem(
                        value: 'action',
                        child: Text('Action (A → Z)'),
                      ),
                      DropdownMenuItem(
                        value: '-action',
                        child: Text('Action (Z → A)'),
                      ),
                      DropdownMenuItem(
                        value: '-status_code',
                        child: Text('Statut HTTP (desc)'),
                      ),
                      DropdownMenuItem(
                        value: 'status_code',
                        child: Text('Statut HTTP (asc)'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _ordering = value ?? '-created_at'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: true),
                  icon: const Icon(Icons.event),
                  label: Text(
                    _dateFrom == null ? 'Date début' : _apiDate(_dateFrom!),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: false),
                  icon: const Icon(Icons.event),
                  label: Text(
                    _dateTo == null ? 'Date fin' : _apiDate(_dateTo!),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.search),
                  label: const Text('Filtrer'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _exportExcel,
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Exporter Excel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Exporter PDF'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _methodFilter = '';
                      _successFilter = '';
                      _ordering = '-created_at';
                      _dateFrom = null;
                      _dateTo = null;
                    });
                    _loadData();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réinitialiser'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Événements récents',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_logs.isEmpty)
                  const Text('Aucune activité trouvée')
                else
                  ..._logs
                      .take(150)
                      .map(
                        (row) => Card(
                          child: ListTile(
                            leading: Icon(
                              row['success'] == true
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              color: row['success'] == true
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            title: Text(
                              '${row['action'] ?? '-'} • ${row['method'] ?? '-'}',
                            ),
                            subtitle: Text(
                              '${row['created_at'] ?? ''}\n'
                              'Utilisateur: ${row['user_display'] ?? row['role'] ?? 'Anonyme'}\n'
                              'Path: ${row['path'] ?? ''}\n'
                              'Status: ${row['status_code'] ?? '-'} • IP: ${row['ip_address'] ?? '-'}',
                            ),
                            isThreeLine: true,
                          ),
                        ),
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

  Uint8List _toUint8List(dynamic data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is List) return Uint8List.fromList(data.cast<int>());
    throw Exception('Réponse binaire invalide');
  }

  String _apiDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
