import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../models/etablissement.dart';
import '../../auth/presentation/auth_controller.dart';

class EtablissementsPage extends ConsumerStatefulWidget {
  const EtablissementsPage({super.key});

  @override
  ConsumerState<EtablissementsPage> createState() => _EtablissementsPageState();
}

class _EtablissementsPageState extends ConsumerState<EtablissementsPage> {
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _rows = [];
  int? _selectedId;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  Uint8List? _logoBytes;
  String? _logoFileName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final response = await ref.read(dioProvider).get('/etablissements/');
      final rows = _extractRows(response.data)
        ..sort(
          (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          ),
        );

      await _syncEtablissementProvider(rows);

      if (!mounted) return;
      setState(() {
        _rows = rows;
        if (_selectedId != null &&
            !_rows.any((row) => _asInt(row['id']) == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (error) {
      _showMessage('Erreur chargement etablissements: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncEtablissementProvider(
    List<Map<String, dynamic>> rows, {
    int? preferSelectionId,
    bool refreshAuthProfile = false,
  }) async {
    final provider = ref.read(etablissementProvider);
    final currentSelectedId = provider.selected?.id;

    final etablissements = <Etablissement>[];
    for (final row in rows) {
      try {
        etablissements.add(Etablissement.fromJson(row));
      } catch (_) {
        // Ignore malformed rows and keep best-effort sync.
      }
    }
    provider.setEtablissements(etablissements);

    final targetId = preferSelectionId ?? currentSelectedId;
    if (targetId != null) {
      for (final etab in etablissements) {
        if (etab.id == targetId) {
          await provider.selectEtablissement(etab);
          break;
        }
      }
    }

    if (refreshAuthProfile) {
      await ref.read(authControllerProvider.notifier).restoreSession();
    }
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final List<dynamic> rows;
    if (data is Map<String, dynamic> && data['results'] is List) {
      rows = data['results'] as List<dynamic>;
    } else if (data is List) {
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

  void _showMessage(String text, {bool isSuccess = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: isSuccess ? Colors.green.shade700 : null,
        ),
      );
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      _showMessage('Fichier logo invalide.');
      return;
    }

    setState(() {
      _logoBytes = bytes;
      _logoFileName = file.name;
    });
  }

  void _clearForm() {
    _nameController.clear();
    _addressController.clear();
    _phoneController.clear();
    _emailController.clear();
    _logoBytes = null;
    _logoFileName = null;
    _selectedId = null;
  }

  void _fillForm(Map<String, dynamic> row) {
    setState(() {
      _selectedId = _asInt(row['id']);
      _nameController.text = (row['name'] ?? '').toString();
      _addressController.text = (row['address'] ?? '').toString();
      _phoneController.text = (row['phone'] ?? '').toString();
      _emailController.text = (row['email'] ?? '').toString();
      _logoBytes = null;
      _logoFileName = null;
    });
  }

  Future<void> _save() async {
    final role = ref.read(authControllerProvider).value?.role;
    if (role != 'super_admin') {
      _showMessage('Acces reserve au super admin.');
      return;
    }

    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || address.isEmpty || phone.isEmpty || email.isEmpty) {
      _showMessage(
        'Tous les champs sont obligatoires: nom, adresse, telephone, email.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final accessToken = await ref.read(tokenStorageProvider).accessToken();
      if (accessToken == null || accessToken.isEmpty) {
        _showMessage('Session expiree. Reconnectez-vous puis reessayez.');
        return;
      }

      final data = FormData.fromMap({
        'name': name,
        'address': address,
        'phone': phone,
        'email': email,
        if (_logoBytes != null)
          'logo': MultipartFile.fromBytes(
            _logoBytes!,
            filename: _logoFileName ?? 'logo.png',
          ),
      });

      final options = Options(
        contentType: 'multipart/form-data',
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      int? savedId;

      if ((_selectedId ?? 0) > 0) {
        final response = await ref
            .read(dioProvider)
            .patch(
              '/etablissements/$_selectedId/',
              data: data,
              options: options,
            );
        savedId = _asInt((response.data as Map<String, dynamic>)['id']);
        _showMessage('Etablissement modifie avec succes.', isSuccess: true);
      } else {
        final response = await ref
            .read(dioProvider)
            .post('/etablissements/', data: data, options: options);
        savedId = _asInt((response.data as Map<String, dynamic>)['id']);
        _showMessage('Etablissement ajoute avec succes.', isSuccess: true);
      }

      _clearForm();
      await _loadData();
      await _syncEtablissementProvider(
        _rows,
        preferSelectionId: savedId,
        refreshAuthProfile: true,
      );
    } on DioException catch (error) {
      _showMessage(_extractApiError(error));
    } catch (error) {
      _showMessage('Erreur enregistrement etablissement: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteSelected() async {
    final id = _selectedId;
    if (id == null || id <= 0) {
      _showMessage('Selectionnez un etablissement a supprimer.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer etablissement'),
          content: const Text(
            'Confirmez-vous la suppression de cet etablissement ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirm != true) {
      return;
    }

    setState(() => _saving = true);
    try {
      final accessToken = await ref.read(tokenStorageProvider).accessToken();
      if (accessToken == null || accessToken.isEmpty) {
        _showMessage('Session expiree. Reconnectez-vous puis reessayez.');
        return;
      }

      await ref
          .read(dioProvider)
          .delete(
            '/etablissements/$id/',
            options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
          );
      _showMessage('Etablissement supprime.', isSuccess: true);
      _clearForm();
      await _loadData();
      await _syncEtablissementProvider(_rows, refreshAuthProfile: true);
    } on DioException catch (error) {
      _showMessage(_extractApiError(error));
    } catch (error) {
      _showMessage('Erreur suppression etablissement: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _extractApiError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      for (final entry in data.entries) {
        final value = entry.value;
        if (value is List && value.isNotEmpty) {
          return '${entry.key}: ${value.join(' | ')}';
        }
        if (value is String && value.trim().isNotEmpty) {
          return '${entry.key}: ${value.trim()}';
        }
      }
    }
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return 'Erreur API sur la gestion des etablissements.';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _rows
        .where((row) => _asInt(row['id']) == _selectedId)
        .toList();
    final selectedName = selected.isNotEmpty
        ? (selected.first['name'] ?? '').toString()
        : '-';

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Gestion etablissements',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Module reserve au super admin. Ajout, modification et suppression des etablissements.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Nom *'),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _addressController,
                      decoration: const InputDecoration(labelText: 'Adresse *'),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Telephone *',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email *'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickLogo,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      _logoFileName == null
                          ? 'Choisir logo'
                          : 'Logo: $_logoFileName',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      (_selectedId ?? 0) > 0 ? 'Mettre a jour' : 'Ajouter',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _clearForm,
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Vider'),
                  ),
                  OutlinedButton.icon(
                    onPressed: (_saving || (_selectedId ?? 0) <= 0)
                        ? null
                        : _deleteSelected,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Etablissement selectionne: $selectedName'),
                    const SizedBox(height: 8),
                    if (_rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucun etablissement disponible.'),
                      )
                    else
                      ..._rows.map((row) {
                        final id = _asInt(row['id']);
                        final selectedRow = id == _selectedId;
                        return ListTile(
                          selected: selectedRow,
                          leading: CircleAvatar(
                            child: Text('${id > 0 ? id : '?'}'),
                          ),
                          title: Text((row['name'] ?? '').toString()),
                          subtitle: Text(
                            '${(row['address'] ?? '').toString()} • ${(row['phone'] ?? '').toString()} • ${(row['email'] ?? '').toString()}',
                          ),
                          trailing: IconButton(
                            onPressed: _saving ? null : () => _fillForm(row),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          onTap: _saving ? null : () => _fillForm(row),
                        );
                      }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
