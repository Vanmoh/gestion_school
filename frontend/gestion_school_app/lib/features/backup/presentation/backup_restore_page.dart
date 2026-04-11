import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../models/etablissement.dart';
import '../../auth/presentation/auth_controller.dart';

class BackupRestorePage extends ConsumerStatefulWidget {
  const BackupRestorePage({super.key});

  @override
  ConsumerState<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends ConsumerState<BackupRestorePage> {
  static const List<String> _backupBases = <String>[
    '/backup-archives',
    '/common/backup-archives',
  ];

  bool _loading = true;
  bool _busy = false;
  bool _historyRefreshing = false;
  List<Map<String, dynamic>> _rows = [];
  Timer? _historyAutoRefreshTimer;

  String _createScope = 'etablissement';
  bool _includeMedia = true;
  final TextEditingController _notesController = TextEditingController();

  String _restoreScope = 'etablissement';
  PlatformFile? _restoreFile;
  final TextEditingController _restoreNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    _historyAutoRefreshTimer?.cancel();
    _notesController.dispose();
    _restoreNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadRows({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _loading = true);
    }
    try {
      final response = await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).get('$base/'),
      );
      final data = response.data;
      final List<dynamic> raw =
          data is Map<String, dynamic> && data['results'] is List<dynamic>
          ? data['results'] as List<dynamic>
          : (data is List<dynamic> ? data : <dynamic>[]);
      setState(() {
        _rows = raw
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      });
      _syncHistoryAutoRefresh();
    } catch (error) {
      if (showLoading) {
        _showMessage('Erreur chargement backups: $error');
      }
    } finally {
      if (mounted && showLoading) {
        setState(() => _loading = false);
      }
    }
  }

  bool _hasActiveRestore() {
    for (final row in _rows) {
      final status = (row['status']?.toString() ?? '').toLowerCase();
      if (status == 'running' || status == 'pending') {
        return true;
      }
    }
    return false;
  }

  void _syncHistoryAutoRefresh() {
    final shouldRefresh = _hasActiveRestore();
    if (!shouldRefresh) {
      _historyAutoRefreshTimer?.cancel();
      _historyAutoRefreshTimer = null;
      return;
    }
    if (_historyAutoRefreshTimer != null) {
      return;
    }

    _historyAutoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || _busy || _historyRefreshing) {
        return;
      }
      _historyRefreshing = true;
      try {
        await _loadRows(showLoading: false);
      } finally {
        _historyRefreshing = false;
      }
    });
  }

  Future<void> _createBackup() async {
    await _runBusyTask(() async {
      final selectedEtab = ref.read(etablissementProvider).selected;
      final payload = <String, dynamic>{
        'scope': _createScope,
        'include_media': _includeMedia,
        'notes': _notesController.text.trim(),
      };
      if (_createScope == 'etablissement' && selectedEtab != null) {
        payload['etablissement_id'] = selectedEtab.id;
      }

      await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).post('$base/', data: payload),
      );
      _showMessage('Sauvegarde créée avec succès.', isSuccess: true);
      await _loadRows();
    });
  }

  Future<void> _downloadBackup(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) {
      _showMessage('Backup invalide.');
      return;
    }

    await _runBusyTask(() async {
      final response = await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).get(
          '$base/$id/download/',
          options: Options(responseType: ResponseType.bytes),
        ),
      );
      final bytes = _toBytes(response.data);
      final fileName = (row['filename']?.toString().trim().isNotEmpty ?? false)
          ? row['filename'].toString().trim()
          : 'backup_$id.zip';

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer la sauvegarde',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: bytes,
      );

      if (savePath == null) {
        _showMessage('Téléchargement annulé.');
        return;
      }
      _showMessage('Fichier sauvegardé: $fileName', isSuccess: true);
    });
  }

  Future<void> _restoreFromArchive(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) {
      _showMessage('Backup invalide.');
      return;
    }

    await _runBusyTask(() async {
      await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).post('$base/$id/restore/'),
      );
      _showMessage('Restauration lancée en arrière-plan.', isSuccess: true);
      await _loadRows();
    });
  }

  Future<void> _pickRestoreFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    setState(() => _restoreFile = result.files.first);
  }

  Future<void> _uploadAndRestore() async {
    if (_restoreFile == null || _restoreFile!.bytes == null) {
      _showMessage('Sélectionnez un fichier ZIP.');
      return;
    }

    await _runBusyTask(() async {
      final selectedEtab = ref.read(etablissementProvider).selected;
      await _requestWithBackupFallback(
        (base) => ref.read(dioProvider).post(
          '$base/upload-restore/',
          data: _buildRestoreFormData(selectedEtab),
        ),
      );
      _showMessage('Archive envoyée. Restauration lancée en arrière-plan.', isSuccess: true);
      await _loadRows();
    });
  }

  FormData _buildRestoreFormData(Etablissement? selectedEtab) {
    return FormData.fromMap({
      'scope': _restoreScope,
      'notes': _restoreNotesController.text.trim(),
      if (_restoreScope == 'etablissement' && selectedEtab != null)
        'etablissement_id': selectedEtab.id,
      'file': MultipartFile.fromBytes(
        _restoreFile!.bytes!,
        filename: _restoreFile!.name,
      ),
    });
  }

  Future<Response<dynamic>> _requestWithBackupFallback(
    Future<Response<dynamic>> Function(String base) request,
  ) async {
    DioException? last404;

    for (final base in _backupBases) {
      try {
        return await request(base);
      } on DioException catch (error) {
        final statusCode = error.response?.statusCode;
        if (statusCode == 404) {
          last404 = error;
          continue;
        }
        rethrow;
      }
    }

    if (last404 != null) {
      throw Exception(
        'Endpoint backup introuvable sur l\'API active. '
        'Vérifiez que le backend production est bien déployé.',
      );
    }

    throw Exception('Aucune route backup disponible.');
  }

  Future<void> _runBusyTask(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      _showMessage('Opération impossible: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Uint8List _toBytes(dynamic data) {
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    return Uint8List.fromList(List<int>.from(data as List));
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  String _scopeLabel(String scope) {
    return scope == 'global' ? 'Globale plateforme' : 'Etablissement';
  }

  @override
  Widget build(BuildContext context) {
    final selectedEtab = ref.watch(etablissementProvider).selected;
    final user = ref.watch(authControllerProvider).value;
    final isSuperAdmin = user?.role == 'super_admin';

    if (_loading) {
      return RefreshIndicator(
        onRefresh: _loadRows,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 420,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRows,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Sauvegarde & Restauration',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selectedEtab == null
                ? 'Aucun établissement sélectionné.'
                : 'Établissement actif: ${selectedEtab.name}',
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Créer une sauvegarde',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _createScope,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      if (isSuperAdmin)
                        const DropdownMenuItem(
                          value: 'global',
                          child: Text('Sauvegarde globale plateforme'),
                        ),
                      const DropdownMenuItem(
                        value: 'etablissement',
                        child: Text('Sauvegarde de l\'établissement actif'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _createScope = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: _includeMedia,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inclure les médias'),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _includeMedia = value),
                  ),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optionnel)',
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _createBackup,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Lancer la sauvegarde'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload + restauration',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _restoreScope,
                    decoration: const InputDecoration(labelText: 'Mode restauration'),
                    items: [
                      if (isSuperAdmin)
                        const DropdownMenuItem(
                          value: 'global',
                          child: Text('Restauration globale plateforme'),
                        ),
                      const DropdownMenuItem(
                        value: 'etablissement',
                        child: Text('Restauration établissement actif'),
                      ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _restoreScope = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickRestoreFile,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Choisir ZIP'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _restoreFile?.name ?? 'Aucun fichier sélectionné',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _restoreNotesController,
                    decoration: const InputDecoration(labelText: 'Notes (optionnel)'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _busy ? null : _uploadAndRestore,
                    icon: const Icon(Icons.restore_page_outlined),
                    label: const Text('Uploader et restaurer'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Historique',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_rows.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Aucune archive disponible.'),
              ),
            )
          else
            ..._rows.map((row) {
              final statusValue = row['status']?.toString() ?? '-';
              final canDownload = (row['file_path']?.toString().isNotEmpty ?? false);
              final restoreLog = (row['restore_log']?.toString() ?? '').trim();
              final isFailed = statusValue == 'failed';
              return Card(
                child: ListTile(
                  title: Text(row['filename']?.toString().isNotEmpty == true
                      ? row['filename'].toString()
                      : 'Archive #${row['id']}'),
                  subtitle: Text(
                    isFailed && restoreLog.isNotEmpty
                        ? '${_scopeLabel(row['scope']?.toString() ?? '')} • Statut: $statusValue\nErreur: ${restoreLog.split("\n").first}'
                        : '${_scopeLabel(row['scope']?.toString() ?? '')} • Statut: $statusValue',
                  ),
                  isThreeLine: isFailed && restoreLog.isNotEmpty,
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (canDownload)
                        IconButton(
                          tooltip: 'Télécharger',
                          onPressed: _busy ? null : () => _downloadBackup(row),
                          icon: const Icon(Icons.download_outlined),
                        ),
                      IconButton(
                        tooltip: 'Restaurer',
                        onPressed: _busy ? null : () => _restoreFromArchive(row),
                        icon: const Icon(Icons.settings_backup_restore_outlined),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
