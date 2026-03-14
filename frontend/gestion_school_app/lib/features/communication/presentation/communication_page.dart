import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class CommunicationPage extends ConsumerStatefulWidget {
  const CommunicationPage({super.key});

  @override
  ConsumerState<CommunicationPage> createState() => _CommunicationPageState();
}

class _CommunicationPageState extends ConsumerState<CommunicationPage> {
  final _annTitleController = TextEditingController();
  final _annMessageController = TextEditingController();
  final _audienceController = TextEditingController(text: 'all');

  final _notifTitleController = TextEditingController();
  final _notifMessageController = TextEditingController();
  String _notifChannel = 'push';
  int? _selectedRecipient;

  final _smsProviderController = TextEditingController();
  final _smsUrlController = TextEditingController();
  final _smsTokenController = TextEditingController();
  final _smsSenderController = TextEditingController();
  bool _smsActive = true;

  final _historySearchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _smsProviders = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _annTitleController.dispose();
    _annMessageController.dispose();
    _audienceController.dispose();
    _notifTitleController.dispose();
    _notifMessageController.dispose();
    _smsProviderController.dispose();
    _smsUrlController.dispose();
    _smsTokenController.dispose();
    _smsSenderController.dispose();
    _historySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/auth/users/'),
        dio.get('/announcements/'),
        dio.get('/notifications/'),
        dio.get('/sms-providers/'),
      ]);

      if (!mounted) return;

      setState(() {
        _users = _extractRows(results[0].data);
        _announcements = _extractRows(results[1].data);
        _notifications = _extractRows(results[2].data);
        _smsProviders = _extractRows(results[3].data);

        if (_selectedRecipient != null &&
            !_users.any((row) => _asInt(row['id']) == _selectedRecipient)) {
          _selectedRecipient = null;
        }
      });
    } catch (error) {
      _showMessage('Erreur chargement communication: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshCommunication() async {
    await _loadData();
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? const Color(0xFF197A43) : null,
      ),
    );
  }

  Future<bool> _post(
    String endpoint,
    Map<String, dynamic> data,
    String success,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(endpoint, data: data);
      if (!mounted) return false;
      _showMessage(success, isSuccess: true);
      await _loadData();
      return true;
    } catch (error) {
      _showMessage('Erreur: $error');
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _delete(String endpoint, String success) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).delete(endpoint);
      if (!mounted) return false;
      _showMessage(success, isSuccess: true);
      await _loadData();
      return true;
    } catch (error) {
      _showMessage('Erreur suppression: $error');
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _createAnnouncement() async {
    final title = _annTitleController.text.trim();
    final message = _annMessageController.text.trim();
    final audience = _audienceController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      _showMessage('Titre et message sont obligatoires.');
      return;
    }

    final ok = await _post('/announcements/', {
      'title': title,
      'message': message,
      'audience': audience.isEmpty ? 'all' : audience,
    }, 'Annonce publiee');

    if (ok) {
      _annTitleController.clear();
      _annMessageController.clear();
      _audienceController.text = 'all';
    }
  }

  Future<void> _createNotification() async {
    final title = _notifTitleController.text.trim();
    final message = _notifMessageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      _showMessage('Titre et message sont obligatoires.');
      return;
    }

    final ok = await _post('/notifications/', {
      'recipient': _selectedRecipient,
      'channel': _notifChannel,
      'title': title,
      'message': message,
      'is_sent': false,
    }, 'Notification creee');

    if (ok) {
      _notifTitleController.clear();
      _notifMessageController.clear();
      _selectedRecipient = null;
      _notifChannel = 'push';
      if (mounted) setState(() {});
    }
  }

  Future<void> _createSmsProvider() async {
    final provider = _smsProviderController.text.trim();
    final apiUrl = _smsUrlController.text.trim();
    final apiToken = _smsTokenController.text.trim();

    if (provider.isEmpty || apiUrl.isEmpty || apiToken.isEmpty) {
      _showMessage('Provider, API URL et API token sont obligatoires.');
      return;
    }

    final ok = await _post('/sms-providers/', {
      'provider_name': provider,
      'api_url': apiUrl,
      'api_token': apiToken,
      'sender_id': _smsSenderController.text.trim(),
      'is_active': _smsActive,
    }, 'Configuration SMS enregistree');

    if (ok) {
      _smsProviderController.clear();
      _smsUrlController.clear();
      _smsTokenController.clear();
      _smsSenderController.clear();
      _smsActive = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _confirmDelete({
    required String title,
    required String message,
    required Future<bool> Function() onDelete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB42318),
              ),
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await onDelete();
  }

  void _showDetailsDialog({
    required String title,
    required List<(String, String)> rows,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 130,
                            child: Text(
                              row.$1,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              row.$2,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
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

  List<Map<String, dynamic>> _filteredRows(
    List<Map<String, dynamic>> rows,
    List<String> Function(Map<String, dynamic> row) fields,
  ) {
    final query = _historySearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return rows;
    }

    return rows.where((row) {
      final haystack = fields(row).join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
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
        onRefresh: _refreshCommunication,
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

    final filteredAnnouncements = _filteredRows(
      _announcements,
      (row) => [
        row['title']?.toString() ?? '',
        row['message']?.toString() ?? '',
        row['audience']?.toString() ?? '',
      ],
    );
    final filteredNotifications = _filteredRows(
      _notifications,
      (row) => [
        row['title']?.toString() ?? '',
        row['message']?.toString() ?? '',
        row['channel']?.toString() ?? '',
      ],
    );
    final filteredSmsProviders = _filteredRows(
      _smsProviders,
      (row) => [
        row['provider_name']?.toString() ?? '',
        row['api_url']?.toString() ?? '',
        row['sender_id']?.toString() ?? '',
      ],
    );

    final sentNotifications = _notifications
        .where((row) => row['is_sent'] == true)
        .length;
    final activeSmsProviders = _smsProviders
        .where((row) => row['is_active'] == true)
        .length;

    final createPanel = Column(
      children: [
        _sectionCard(
          title: 'Nouvelle annonce',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _annTitleController,
                decoration: const InputDecoration(labelText: 'Titre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _annMessageController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _audienceController,
                decoration: const InputDecoration(
                  labelText: 'Audience (all, parents, teachers...)',
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _saving ? null : _createAnnouncement,
                child: const Text('Publier annonce'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Nouvelle notification',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _notifChannel,
                decoration: const InputDecoration(labelText: 'Canal'),
                items: const [
                  DropdownMenuItem(value: 'push', child: Text('Push')),
                  DropdownMenuItem(value: 'email', child: Text('Email')),
                  DropdownMenuItem(value: 'sms', child: Text('SMS')),
                ],
                onChanged: (value) {
                  setState(() => _notifChannel = value ?? 'push');
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: _selectedRecipient,
                decoration: const InputDecoration(
                  labelText: 'Destinataire (optionnel)',
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Notification globale'),
                  ),
                  ..._users.map(
                    (row) => DropdownMenuItem<int?>(
                      value: _asInt(row['id']),
                      child: Text(_userLabel(row)),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _selectedRecipient = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notifTitleController,
                decoration: const InputDecoration(labelText: 'Titre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notifMessageController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonal(
                onPressed: _saving ? null : _createNotification,
                child: const Text('Creer notification'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          title: 'Configuration SMS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _smsProviderController,
                decoration: const InputDecoration(labelText: 'Provider'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _smsUrlController,
                decoration: const InputDecoration(labelText: 'API URL'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _smsTokenController,
                decoration: const InputDecoration(labelText: 'API token'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _smsSenderController,
                decoration: const InputDecoration(labelText: 'Sender ID'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _smsActive,
                title: const Text('Actif'),
                onChanged: (value) {
                  setState(() => _smsActive = value);
                },
              ),
              FilledButton.tonal(
                onPressed: _saving ? null : _createSmsProvider,
                child: const Text('Enregistrer config SMS'),
              ),
            ],
          ),
        ),
      ],
    );

    final historyPanel = _sectionCard(
      title: 'Historique communication',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _historySearchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Rechercher dans historique',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _historySearchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _historySearchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.clear),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Annonces (${filteredAnnouncements.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (filteredAnnouncements.isEmpty)
            const Text('Aucune annonce')
          else
            Column(
              children: filteredAnnouncements
                  .map(
                    (row) => Card(
                      child: ListTile(
                        title: Text(row['title']?.toString() ?? 'Annonce'),
                        subtitle: Text(
                          '${row['audience'] ?? 'all'} • ${row['message'] ?? ''}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'view') {
                              _showDetailsDialog(
                                title: 'Annonce #${_asInt(row['id'])}',
                                rows: [
                                  ('Titre', row['title']?.toString() ?? '-'),
                                  (
                                    'Audience',
                                    row['audience']?.toString() ?? '-',
                                  ),
                                  (
                                    'Message',
                                    row['message']?.toString() ?? '-',
                                  ),
                                ],
                              );
                              return;
                            }
                            if (value == 'delete') {
                              await _confirmDelete(
                                title: 'Supprimer annonce',
                                message: 'Supprimer cette annonce ?',
                                onDelete: () => _delete(
                                  '/announcements/${_asInt(row['id'])}/',
                                  'Annonce supprimee',
                                ),
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem<String>(
                              value: 'view',
                              child: Text('Afficher'),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Supprimer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          Text(
            'Notifications (${filteredNotifications.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (filteredNotifications.isEmpty)
            const Text('Aucune notification')
          else
            Column(
              children: filteredNotifications
                  .map(
                    (row) => Card(
                      child: ListTile(
                        title: Text(row['title']?.toString() ?? 'Notification'),
                        subtitle: Text(
                          '${row['channel'] ?? '-'} • ${row['message'] ?? ''}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'view') {
                              _showDetailsDialog(
                                title: 'Notification #${_asInt(row['id'])}',
                                rows: [
                                  ('Titre', row['title']?.toString() ?? '-'),
                                  ('Canal', row['channel']?.toString() ?? '-'),
                                  (
                                    'Destinataire',
                                    row['recipient']?.toString() ?? 'Global',
                                  ),
                                  (
                                    'Message',
                                    row['message']?.toString() ?? '-',
                                  ),
                                  (
                                    'Statut',
                                    row['is_sent'] == true
                                        ? 'Envoyee'
                                        : 'En attente',
                                  ),
                                ],
                              );
                              return;
                            }
                            if (value == 'delete') {
                              await _confirmDelete(
                                title: 'Supprimer notification',
                                message: 'Supprimer cette notification ?',
                                onDelete: () => _delete(
                                  '/notifications/${_asInt(row['id'])}/',
                                  'Notification supprimee',
                                ),
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem<String>(
                              value: 'view',
                              child: Text('Afficher'),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Supprimer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          Text(
            'Providers SMS (${filteredSmsProviders.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (filteredSmsProviders.isEmpty)
            const Text('Aucune configuration SMS')
          else
            Column(
              children: filteredSmsProviders
                  .map(
                    (row) => Card(
                      child: ListTile(
                        title: Text(
                          row['provider_name']?.toString() ?? 'Provider',
                        ),
                        subtitle: Text(
                          '${row['api_url'] ?? '-'} • Sender ${row['sender_id'] ?? '-'}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'view') {
                              _showDetailsDialog(
                                title: 'Provider SMS #${_asInt(row['id'])}',
                                rows: [
                                  (
                                    'Provider',
                                    row['provider_name']?.toString() ?? '-',
                                  ),
                                  (
                                    'API URL',
                                    row['api_url']?.toString() ?? '-',
                                  ),
                                  (
                                    'Sender ID',
                                    row['sender_id']?.toString() ?? '-',
                                  ),
                                  (
                                    'Actif',
                                    row['is_active'] == true ? 'Oui' : 'Non',
                                  ),
                                ],
                              );
                              return;
                            }
                            if (value == 'delete') {
                              await _confirmDelete(
                                title: 'Supprimer provider SMS',
                                message: 'Supprimer cette configuration SMS ?',
                                onDelete: () => _delete(
                                  '/sms-providers/${_asInt(row['id'])}/',
                                  'Configuration SMS supprimee',
                                ),
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem<String>(
                              value: 'view',
                              child: Text('Afficher'),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Supprimer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: _refreshCommunication,
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
                      'Communication',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Annonces, notifications et configuration de diffusion SMS.',
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
                _metricChip('Utilisateurs', '${_users.length}'),
                _metricChip('Annonces', '${_announcements.length}'),
                _metricChip('Notifications', '${_notifications.length}'),
                _metricChip('Notifications envoyees', '$sentNotifications'),
                _metricChip('Providers SMS actifs', '$activeSmsProviders'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1120;
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: createPanel),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: historyPanel),
                  ],
                );
              }

              return Column(
                children: [
                  createPanel,
                  const SizedBox(height: 12),
                  historyPanel,
                ],
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

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _userLabel(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString().trim();
    final last = (user['last_name'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    final username = (user['username'] ?? '').toString().trim();
    final role = (user['role'] ?? '').toString().trim();
    if (full.isNotEmpty) {
      return '$full ($role)';
    }
    return '$username ($role)';
  }
}
