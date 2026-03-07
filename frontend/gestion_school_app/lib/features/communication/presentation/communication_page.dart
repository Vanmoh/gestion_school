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
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur chargement communication: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _post(
    String endpoint,
    Map<String, dynamic> data,
    String success,
  ) async {
    setState(() => _saving = true);
    try {
      await ref.read(dioProvider).post(endpoint, data: data);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erreur: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('Communication', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Annonces, notifications et configuration SMS.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Nouvelle annonce',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
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
                  onPressed: _saving
                      ? null
                      : () => _post('/announcements/', {
                          'title': _annTitleController.text.trim(),
                          'message': _annMessageController.text.trim(),
                          'audience': _audienceController.text.trim().isEmpty
                              ? 'all'
                              : _audienceController.text.trim(),
                        }, 'Annonce publiée'),
                  child: const Text('Publier annonce'),
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
                  'Nouvelle notification',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _notifChannel,
                  decoration: const InputDecoration(labelText: 'Canal'),
                  items: const [
                    DropdownMenuItem(value: 'push', child: Text('Push')),
                    DropdownMenuItem(value: 'email', child: Text('Email')),
                    DropdownMenuItem(value: 'sms', child: Text('SMS')),
                  ],
                  onChanged: (v) => setState(() => _notifChannel = v ?? 'push'),
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
                      (u) => DropdownMenuItem<int?>(
                        value: _asInt(u['id']),
                        child: Text(_userLabel(u)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedRecipient = v),
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
                  onPressed: _saving
                      ? null
                      : () => _post('/notifications/', {
                          'recipient': _selectedRecipient,
                          'channel': _notifChannel,
                          'title': _notifTitleController.text.trim(),
                          'message': _notifMessageController.text.trim(),
                          'is_sent': false,
                        }, 'Notification créée'),
                  child: const Text('Créer notification'),
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
                  'Configuration SMS',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
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
                  decoration: const InputDecoration(labelText: 'API Token'),
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
                  onChanged: (v) => setState(() => _smsActive = v),
                ),
                FilledButton.tonal(
                  onPressed: _saving
                      ? null
                      : () => _post('/sms-providers/', {
                          'provider_name': _smsProviderController.text.trim(),
                          'api_url': _smsUrlController.text.trim(),
                          'api_token': _smsTokenController.text.trim(),
                          'sender_id': _smsSenderController.text.trim(),
                          'is_active': _smsActive,
                        }, 'Configuration SMS enregistrée'),
                  child: const Text('Enregistrer config SMS'),
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
                  'Historique communication',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Annonces: ${_announcements.length}'),
                Text('Notifications: ${_notifications.length}'),
                Text('SMS providers: ${_smsProviders.length}'),
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

  String _userLabel(Map<String, dynamic> user) {
    final first = (user['first_name'] ?? '').toString();
    final last = (user['last_name'] ?? '').toString();
    final full = '$first $last'.trim();
    final username = (user['username'] ?? '').toString();
    final role = (user['role'] ?? '').toString();
    if (full.isNotEmpty) {
      return '$full ($role)';
    }
    return '$username ($role)';
  }
}
