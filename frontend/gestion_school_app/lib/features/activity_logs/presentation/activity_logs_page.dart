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
  String? _selectedLogKey;

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
      setState(() {
        _logs = rows;
        if (_selectedLogKey == null && rows.isNotEmpty) {
          _selectedLogKey = _logKey(rows.first);
          return;
        }

        if (_selectedLogKey != null &&
            !rows.any((row) => _logKey(row) == _selectedLogKey)) {
          _selectedLogKey = rows.isNotEmpty ? _logKey(rows.first) : null;
        }
      });
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

  Future<void> _refreshLogs() async {
    await _loadData();
  }

  Future<void> _resetFilters() async {
    setState(() {
      _searchController.clear();
      _methodFilter = '';
      _successFilter = '';
      _ordering = '-created_at';
      _dateFrom = null;
      _dateTo = null;
    });
    await _loadData();
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
      _showMessage('Export Excel enregistré: ${file.path}', isSuccess: true);
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

  Map<String, dynamic>? _selectedLog() {
    if (_selectedLogKey == null) return null;
    for (final row in _logs) {
      if (_logKey(row) == _selectedLogKey) {
        return row;
      }
    }
    return null;
  }

  String _logKey(Map<String, dynamic> row) {
    final id = row['id'];
    if (id != null) {
      return 'id:$id';
    }
    final createdAt = row['created_at']?.toString() ?? '-';
    final path = row['path']?.toString() ?? '-';
    final method = row['method']?.toString() ?? '-';
    return 'fallback:$createdAt|$path|$method';
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

  Widget _statusChip(Map<String, dynamic> row) {
    final success = row['success'] == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: success ? const Color(0xFFE7F6EC) : const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        success ? 'Succes' : 'Echec',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: success ? const Color(0xFF1E7B3D) : const Color(0xFFB42318),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _showLogDetailsDialog(Map<String, dynamic> row) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Evenement ${row['id'] ?? '-'}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailLine('Date', row['created_at']?.toString() ?? '-'),
                  _detailLine('Action', row['action']?.toString() ?? '-'),
                  _detailLine('Methode', row['method']?.toString() ?? '-'),
                  _detailLine('Path', row['path']?.toString() ?? '-'),
                  _detailLine(
                    'Utilisateur',
                    row['user_display']?.toString() ??
                        row['role']?.toString() ??
                        'Anonyme',
                  ),
                  _detailLine(
                    'Code HTTP',
                    row['status_code']?.toString() ?? '-',
                  ),
                  _detailLine(
                    'IP',
                    row['ip_address']?.toString().trim().isEmpty == true
                        ? '-'
                        : row['ip_address']?.toString() ?? '-',
                  ),
                  _detailLine('Succes', row['success'] == true ? 'Oui' : 'Non'),
                  _detailLine(
                    'Payload',
                    row['payload']?.toString().trim().isEmpty == true
                        ? '-'
                        : row['payload']?.toString() ?? '-',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return RefreshIndicator(
        onRefresh: _refreshLogs,
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
    final totalLogs = _logs.length;
    final successfulLogs = _logs.where((row) => row['success'] == true).length;
    final failedLogs = totalLogs - successfulLogs;
    final errorStatusLogs = _logs.where((row) {
      final code = int.tryParse(row['status_code']?.toString() ?? '');
      return code != null && code >= 400;
    }).length;

    final users = _logs
        .map(
          (row) => row['user_display']?.toString().trim().isNotEmpty == true
              ? row['user_display'].toString().trim()
              : (row['role']?.toString().trim().isNotEmpty == true
                    ? row['role'].toString().trim()
                    : 'Anonyme'),
        )
        .toSet()
        .length;

    final selectedLog = _selectedLog();

    return RefreshIndicator(
      onRefresh: _refreshLogs,
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
                      'Logs activites',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Historique des actions utilisateurs pour audit et securite.',
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
          if (_busy) ...[
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
                _metricChip('Total logs', '$totalLogs'),
                _metricChip('Succes', '$successfulLogs'),
                _metricChip('Echecs', '$failedLogs'),
                _metricChip('HTTP >= 400', '$errorStatusLogs'),
                _metricChip('Utilisateurs', '$users'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'Filtres et exports',
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
                    decoration: const InputDecoration(labelText: 'Methode'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Toutes')),
                      DropdownMenuItem(value: 'POST', child: Text('POST')),
                      DropdownMenuItem(value: 'PUT', child: Text('PUT')),
                      DropdownMenuItem(value: 'PATCH', child: Text('PATCH')),
                      DropdownMenuItem(value: 'DELETE', child: Text('DELETE')),
                    ],
                    onChanged: (value) {
                      setState(() => _methodFilter = value ?? '');
                    },
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<String>(
                    initialValue: _successFilter,
                    decoration: const InputDecoration(labelText: 'Statut'),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Tous')),
                      DropdownMenuItem(value: 'true', child: Text('Succes')),
                      DropdownMenuItem(value: 'false', child: Text('Echec')),
                    ],
                    onChanged: (value) {
                      setState(() => _successFilter = value ?? '');
                    },
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
                        child: Text('Date (recent -> ancien)'),
                      ),
                      DropdownMenuItem(
                        value: 'created_at',
                        child: Text('Date (ancien -> recent)'),
                      ),
                      DropdownMenuItem(
                        value: 'action',
                        child: Text('Action (A -> Z)'),
                      ),
                      DropdownMenuItem(
                        value: '-action',
                        child: Text('Action (Z -> A)'),
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
                    onChanged: (value) {
                      setState(() => _ordering = value ?? '-created_at');
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(isFrom: true),
                  icon: const Icon(Icons.event),
                  label: Text(
                    _dateFrom == null ? 'Date debut' : _apiDate(_dateFrom!),
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
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reinitialiser'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1120;

              final logsPanel = _sectionCard(
                title: 'Journal des evenements',
                child: _logs.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('Aucune activite trouvee'),
                      )
                    : SizedBox(
                        height: isWide ? 620 : 420,
                        child: ListView.separated(
                          itemCount: _logs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final row = _logs[index];
                            final selected = _logKey(row) == _selectedLogKey;
                            final action = row['action']?.toString() ?? '-';
                            final method = row['method']?.toString() ?? '-';
                            final createdAt =
                                row['created_at']?.toString() ?? '-';
                            final user =
                                row['user_display']
                                        ?.toString()
                                        .trim()
                                        .isNotEmpty ==
                                    true
                                ? row['user_display'].toString().trim()
                                : (row['role']?.toString().trim().isNotEmpty ==
                                          true
                                      ? row['role'].toString().trim()
                                      : 'Anonyme');

                            return Material(
                              color: selected
                                  ? colorScheme.primaryContainer.withValues(
                                      alpha: 0.45,
                                    )
                                  : colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  setState(
                                    () => _selectedLogKey = _logKey(row),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    10,
                                    10,
                                    10,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _statusChip(row),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$action • $method',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              createdAt,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              user,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              row['path']?.toString() ?? '-',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        row['status_code']?.toString() ?? '-',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelLarge,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              );

              final detailPanel = _sectionCard(
                title: 'Details evenement',
                child: selectedLog == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Selectionnez un evenement pour afficher les details.',
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    _showLogDetailsDialog(selectedLog),
                                icon: const Icon(Icons.visibility),
                                label: const Text('Afficher'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : _exportExcel,
                                icon: const Icon(Icons.table_view_outlined),
                                label: const Text('Excel'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : _exportPdf,
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('PDF'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _detailLine(
                            'Date',
                            selectedLog['created_at']?.toString() ?? '-',
                          ),
                          _detailLine(
                            'Action',
                            selectedLog['action']?.toString() ?? '-',
                          ),
                          _detailLine(
                            'Methode',
                            selectedLog['method']?.toString() ?? '-',
                          ),
                          _detailLine(
                            'Utilisateur',
                            selectedLog['user_display']?.toString() ??
                                selectedLog['role']?.toString() ??
                                'Anonyme',
                          ),
                          _detailLine(
                            'Path',
                            selectedLog['path']?.toString() ?? '-',
                          ),
                          _detailLine(
                            'Code HTTP',
                            selectedLog['status_code']?.toString() ?? '-',
                          ),
                          _detailLine(
                            'IP',
                            selectedLog['ip_address']
                                        ?.toString()
                                        .trim()
                                        .isEmpty ==
                                    true
                                ? '-'
                                : selectedLog['ip_address']?.toString() ?? '-',
                          ),
                          _detailLine(
                            'Succes',
                            selectedLog['success'] == true ? 'Oui' : 'Non',
                          ),
                        ],
                      ),
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: logsPanel),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: detailPanel),
                  ],
                );
              }

              return Column(
                children: [logsPanel, const SizedBox(height: 12), detailPanel],
              );
            },
          ),
        ],
      ),
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
