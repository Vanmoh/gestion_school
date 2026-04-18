import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/network/token_storage.dart';

class ChatPanel extends StatefulWidget {
  final Dio dio;
  final TokenStorage tokenStorage;
  final ValueChanged<int>? onUnreadChanged;

  const ChatPanel({
    super.key,
    required this.dio,
    required this.tokenStorage,
    this.onUnreadChanged,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  static const int _pageSize = 50;
  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const List<String> _allowedAttachmentExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'csv',
    'zip',
  ];

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _conversationSearchController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();

  bool _loading = true;
  bool _sending = false;
  bool _loadingOlderMessages = false;
  bool _hasMoreMessages = true;
  String? _sendError;
  int? _currentUserId;
  int? _selectedConversationId;
  int? _oldestMessageId;

  List<Map<String, dynamic>> _conversations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  final Map<int, bool> _presenceByUser = <int, bool>{};
  final Map<int, bool> _typingByConversation = <int, bool>{};
  final Map<int, Timer> _typingExpiryByConversation = <int, Timer>{};
  final Map<int, int> _lastReadByConversation = <int, int>{};
  final Map<int, String> _draftByConversation = <int, String>{};
  final Set<String> _seenMessageKeys = <String>{};
  int _pendingInThreadCount = 0;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _typingStopTimer;
  Timer? _presenceRefreshTimer;
  CancelToken? _activeUploadCancelToken;
  String? _activeUploadClientMessageId;
  int? _activeUploadConversationId;
  bool _wsConnected = false;
  bool _awaitingPong = false;
  int _wsReconnectAttempt = 0;
  String? _wsBaseUrl;
  String? _wsToken;

  String _messageKey(int conversationId, int messageId) => '$conversationId:$messageId';

  void _rebuildSeenMessageKeys(int conversationId) {
    _seenMessageKeys
      ..clear()
      ..addAll(
        _messages
            .map((row) => _messageKey(conversationId, _asInt(row['id'])))
            .where((key) => !key.endsWith(':0')),
      );
  }

  bool _isTransientSendError(Object error) {
    if (error is! DioException) {
      return false;
    }
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError;
  }

  bool _isCancelledError(Object error) {
    return error is DioException && error.type == DioExceptionType.cancel;
  }

  String _newClientMessageId(int conversationId) {
    final userId = _currentUserId ?? 0;
    final micros = DateTime.now().microsecondsSinceEpoch;
    return 'c${conversationId}_u${userId}_$micros';
  }

  bool _isThreadNearBottom() {
    if (!_messageScrollController.hasClients) {
      return true;
    }
    final position = _messageScrollController.position;
    final remaining = position.maxScrollExtent - position.pixels;
    return remaining <= 84;
  }

  bool _isThreadNearTop() {
    if (!_messageScrollController.hasClients) {
      return true;
    }
    return _messageScrollController.position.pixels <= 80;
  }

  void _storeCurrentDraft() {
    final conversationId = _selectedConversationId;
    if (conversationId == null) {
      return;
    }
    _draftByConversation[conversationId] = _messageController.text;
  }

  Future<void> _selectConversation(int conversationId) async {
    _storeCurrentDraft();
    final restoredDraft = _draftByConversation[conversationId] ?? '';
    if (!mounted) return;
    setState(() {
      _selectedConversationId = conversationId;
      _sendError = null;
      _pendingInThreadCount = 0;
      _messageController.value = TextEditingValue(
        text: restoredDraft,
        selection: TextSelection.collapsed(offset: restoredDraft.length),
      );
    });
    await _loadMessages(conversationId, reset: true);
  }

  @override
  void initState() {
    super.initState();
    _messageScrollController.addListener(_onMessageListScroll);
    _presenceRefreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshPresenceSnapshot(),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    _storeCurrentDraft();
    _activeUploadCancelToken?.cancel('panel_disposed');
    _typingStopTimer?.cancel();
    for (final timer in _typingExpiryByConversation.values) {
      timer.cancel();
    }
    _typingExpiryByConversation.clear();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _presenceRefreshTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    _messageScrollController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _conversationSearchController.dispose();
    super.dispose();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _asString(dynamic value) => value?.toString() ?? '';

  String _formatMessageTime(dynamic rawIso) {
    final raw = _asString(rawIso).trim();
    if (raw.isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return '';
    }
    final local = parsed.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return '$hh:$mm';
    }
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo $hh:$mm';
  }

  void _setTypingState(int conversationId, bool isTyping) {
    _typingExpiryByConversation[conversationId]?.cancel();
    if (isTyping) {
      _typingExpiryByConversation[conversationId] = Timer(
        const Duration(seconds: 4),
        () {
          if (!mounted) {
            return;
          }
          setState(() => _typingByConversation[conversationId] = false);
          _typingExpiryByConversation.remove(conversationId);
        },
      );
    } else {
      _typingExpiryByConversation.remove(conversationId);
    }
    _typingByConversation[conversationId] = isTyping;
  }

  String _extractApiError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final detail = data['detail']?.toString().trim();
        if (detail != null && detail.isNotEmpty) {
          return detail;
        }
        for (final value in data.values) {
          if (value is List && value.isNotEmpty) {
            return value.map((item) => item.toString()).join(' | ');
          }
          if (value is String && value.trim().isNotEmpty) {
            return value.trim();
          }
        }
      }
      if (data is String && data.trim().isNotEmpty) {
        return data.trim();
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return 'Erreur serveur HTTP $statusCode.';
      }
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
    }
    return error.toString();
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'director':
        return 'Directeurs';
      case 'accountant':
        return 'Comptables';
      case 'teacher':
        return 'Enseignants';
      case 'supervisor':
        return 'Surveillants';
      case 'parent':
        return 'Parents';
      case 'student':
        return 'Eleves';
      default:
        return 'Autres';
    }
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groupUsersByRole(
    List<Map<String, dynamic>> users,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final user in users) {
      final role = _asString(user['role']);
      grouped.putIfAbsent(role, () => <Map<String, dynamic>>[]).add(user);
    }

    const roleOrder = <String>[
      'super_admin',
      'director',
      'accountant',
      'teacher',
      'supervisor',
      'parent',
      'student',
      '',
    ];

    final entries = grouped.entries.toList(growable: false);
    entries.sort((a, b) {
      final ia = roleOrder.indexOf(a.key);
      final ib = roleOrder.indexOf(b.key);
      final wa = ia == -1 ? 999 : ia;
      final wb = ib == -1 ? 999 : ib;
      if (wa != wb) return wa.compareTo(wb);
      return _roleLabel(a.key).compareTo(_roleLabel(b.key));
    });
    return entries;
  }

  List<Map<String, dynamic>> _rows(dynamic payload) {
    if (payload is List) {
      return payload.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (payload is Map && payload['results'] is List) {
      return (payload['results'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  int _sumUnread(List<Map<String, dynamic>> rows) {
    return rows.fold<int>(
      0,
      (sum, row) => sum + _asInt(row['unread_count']),
    );
  }

  void _syncConversationReadState(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final conversationId = _asInt(row['id']);
      if (conversationId <= 0) {
        continue;
      }
      final otherLastRead = _asInt(row['other_last_read_message_id']);
      if (otherLastRead > 0) {
        _lastReadByConversation[conversationId] = otherLastRead;
      } else {
        _lastReadByConversation.remove(conversationId);
      }
    }
  }

  String _wsUrlFromApiBase(
    String apiBase,
    String token, {
    int? etablissementId,
  }) {
    final base = Uri.parse(apiBase.trim());
    final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';

    var path = base.path;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/api')) {
      path = path.substring(0, path.length - 4);
    }

    final wsPath = '$path/ws/chat/stream/';
    final queryParameters = <String, String>{'token': token};
    if (etablissementId != null && etablissementId > 0) {
      queryParameters['etablissement_id'] = etablissementId.toString();
    }
    final uri = Uri(
      scheme: wsScheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: wsPath,
      queryParameters: queryParameters,
    );
    return uri.toString();
  }

  Future<int?> _resolveWsEtablissementId() async {
    final values = await Future.wait<String?>(<Future<String?>>[
      widget.tokenStorage.selectedEtablissement(),
      widget.tokenStorage.cachedUser(),
    ]);

    final selectedEtablissementRaw = values[0] ?? '';
    final cachedUserRaw = values[1] ?? '';

    if (selectedEtablissementRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(selectedEtablissementRaw) as Map<String, dynamic>;
        return (decoded['id'] as num?)?.toInt();
      } catch (_) {
        // Ignore malformed cached establishment payload.
      }
    }

    if (cachedUserRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(cachedUserRaw) as Map<String, dynamic>;
        return (decoded['etablissementId'] as num?)?.toInt();
      } catch (_) {
        // Ignore malformed cached user payload.
      }
    }

    return null;
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait<String?>(<Future<String?>>[
        widget.tokenStorage.cachedUser(),
        widget.tokenStorage.accessToken(),
        widget.tokenStorage.apiBaseUrl(),
      ]);

      final rawUser = values[0] ?? '';
      final token = values[1] ?? '';
      final storedBase = values[2] ?? '';
      if (rawUser.isNotEmpty) {
        final parsed = jsonDecode(rawUser) as Map<String, dynamic>;
        _currentUserId = _asInt(parsed['id']);
      }

      final responses = await Future.wait<Response<dynamic>>(<Future<Response<dynamic>>>[
        widget.dio.get('/chat/conversations/'),
        widget.dio.get('/chat/users/'),
      ]);

      final conversations = _rows(responses[0].data);
      final users = _rows(responses[1].data);
      _syncConversationReadState(conversations);
      for (final row in users) {
        final id = _asInt(row['id']);
        _presenceByUser[id] = row['online'] == true;
      }

      _conversations = conversations;
      _users = users;
      if (_selectedConversationId == null && _conversations.isNotEmpty) {
        _selectedConversationId = _asInt(_conversations.first['id']);
      }

      widget.onUnreadChanged?.call(_sumUnread(_conversations));

      if (_selectedConversationId != null) {
        await _loadMessages(_selectedConversationId!, reset: true);
        await _refreshConversationPresence(_selectedConversationId!);
      }

      if (token.isNotEmpty) {
        final activeBase = widget.dio.options.baseUrl.trim();
        final baseUrl = activeBase.isNotEmpty ? activeBase : storedBase;
        unawaited(_connectWs(baseUrl, token));
      }

      // Refresh once after websocket connect attempt so counterpart online
      // state in conversation rows catches up quickly.
      Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        unawaited(_reloadConversationsOnly());
      });
    } catch (_) {
      // Keep panel usable with best effort data load.
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom(immediate: true);
      }
    }
  }

  Future<void> _loadMessages(
    int conversationId, {
    bool reset = false,
    bool appendOlder = false,
  }) async {
    if (appendOlder && (_loadingOlderMessages || !_hasMoreMessages || _oldestMessageId == null)) {
      return;
    }

    if (appendOlder) {
      if (!mounted) return;
      setState(() => _loadingOlderMessages = true);
    }

    try {
      final beforeId = appendOlder ? _oldestMessageId : null;
      final resp = await widget.dio.get(
        '/chat/conversations/$conversationId/messages/',
        queryParameters: <String, dynamic>{
          'page_size': _pageSize,
          if (beforeId != null) 'before_id': beforeId,
        },
      );
      final rows = _rows(resp.data);

      if (!mounted) return;

      if (appendOlder) {
        final beforeExtent = _messageScrollController.hasClients
            ? _messageScrollController.position.maxScrollExtent
            : 0.0;
        setState(() {
          _messages = <Map<String, dynamic>>[...rows, ..._messages];
          _hasMoreMessages = rows.length >= _pageSize;
          _oldestMessageId = _messages.isNotEmpty
              ? _asInt(_messages.first['id'])
              : null;
          _loadingOlderMessages = false;
        });
        _rebuildSeenMessageKeys(conversationId);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_messageScrollController.hasClients) {
            return;
          }
          final afterExtent = _messageScrollController.position.maxScrollExtent;
          final delta = afterExtent - beforeExtent;
          final nextOffset = _messageScrollController.offset + delta;
          _messageScrollController.jumpTo(nextOffset);
        });
      } else {
        setState(() {
          _messages = rows;
          _hasMoreMessages = rows.length >= _pageSize;
          _oldestMessageId = rows.isNotEmpty ? _asInt(rows.first['id']) : null;
          _pendingInThreadCount = 0;
        });
        _rebuildSeenMessageKeys(conversationId);
        await _markRead(conversationId);
        _scrollToBottom(immediate: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (!appendOlder) {
          _messages = <Map<String, dynamic>>[];
          _hasMoreMessages = false;
          _oldestMessageId = null;
        }
      });
    } finally {
      if (mounted && appendOlder) {
        setState(() => _loadingOlderMessages = false);
      }
    }
  }

  void _onMessageListScroll() {
    if (!_messageScrollController.hasClients || _selectedConversationId == null) {
      return;
    }
    if (_isThreadNearTop()) {
      _loadMessages(_selectedConversationId!, appendOlder: true);
    }
  }

  Future<void> _reloadConversationsOnly() async {
    try {
      final resp = await widget.dio.get('/chat/conversations/');
      final rows = _rows(resp.data);
      _syncConversationReadState(rows);
      if (!mounted) return;
      setState(() {
        _conversations = rows;
        final selectedExists = _conversations.any(
          (row) => _asInt(row['id']) == _selectedConversationId,
        );
        if (!selectedExists) {
          _selectedConversationId = _conversations.isNotEmpty
              ? _asInt(_conversations.first['id'])
              : null;
          _messages = <Map<String, dynamic>>[];
          _oldestMessageId = null;
          _hasMoreMessages = true;
          _sendError = null;
        }
      });
      widget.onUnreadChanged?.call(_sumUnread(_conversations));

      if (_selectedConversationId != null && _messages.isEmpty) {
        await _loadMessages(_selectedConversationId!, reset: true);
      }
    } catch (_) {
      // Best effort refresh.
    }
  }

  Future<void> _refreshPresenceSnapshot() async {
    final conversationId = _selectedConversationId;
    if (conversationId != null) {
      await _refreshConversationPresence(conversationId);
    }

    try {
      final resp = await widget.dio.get('/chat/users/');
      final rows = _rows(resp.data);
      if (!mounted) return;
      setState(() {
        _users = rows;
        for (final user in rows) {
          _presenceByUser[_asInt(user['id'])] = user['online'] == true;
        }
      });
    } catch (_) {
      // Keep chat usable if periodic presence refresh fails.
    }
  }

  Future<void> _refreshConversationPresence(int conversationId) async {
    try {
      final resp = await widget.dio.get('/chat/conversations/$conversationId/presence/');
      final rows = _rows(resp.data);
      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          final userId = _asInt(row['user_id']);
          if (userId > 0) {
            _presenceByUser[userId] = row['online'] == true;
          }
        }
      });
    } catch (_) {
      // Keep chat usable if targeted presence refresh fails.
    }
  }

  Future<void> _leaveGroupConversation(Map<String, dynamic> conversation) async {
    final conversationId = _asInt(conversation['id']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter le groupe'),
        content: const Text('Voulez-vous vraiment quitter ce groupe ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.dio.post('/chat/conversations/$conversationId/group/leave/');
      if (!mounted) return;
      await _reloadConversationsOnly();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de quitter le groupe.')),
      );
    }
  }

  Future<void> _deleteGroupConversation(Map<String, dynamic> conversation) async {
    final conversationId = _asInt(conversation['id']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le groupe'),
        content: const Text('Cette action est irreversible. Supprimer ce groupe ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.dio.delete('/chat/conversations/$conversationId/group/');
      if (!mounted) return;
      await _reloadConversationsOnly();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression du groupe impossible.')),
      );
    }
  }

  Future<void> _closeConversation(Map<String, dynamic> conversation) async {
    final conversationId = _asInt(conversation['id']);
    final isGroup = conversation['is_group'] == true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isGroup ? 'Fermer le groupe' : 'Fermer la conversation'),
        content: Text(
          isGroup
              ? 'Ce groupe sera retire de votre liste. Continuer ?'
              : 'Cette conversation sera retiree de votre liste. Continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await widget.dio.post('/chat/conversations/$conversationId/close/');
      if (!mounted) return;
      await _reloadConversationsOnly();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isGroup ? 'Groupe ferme avec succes.' : 'Conversation fermee avec succes.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de fermer la conversation.')),
      );
    }
  }

  Future<void> _markRead(int conversationId) async {
    try {
      final response = await widget.dio.post(
        '/chat/conversations/$conversationId/mark-read/',
        data: <String, dynamic>{},
      );
      final map = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      _channel?.sink.add(jsonEncode(<String, dynamic>{
        'action': 'mark_read',
        'conversation_id': conversationId,
      }));
    } catch (_) {
      // Non-blocking.
    }

    if (!mounted) return;
    setState(() {
      _conversations = _conversations.map((row) {
        if (_asInt(row['id']) != conversationId) return row;
        final next = Map<String, dynamic>.from(row);
        next['unread_count'] = 0;
        return next;
      }).toList(growable: false);
    });
    widget.onUnreadChanged?.call(_sumUnread(_conversations));
  }

  Future<void> _connectWs(String baseUrl, String token) async {
    _wsBaseUrl = baseUrl;
    _wsToken = token;
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();

    final etablissementId = await _resolveWsEtablissementId();
    final wsUrl = _wsUrlFromApiBase(
      baseUrl,
      token,
      etablissementId: etablissementId,
    );
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _channelSub = _channel!.stream.listen(
      _handleWsEvent,
      onError: (_) {
        _setWsDisconnected();
        _scheduleReconnect();
      },
      onDone: () {
        _setWsDisconnected();
        _scheduleReconnect();
      },
    );
    _setWsConnected();
    _startHeartbeat();
  }

  void _setWsConnected() {
    _awaitingPong = false;
    _wsReconnectAttempt = 0;
    if (!mounted) return;
    setState(() => _wsConnected = true);
    unawaited(_reloadConversationsOnly());
    final conversationId = _selectedConversationId;
    if (conversationId != null) {
      unawaited(_loadMessages(conversationId, reset: true));
    }
  }

  void _setWsDisconnected() {
    _heartbeatTimer?.cancel();
    if (!mounted) return;
    setState(() => _wsConnected = false);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (!_wsConnected) {
        return;
      }
      if (_awaitingPong) {
        _channel?.sink.close();
        _setWsDisconnected();
        _scheduleReconnect();
        return;
      }
      _awaitingPong = true;
      _channel?.sink.add(jsonEncode(<String, dynamic>{'action': 'ping'}));
    });
  }

  void _scheduleReconnect() {
    if (!mounted || _reconnectTimer != null) {
      return;
    }
    final base = _wsBaseUrl;
    final token = _wsToken;
    if (base == null || token == null || token.isEmpty) {
      return;
    }
    final seconds = _backoffSeconds(_wsReconnectAttempt);
    _wsReconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(_connectWs(base, token));
    });
  }

  int _backoffSeconds(int attempt) {
    final value = 1 << (attempt.clamp(0, 5));
    if (value > 30) {
      return 30;
    }
    return value;
  }

  void _onInputChanged(String value) {
    if (!_wsConnected || _selectedConversationId == null) {
      return;
    }

    _channel?.sink.add(jsonEncode(<String, dynamic>{
      'action': 'typing',
      'conversation_id': _selectedConversationId,
      'is_typing': value.trim().isNotEmpty,
    }));

    _typingStopTimer?.cancel();
    if (value.trim().isNotEmpty) {
      _typingStopTimer = Timer(const Duration(milliseconds: 1200), () {
        _channel?.sink.add(jsonEncode(<String, dynamic>{
          'action': 'typing',
          'conversation_id': _selectedConversationId,
          'is_typing': false,
        }));
      });
    }
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messageScrollController.hasClients) {
        return;
      }
      final target = _messageScrollController.position.maxScrollExtent;
      if (immediate) {
        _messageScrollController.jumpTo(target);
      } else {
        _messageScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleWsEvent(dynamic payload) {
    try {
      final data = jsonDecode(payload.toString()) as Map<String, dynamic>;
      final event = _asString(data['event']);

      if (event == 'connected') {
        _setWsConnected();
        if (_selectedConversationId != null) {
          unawaited(_refreshConversationPresence(_selectedConversationId!));
        }
        return;
      }

      if (event == 'pong') {
        _awaitingPong = false;
        return;
      }

      if (event == 'presence') {
        final userId = _asInt(data['user_id']);
        final online = data['online'] == true;
        if (mounted) {
          setState(() => _presenceByUser[userId] = online);
        }
        return;
      }

      if (event == 'typing') {
        final conversationId = _asInt(data['conversation_id']);
        final userId = _asInt(data['user_id']);
        if (_currentUserId != null && userId == _currentUserId) {
          return;
        }
        final isTyping = data['is_typing'] == true;
        if (mounted) {
          setState(() {
            _setTypingState(conversationId, isTyping);
            if (userId > 0) {
              _presenceByUser[userId] = true;
            }
          });
        }
        return;
      }

      if (event == 'read_receipt') {
        final conversationId = _asInt(data['conversation_id']);
        final userId = _asInt(data['user_id']);
        final lastRead = _asInt(data['last_read_message_id']);
        if (conversationId > 0 && lastRead > 0) {
          if (mounted) {
            setState(() {
              _lastReadByConversation[conversationId] = lastRead;
              if (userId > 0) {
                _presenceByUser[userId] = true;
              }
            });
          }
        }
        return;
      }

      if (event == 'message') {
        final conversationId = _asInt(data['conversation_id']);
        final senderId = _asInt(data['sender_id']);
        final messageId = _asInt(data['message_id']);
        if (conversationId <= 0 || messageId <= 0) {
          return;
        }
        final dedupeKey = _messageKey(conversationId, messageId);
        if (_seenMessageKeys.contains(dedupeKey)) {
          return;
        }
        final mine = _currentUserId != null && senderId == _currentUserId;
        final shouldAutoScroll = mine || _selectedConversationId != conversationId || _isThreadNearBottom();
        final existedBefore = _conversations.any(
          (row) => _asInt(row['id']) == conversationId,
        );

        final message = <String, dynamic>{
          'id': messageId,
          'conversation': conversationId,
          'sender': senderId,
          'sender_name': _asString(data['sender_name']),
          'message_type': _asString(data['message_type']),
          'content': _asString(data['content']),
          'created_at': _asString(data['created_at']),
          'client_message_id': _asString(data['client_message_id']),
          'attachment_url': _asString(data['attachment_url']),
          'attachment_name': _asString(data['attachment_name']),
          'attachment_size': _asInt(data['attachment_size']),
          'attachment_mime_type': _asString(data['attachment_mime_type']),
        };

        if (!mounted) return;
        setState(() {
          if (senderId > 0) {
            _presenceByUser[senderId] = true;
          }
          if (_selectedConversationId == conversationId) {
            _messages = <Map<String, dynamic>>[..._messages, message];
            _oldestMessageId = _messages.isNotEmpty ? _asInt(_messages.first['id']) : null;
            _seenMessageKeys.add(dedupeKey);
            if (!mine && !shouldAutoScroll) {
              _pendingInThreadCount += 1;
            }
          }

          _conversations = _conversations.map((row) {
            if (_asInt(row['id']) != conversationId) return row;
            final next = Map<String, dynamic>.from(row);
            next['last_message'] = message;
            final unread = _asInt(next['unread_count']);
            if (!mine && _selectedConversationId != conversationId) {
              next['unread_count'] = unread + 1;
            } else if (_selectedConversationId == conversationId) {
              next['unread_count'] = 0;
            }
            return next;
          }).toList(growable: false);

          _conversations.sort((a, b) {
            final aid = _asInt(a['id']);
            final bid = _asInt(b['id']);
            if (aid == conversationId) return -1;
            if (bid == conversationId) return 1;
            return 0;
          });
        });

        widget.onUnreadChanged?.call(_sumUnread(_conversations));
        if (_selectedConversationId == conversationId && shouldAutoScroll) {
          if (mounted) {
            setState(() => _pendingInThreadCount = 0);
          }
          _scrollToBottom();
        }
        if (!mine && _selectedConversationId != conversationId && mounted) {
          final senderName = _asString(data['sender_name']).trim();
          final senderLabel = senderName.isNotEmpty ? senderName : 'Nouveau message';
          final contentPreview = _asString(data['content']).trim();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 2),
                content: Text(
                  contentPreview.isEmpty
                      ? senderLabel
                      : '$senderLabel: $contentPreview',
                ),
              ),
            );
        }
        if (!existedBefore) {
          _reloadConversationsOnly();
        }
        if (!mine && _selectedConversationId == conversationId) {
          _markRead(conversationId);
        }
      }
    } catch (_) {
      // Ignore malformed payload.
    }
  }

  Future<void> _openDirectConversation(Map<String, dynamic> user) async {
    final userId = _asInt(user['id']);
    try {
      final resp = await widget.dio.post(
        '/chat/conversations/direct/',
        data: <String, dynamic>{'user_id': userId},
      );
      final conversation = Map<String, dynamic>.from(resp.data as Map);
      final cid = _asInt(conversation['id']);

      if (!mounted) return;
      _storeCurrentDraft();
      setState(() {
        final exists = _conversations.any((row) => _asInt(row['id']) == cid);
        if (!exists) {
          _conversations = <Map<String, dynamic>>[conversation, ..._conversations];
        }
        _selectedConversationId = cid;
        _sendError = null;
        _pendingInThreadCount = 0;
        final restoredDraft = _draftByConversation[cid] ?? '';
        _messageController.value = TextEditingValue(
          text: restoredDraft,
          selection: TextSelection.collapsed(offset: restoredDraft.length),
        );
      });
      await _loadMessages(cid, reset: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de demarrer la conversation.')),
      );
    }
  }

  Future<void> _sendMessage() async {
    final conversationId = _selectedConversationId;
    final draft = _messageController.text;
    final content = draft.trim();
    if (conversationId == null || content.isEmpty || _sending) {
      return;
    }

    final clientMessageId = _newClientMessageId(conversationId);
    final localMessageId = -DateTime.now().microsecondsSinceEpoch;
    final localMessage = <String, dynamic>{
      'id': localMessageId,
      'conversation': conversationId,
      'sender': _currentUserId,
      'sender_name': 'Moi',
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'client_message_id': clientMessageId,
      'is_local_pending': true,
    };

    setState(() {
      _sending = true;
      _sendError = null;
      _messages = <Map<String, dynamic>>[..._messages, localMessage];
      _conversations = _conversations.map((row) {
        if (_asInt(row['id']) != conversationId) return row;
        final next = Map<String, dynamic>.from(row);
        next['last_message'] = localMessage;
        next['unread_count'] = 0;
        return next;
      }).toList(growable: false);
    });
    _typingStopTimer?.cancel();
    _onInputChanged('');
    _scrollToBottom();

    try {
      Response<dynamic> resp;
      try {
        resp = await widget.dio.post(
          '/chat/conversations/$conversationId/send/',
          data: <String, dynamic>{
            'content': content,
            'client_message_id': clientMessageId,
          },
        );
      } catch (error) {
        if (_isTransientSendError(error)) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
          resp = await widget.dio.post(
            '/chat/conversations/$conversationId/send/',
            data: <String, dynamic>{
              'content': content,
              'client_message_id': clientMessageId,
            },
          );
        } else {
          rethrow;
        }
      }

      final msg = Map<String, dynamic>.from(resp.data as Map);
      final msgId = _asInt(msg['id']);
      if (!mounted) return;
      setState(() {
        _draftByConversation[conversationId] = '';
        _messageController.clear();
        final dedupeKey = _messageKey(conversationId, msgId);
        var replacedPending = false;
        _messages = _messages.map((row) {
          if (_asString(row['client_message_id']) == clientMessageId) {
            replacedPending = true;
            return msg;
          }
          return row;
        }).toList(growable: false);

        if (!replacedPending && msgId > 0 && !_seenMessageKeys.contains(dedupeKey)) {
          _messages = <Map<String, dynamic>>[..._messages, msg];
        }
        if (msgId > 0) {
          _seenMessageKeys.add(dedupeKey);
        }
        _oldestMessageId = _messages.isNotEmpty ? _asInt(_messages.first['id']) : null;
        _pendingInThreadCount = 0;

        _conversations = _conversations.map((row) {
          if (_asInt(row['id']) != conversationId) return row;
          final next = Map<String, dynamic>.from(row);
          next['last_message'] = msg;
          next['unread_count'] = 0;
          return next;
        }).toList(growable: false);

        _conversations.sort((a, b) {
          final aid = _asInt(a['id']);
          final bid = _asInt(b['id']);
          if (aid == conversationId) return -1;
          if (bid == conversationId) return 1;
          return 0;
        });
        _sendError = null;
      });
      widget.onUnreadChanged?.call(_sumUnread(_conversations));
      _scrollToBottom();
      unawaited(_loadMessages(conversationId, reset: true));
    } catch (error) {
      if (!mounted) return;
      final message = _extractApiError(error);
      setState(() {
        final cleanedMessages = _messages
            .where((row) => _asString(row['client_message_id']) != clientMessageId)
            .toList(growable: false);
        _messages = cleanedMessages;
        final fallbackLast = cleanedMessages.isNotEmpty ? cleanedMessages.last : null;
        _conversations = _conversations.map((row) {
          if (_asInt(row['id']) != conversationId) return row;
          final next = Map<String, dynamic>.from(row);
          if (fallbackLast != null) {
            next['last_message'] = fallbackLast;
          }
          return next;
        }).toList(growable: false);
        _sendError = message;
        _messageController.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Echec envoi du message: $message')),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  String _conversationTitle(Map<String, dynamic> row) {
    final counterpart = row['counterpart'];
    if (counterpart is Map) {
      final name = _asString(counterpart['full_name']).trim();
      if (name.isNotEmpty) return name;
      return _asString(counterpart['username']);
    }
    final title = _asString(row['title']).trim();
    if (title.isNotEmpty) return title;
    return 'Conversation #${_asInt(row['id'])}';
  }

  String _conversationPreview(Map<String, dynamic> row) {
    final lastMessage = row['last_message'];
    if (lastMessage is! Map) {
      return '';
    }
    final content = _asString(lastMessage['content']).trim();
    final attachmentName = _asString(lastMessage['attachment_name']).trim();
    final messageType = _asString(lastMessage['message_type']).trim();
    if (attachmentName.isNotEmpty || messageType == 'file') {
      if (content.isNotEmpty) {
        return 'Fichier: $attachmentName - $content';
      }
      return attachmentName.isNotEmpty ? 'Fichier: $attachmentName' : 'Piece jointe';
    }
    return content;
  }

  bool _conversationOnline(Map<String, dynamic> row) {
    final counterpart = row['counterpart'];
    if (counterpart is! Map) return false;
    final uid = _asInt(counterpart['id']);
    return _presenceByUser[uid] ?? (counterpart['online'] == true);
  }

  String _senderLabel(Map<String, dynamic> message) {
    final senderId = _asInt(message['sender'] ?? message['sender_id']);
    final mine = _currentUserId != null && senderId == _currentUserId;
    return mine ? 'Moi' : _asString(message['sender_name']);
  }

  String _outgoingStatusLabel(Map<String, dynamic> message, int lastReadMessageId) {
    if (message['upload_failed'] == true) {
      return 'Echec';
    }
    if (message['is_local_pending'] == true) {
      final progress = _asInt(message['upload_progress']);
      if (progress > 0 && progress < 100) {
        return 'Envoi... $progress%';
      }
      return 'Envoi...';
    }
    final messageId = _asInt(message['id']);
    if (messageId > 0 && lastReadMessageId >= messageId) {
      return 'Lu';
    }
    return 'Recu';
  }

  void _updatePendingMessageProgress(String clientMessageId, int progress) {
    if (!mounted) {
      return;
    }
    final bounded = progress.clamp(0, 100);
    setState(() {
      _messages = _messages.map((row) {
        if (_asString(row['client_message_id']) != clientMessageId) {
          return row;
        }
        final next = Map<String, dynamic>.from(row);
        next['upload_progress'] = bounded;
        return next;
      }).toList(growable: false);

      _conversations = _conversations.map((row) {
        if (_asInt(row['id']) != _selectedConversationId) {
          return row;
        }
        final lastMessage = row['last_message'];
        if (lastMessage is! Map || _asString(lastMessage['client_message_id']) != clientMessageId) {
          return row;
        }
        final next = Map<String, dynamic>.from(row);
        next['last_message'] = <String, dynamic>{
          ...Map<String, dynamic>.from(lastMessage),
          'upload_progress': bounded,
        };
        return next;
      }).toList(growable: false);
    });
  }

  void _removePendingUploadMessage(String clientMessageId, int conversationId) {
    final cleanedMessages = _messages
        .where((row) => _asString(row['client_message_id']) != clientMessageId)
        .toList(growable: false);
    _messages = cleanedMessages;
    final fallbackLast = cleanedMessages.isNotEmpty ? cleanedMessages.last : null;
    _conversations = _conversations.map((row) {
      if (_asInt(row['id']) != conversationId) return row;
      final next = Map<String, dynamic>.from(row);
      if (fallbackLast != null) {
        next['last_message'] = fallbackLast;
      }
      return next;
    }).toList(growable: false);
  }

  void _cancelActiveUpload() {
    final token = _activeUploadCancelToken;
    if (token == null || token.isCancelled) {
      return;
    }
    token.cancel('user_cancelled_upload');
  }

  void _markUploadMessageFailed(String clientMessageId, int conversationId, String errorMessage) {
    _messages = _messages.map((row) {
      if (_asString(row['client_message_id']) != clientMessageId) {
        return row;
      }
      final next = Map<String, dynamic>.from(row);
      next['is_local_pending'] = false;
      next['upload_failed'] = true;
      next['upload_progress'] = 0;
      next['upload_error'] = errorMessage;
      return next;
    }).toList(growable: false);

    _conversations = _conversations.map((row) {
      if (_asInt(row['id']) != conversationId) return row;
      final lastMessage = row['last_message'];
      if (lastMessage is! Map || _asString(lastMessage['client_message_id']) != clientMessageId) {
        return row;
      }
      final next = Map<String, dynamic>.from(row);
      next['last_message'] = <String, dynamic>{
        ...Map<String, dynamic>.from(lastMessage),
        'is_local_pending': false,
        'upload_failed': true,
        'upload_progress': 0,
        'upload_error': errorMessage,
      };
      return next;
    }).toList(growable: false);
  }

  Future<void> _retryFailedFileUpload(Map<String, dynamic> message) async {
    final conversationId = _selectedConversationId;
    final clientMessageId = _asString(message['client_message_id']).trim();
    final attachmentName = _asString(message['attachment_name']).trim();
    final attachmentBytes = message['attachment_bytes'];
    if (conversationId == null ||
        clientMessageId.isEmpty ||
        attachmentName.isEmpty ||
        attachmentBytes is! Uint8List ||
        attachmentBytes.isEmpty ||
        _sending) {
      return;
    }

    await _uploadAttachment(
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      attachmentName: attachmentName,
      attachmentSize: _asInt(message['attachment_size']),
      content: _asString(message['content']).trim(),
      bytes: attachmentBytes,
      reuseExistingPendingMessage: true,
      restoreComposerOnFailure: true,
      draftOnFailure: _messageController.text,
    );
  }

  Future<void> _showImagePreview(Map<String, dynamic> message) async {
    final attachmentBytes = message['attachment_bytes'];
    final attachmentUrl = _asString(message['attachment_url']).trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        Widget imageChild;
        if (attachmentBytes is Uint8List && attachmentBytes.isNotEmpty) {
          imageChild = Image.memory(attachmentBytes, fit: BoxFit.contain);
        } else if (attachmentUrl.isNotEmpty) {
          imageChild = Image.network(
            attachmentUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined, size: 48),
            ),
          );
        } else {
          imageChild = const Center(child: Icon(Icons.image_outlined, size: 48));
        }

        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: Container(
            width: 900,
            height: 700,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _asString(message['attachment_name']).trim().isNotEmpty
                            ? _asString(message['attachment_name']).trim()
                            : 'Image',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Telecharger',
                      onPressed: message['is_local_pending'] == true
                          ? null
                          : () => _downloadAttachment(message),
                      icon: const Icon(Icons.download_outlined),
                    ),
                    IconButton(
                      tooltip: 'Fermer',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Center(child: imageChild),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Uint8List> _loadAttachmentBytes(Map<String, dynamic> message) async {
    final attachmentBytes = message['attachment_bytes'];
    if (attachmentBytes is Uint8List && attachmentBytes.isNotEmpty) {
      return attachmentBytes;
    }

    final messageId = _asInt(message['id']);
    if (messageId <= 0) {
      throw Exception('Piece jointe indisponible.');
    }

    final response = await widget.dio.get(
      '/chat/messages/$messageId/download/',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data is Uint8List) {
      return data;
    }
    if (data is List<int>) {
      return Uint8List.fromList(data);
    }
    return Uint8List.fromList(List<int>.from(data as List));
  }

  Future<void> _showPdfPreview(Map<String, dynamic> message) async {
    try {
      final bytes = await _loadAttachmentBytes(message);
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            insetPadding: const EdgeInsets.all(18),
            child: SizedBox(
              width: 960,
              height: 760,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _asString(message['attachment_name']).trim().isNotEmpty
                                ? _asString(message['attachment_name']).trim()
                                : 'PDF',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Telecharger',
                          onPressed: message['is_local_pending'] == true
                              ? null
                              : () => _downloadAttachment(message),
                          icon: const Icon(Icons.download_outlined),
                        ),
                        IconButton(
                          tooltip: 'Fermer',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: PdfPreview(
                      build: (_) async => bytes,
                      canChangePageFormat: false,
                      canChangeOrientation: false,
                      allowPrinting: false,
                      allowSharing: false,
                      useActions: false,
                      loadingWidget: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Apercu PDF impossible: ${_extractApiError(error)}')),
      );
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) {
      return '0 o';
    }
    const units = <String>['o', 'Ko', 'Mo', 'Go'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    final precision = size >= 10 || unitIndex == 0 ? 0 : 1;
    return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  bool _messageHasAttachment(Map<String, dynamic> message) {
    return _asString(message['message_type']) == 'file' ||
        _asString(message['attachment_name']).trim().isNotEmpty ||
        _asString(message['attachment_url']).trim().isNotEmpty;
  }

  bool _isImageAttachment(Map<String, dynamic> message) {
    final mime = _asString(message['attachment_mime_type']).trim().toLowerCase();
    if (mime.startsWith('image/')) {
      return true;
    }
    final name = _asString(message['attachment_name']).trim().toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif');
  }

  bool _isPdfAttachment(Map<String, dynamic> message) {
    final mime = _asString(message['attachment_mime_type']).trim().toLowerCase();
    if (mime.contains('pdf')) {
      return true;
    }
    final name = _asString(message['attachment_name']).trim().toLowerCase();
    return name.endsWith('.pdf');
  }

  bool _isAttachmentOnlyMessage(Map<String, dynamic> message) {
    return _messageHasAttachment(message) && _asString(message['content']).trim().isEmpty;
  }

  bool _shouldGroupAttachmentMessages(
    Map<String, dynamic> current,
    Map<String, dynamic>? other,
  ) {
    if (other == null) {
      return false;
    }
    final currentSender = _asInt(current['sender'] ?? current['sender_id']);
    final otherSender = _asInt(other['sender'] ?? other['sender_id']);
    if (currentSender <= 0 || currentSender != otherSender) {
      return false;
    }
    return _isAttachmentOnlyMessage(current) && _isAttachmentOnlyMessage(other);
  }

  BorderRadius _messageBubbleRadius({
    required bool mine,
    required bool groupedWithPrevious,
    required bool groupedWithNext,
  }) {
    const large = Radius.circular(12);
    const small = Radius.circular(5);
    if (mine) {
      return BorderRadius.only(
        topLeft: large,
        topRight: groupedWithPrevious ? small : large,
        bottomLeft: large,
        bottomRight: groupedWithNext ? small : large,
      );
    }
    return BorderRadius.only(
      topLeft: groupedWithPrevious ? small : large,
      topRight: large,
      bottomLeft: groupedWithNext ? small : large,
      bottomRight: large,
    );
  }

  Widget _attachmentIcon(Map<String, dynamic> message) {
    if (_isImageAttachment(message)) {
      return const Icon(Icons.image_outlined);
    }
    final mime = _asString(message['attachment_mime_type']).trim().toLowerCase();
    if (mime.contains('pdf')) {
      return const Icon(Icons.picture_as_pdf_outlined);
    }
    if (mime.contains('sheet') || mime.contains('excel') || mime.contains('csv')) {
      return const Icon(Icons.table_chart_outlined);
    }
    if (mime.contains('word') || mime.contains('document')) {
      return const Icon(Icons.description_outlined);
    }
    if (mime.contains('presentation') || mime.contains('powerpoint')) {
      return const Icon(Icons.slideshow_outlined);
    }
    if (mime.contains('zip')) {
      return const Icon(Icons.folder_zip_outlined);
    }
    return const Icon(Icons.attach_file_outlined);
  }

  Future<MultipartFile?> _buildMultipartFile({
    String? path,
    Uint8List? bytes,
    String? fileName,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      return MultipartFile.fromBytes(
        bytes,
        filename: (fileName != null && fileName.trim().isNotEmpty)
            ? fileName.trim()
            : 'piece_jointe_${DateTime.now().millisecondsSinceEpoch}',
      );
    }

    final normalizedPath = path?.trim() ?? '';
    if (normalizedPath.isEmpty) {
      return null;
    }
    if (kIsWeb) {
      throw Exception('Upload web impossible: le fichier doit etre disponible en memoire.');
    }
    return MultipartFile.fromFile(
      normalizedPath,
      filename: (fileName != null && fileName.trim().isNotEmpty)
          ? fileName.trim()
          : 'piece_jointe_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  Future<void> _downloadAttachment(Map<String, dynamic> message) async {
    try {
      final messageId = _asInt(message['id']);
      if (messageId <= 0) {
        return;
      }
      final bytes = await _loadAttachmentBytes(message);
      final fileName = _asString(message['attachment_name']).trim().isNotEmpty
          ? _asString(message['attachment_name']).trim()
          : 'piece_jointe_$messageId';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Enregistrer le fichier',
        fileName: fileName,
        bytes: bytes,
      );
      if (savePath == null && !kIsWeb) {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fichier telecharge: $fileName')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Telechargement impossible: ${_extractApiError(error)}')),
      );
    }
  }

  Future<void> _openAttachment(Map<String, dynamic> message) async {
    if (_isImageAttachment(message)) {
      await _showImagePreview(message);
      return;
    }
    if (_isPdfAttachment(message)) {
      await _showPdfPreview(message);
      return;
    }
    await _downloadAttachment(message);
  }

  List<Map<String, dynamic>> _attachmentRunForMessageIndex(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _messages.length) {
      return const <Map<String, dynamic>>[];
    }
    final current = _messages[messageIndex];
    if (!_isAttachmentOnlyMessage(current)) {
      return const <Map<String, dynamic>>[];
    }
    final senderId = _asInt(current['sender'] ?? current['sender_id']);
    if (senderId <= 0) {
      return const <Map<String, dynamic>>[];
    }

    var start = messageIndex;
    while (start > 0) {
      final prev = _messages[start - 1];
      final prevSender = _asInt(prev['sender'] ?? prev['sender_id']);
      if (prevSender != senderId || !_isAttachmentOnlyMessage(prev)) {
        break;
      }
      start -= 1;
    }

    var end = messageIndex;
    while (end + 1 < _messages.length) {
      final next = _messages[end + 1];
      final nextSender = _asInt(next['sender'] ?? next['sender_id']);
      if (nextSender != senderId || !_isAttachmentOnlyMessage(next)) {
        break;
      }
      end += 1;
    }

    return _messages.sublist(start, end + 1);
  }

  bool _isRetriableFailedAttachment(Map<String, dynamic> message) {
    if (message['upload_failed'] != true) {
      return false;
    }
    final attachmentBytes = message['attachment_bytes'];
    if (attachmentBytes is! Uint8List || attachmentBytes.isEmpty) {
      return false;
    }
    return _asString(message['client_message_id']).trim().isNotEmpty &&
        _asString(message['attachment_name']).trim().isNotEmpty;
  }

  Future<void> _retryFailedAttachmentBatchFrom(int messageIndex) async {
    if (_sending) {
      return;
    }
    final conversationId = _selectedConversationId;
    if (conversationId == null) {
      return;
    }

    final run = _attachmentRunForMessageIndex(messageIndex);
    final failedMessages = run.where(_isRetriableFailedAttachment).toList(growable: false);
    if (failedMessages.length < 2) {
      return;
    }

    if (mounted) {
      setState(() {
        _sending = true;
        _sendError = null;
      });
    }

    try {
      for (final message in failedMessages) {
        if (!mounted || _selectedConversationId != conversationId) {
          break;
        }
        final keepGoing = await _uploadAttachment(
          conversationId: conversationId,
          clientMessageId: _asString(message['client_message_id']).trim(),
          attachmentName: _asString(message['attachment_name']).trim(),
          attachmentSize: _asInt(message['attachment_size']),
          content: _asString(message['content']).trim(),
          bytes: message['attachment_bytes'] as Uint8List,
          reuseExistingPendingMessage: true,
          manageSendingState: false,
        );
        if (!keepGoing) {
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void> _showImageGalleryAt(int messageIndex) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) {
      return;
    }
    final run = _attachmentRunForMessageIndex(messageIndex)
        .where(_isImageAttachment)
        .toList(growable: false);
    if (run.length <= 1) {
      await _showImagePreview(_messages[messageIndex]);
      return;
    }

    final targetMessage = _messages[messageIndex];
    final targetClientId = _asString(targetMessage['client_message_id']).trim();
    var initialPage = run.indexWhere(
      (row) => _asString(row['client_message_id']).trim() == targetClientId,
    );
    if (initialPage < 0) {
      final targetId = _asInt(targetMessage['id']);
      initialPage = run.indexWhere((row) => _asInt(row['id']) == targetId);
    }
    if (initialPage < 0) {
      initialPage = 0;
    }

    final pageController = PageController(initialPage: initialPage);
    var currentPage = initialPage;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setGalleryState) {
              final currentMessage = run[currentPage];
              return Dialog(
                insetPadding: const EdgeInsets.all(18),
                child: SizedBox(
                  width: 980,
                  height: 760,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${currentPage + 1}/${run.length} - '
                                '${_asString(currentMessage['attachment_name']).trim().isNotEmpty ? _asString(currentMessage['attachment_name']).trim() : 'Image'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Telecharger',
                              onPressed: currentMessage['is_local_pending'] == true
                                  ? null
                                  : () => _downloadAttachment(currentMessage),
                              icon: const Icon(Icons.download_outlined),
                            ),
                            IconButton(
                              tooltip: 'Fermer',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: PageView.builder(
                          controller: pageController,
                          itemCount: run.length,
                          onPageChanged: (value) {
                            setGalleryState(() {
                              currentPage = value;
                            });
                          },
                          itemBuilder: (context, pageIndex) {
                            final imageMessage = run[pageIndex];
                            final attachmentBytes = imageMessage['attachment_bytes'];
                            final attachmentUrl = _asString(imageMessage['attachment_url']).trim();
                            Widget imageChild;
                            if (attachmentBytes is Uint8List && attachmentBytes.isNotEmpty) {
                              imageChild = Image.memory(attachmentBytes, fit: BoxFit.contain);
                            } else if (attachmentUrl.isNotEmpty) {
                              imageChild = Image.network(
                                attachmentUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image_outlined, size: 48),
                                ),
                              );
                            } else {
                              imageChild = const Center(
                                child: Icon(Icons.image_outlined, size: 48),
                              );
                            }
                            return InteractiveViewer(
                              minScale: 0.8,
                              maxScale: 4,
                              child: Center(child: imageChild),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      pageController.dispose();
    }
  }

  Future<bool> _uploadAttachment({
    required int conversationId,
    required String clientMessageId,
    required String attachmentName,
    required int attachmentSize,
    required String content,
    String? path,
    Uint8List? bytes,
    bool reuseExistingPendingMessage = false,
    bool clearComposerOnSuccess = false,
    bool restoreComposerOnFailure = false,
    bool manageSendingState = true,
    String? draftOnFailure,
  }) async {
    final multipart = await _buildMultipartFile(
      path: path,
      bytes: bytes,
      fileName: attachmentName,
    );
    if (multipart == null) {
      if (!mounted) {
        return true;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier invalide.')),
      );
      return true;
    }

    final draft = draftOnFailure ?? _messageController.text;
    final cancelToken = CancelToken();
    final localMessage = <String, dynamic>{
      'id': -DateTime.now().microsecondsSinceEpoch,
      'conversation': conversationId,
      'sender': _currentUserId,
      'sender_name': 'Moi',
      'message_type': 'file',
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
      'client_message_id': clientMessageId,
      'attachment_name': attachmentName,
      'attachment_size': attachmentSize,
      'attachment_mime_type': '',
      'attachment_bytes': bytes,
      'upload_progress': 0,
      'upload_failed': false,
      'upload_error': null,
      'is_local_pending': true,
    };

    if (!mounted) {
      return false;
    }

    setState(() {
      if (manageSendingState) {
        _sending = true;
      }
      _sendError = null;
      _activeUploadCancelToken = cancelToken;
      _activeUploadClientMessageId = clientMessageId;
      _activeUploadConversationId = conversationId;
      if (reuseExistingPendingMessage) {
        _messages = _messages.map((row) {
          if (_asString(row['client_message_id']) != clientMessageId) {
            return row;
          }
          return <String, dynamic>{
            ...Map<String, dynamic>.from(row),
            ...localMessage,
            'id': row['id'],
          };
        }).toList(growable: false);
      } else {
        _messages = <Map<String, dynamic>>[..._messages, localMessage];
      }
      _conversations = _conversations.map((row) {
        if (_asInt(row['id']) != conversationId) {
          return row;
        }
        final next = Map<String, dynamic>.from(row);
        next['last_message'] = localMessage;
        next['unread_count'] = 0;
        return next;
      }).toList(growable: false);
    });
    _scrollToBottom();

    try {
      final response = await widget.dio.post(
        '/chat/conversations/$conversationId/send-file/',
        data: FormData.fromMap(<String, dynamic>{
          'file': multipart,
          'content': content,
          'client_message_id': clientMessageId,
        }),
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (total <= 0) {
            return;
          }
          final percent = ((sent / total) * 100).round();
          _updatePendingMessageProgress(clientMessageId, percent);
        },
      );
      final msg = Map<String, dynamic>.from(response.data as Map);
      final msgId = _asInt(msg['id']);
      if (!mounted) {
        return false;
      }
      setState(() {
        if (clearComposerOnSuccess) {
          _draftByConversation[conversationId] = '';
          _messageController.clear();
        }
        _messages = _messages.map((row) {
          if (_asString(row['client_message_id']) == clientMessageId) {
            return msg;
          }
          return row;
        }).toList(growable: false);
        if (msgId > 0) {
          _seenMessageKeys.add(_messageKey(conversationId, msgId));
        }
        _conversations = _conversations.map((row) {
          if (_asInt(row['id']) != conversationId) {
            return row;
          }
          final next = Map<String, dynamic>.from(row);
          next['last_message'] = msg;
          next['unread_count'] = 0;
          return next;
        }).toList(growable: false);
      });
      widget.onUnreadChanged?.call(_sumUnread(_conversations));
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      final cancelled = _isCancelledError(error);
      final errorMessage = cancelled ? 'Envoi du fichier annule.' : _extractApiError(error);
      setState(() {
        if (cancelled) {
          _removePendingUploadMessage(clientMessageId, conversationId);
        } else {
          _markUploadMessageFailed(clientMessageId, conversationId, errorMessage);
          _sendError = errorMessage;
          if (restoreComposerOnFailure) {
            _messageController.value = TextEditingValue(
              text: draft,
              selection: TextSelection.collapsed(offset: draft.length),
            );
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cancelled ? errorMessage : 'Echec envoi du fichier: $errorMessage'),
        ),
      );
      return !cancelled;
    } finally {
      if (mounted) {
        setState(() {
          if (manageSendingState) {
            _sending = false;
          }
          if (identical(_activeUploadCancelToken, cancelToken)) {
            _activeUploadCancelToken = null;
            _activeUploadClientMessageId = null;
            _activeUploadConversationId = null;
          }
        });
      }
    }
  }

  Future<void> _sendFile() async {
    final conversationId = _selectedConversationId;
    if (conversationId == null || _sending) {
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedAttachmentExtensions,
      allowMultiple: true,
      withData: true,
    );
    final pickedFiles = result?.files.where((file) => file.name.trim().isNotEmpty).toList() ??
        const <PlatformFile>[];
    if (pickedFiles.isEmpty) {
      return;
    }

    final draft = _messageController.text;
    final trimmedDraft = draft.trim();

    if (mounted) {
      setState(() {
        _sending = true;
        _sendError = null;
      });
    }

    try {
      for (var index = 0; index < pickedFiles.length; index += 1) {
        if (!mounted || _selectedConversationId != conversationId) {
          break;
        }
        final picked = pickedFiles[index];
        final keepGoing = await _uploadAttachment(
          conversationId: conversationId,
          clientMessageId: _newClientMessageId(conversationId),
          attachmentName: picked.name,
          attachmentSize: picked.size,
          content: index == 0 ? trimmedDraft : '',
          path: picked.path,
          bytes: picked.bytes,
          clearComposerOnSuccess: index == 0,
          restoreComposerOnFailure: index == 0,
          manageSendingState: false,
          draftOnFailure: draft,
        );
        if (!keepGoing) {
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _users;
    final conversationQuery = _conversationSearchController.text.trim().toLowerCase();
    final filteredConversations = _conversations.where((row) {
      if (conversationQuery.isEmpty) return true;
      final text = _conversationTitle(row).toLowerCase();
      final lastMessage = _conversationPreview(row).toLowerCase();
      return text.contains(conversationQuery) || lastMessage.contains(conversationQuery);
    }).toList(growable: false);

    Map<String, dynamic>? selectedConversation;
    for (final row in _conversations) {
      if (_asInt(row['id']) == _selectedConversationId) {
        selectedConversation = row;
        break;
      }
    }

    final compact = MediaQuery.sizeOf(context).width < 900;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        width: 1100,
        height: 680,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Messagerie',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer la fenetre',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (compact) {
                          if (selectedConversation == null) {
                            return _buildConversationList(
                              filteredUsers,
                              filteredConversations,
                              compact: true,
                            );
                          }
                          return _buildThread(selectedConversation, compact: true);
                        }
                        return Row(
                          children: [
                            SizedBox(
                              width: 340,
                              child: _buildConversationList(
                                filteredUsers,
                                filteredConversations,
                                compact: false,
                              ),
                            ),
                            const VerticalDivider(width: 18),
                            Expanded(
                              child: selectedConversation == null
                                  ? const Center(child: Text('Selectionnez une conversation'))
                                  : _buildThread(selectedConversation, compact: false),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(
    List<Map<String, dynamic>> filteredUsers,
    List<Map<String, dynamic>> filteredConversations, {
    required bool compact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _showNewGroupDialog(filteredUsers),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Groupe'),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => _showNewChatDialog(filteredUsers),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('Nouveau'),
            ),
          ],
        ),
        TextField(
          controller: _conversationSearchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Rechercher une conversation',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: filteredConversations.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final row = filteredConversations[index];
              final id = _asInt(row['id']);
              final active = id == _selectedConversationId;
              final unread = _asInt(row['unread_count']);
              final online = _conversationOnline(row);

              return Material(
                color: active ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onTap: () async {
                    await _selectConversation(id);
                  },
                  title: Row(
                    children: [
                      Expanded(child: Text(_conversationTitle(row), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (online)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Color(0xFF12B76A),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    _conversationPreview(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unread > 0)
                        CircleAvatar(
                          radius: 11,
                          child: Text('$unread', style: const TextStyle(fontSize: 11)),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Actions conversation',
                        onSelected: (value) async {
                          if (value == 'close') {
                            await _closeConversation(row);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'close',
                            child: Text(row['is_group'] == true ? 'Fermer groupe' : 'Fermer conversation directe'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showNewChatDialog(List<Map<String, dynamic>> initialUsers) async {
    _searchController.clear();
    await showDialog<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final users = initialUsers.where((user) {
              final q = _searchController.text.trim().toLowerCase();
              if (q.isEmpty) return true;
              final txt = '${_asString(user['full_name'])} ${_asString(user['username'])}'.toLowerCase();
              return txt.contains(q);
            }).toList(growable: false);
            final grouped = _groupUsersByRole(users);

            return AlertDialog(
              title: const Text('Nouvelle conversation'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setLocal(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Rechercher un utilisateur',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 320,
                      child: grouped.isEmpty
                          ? const Center(child: Text('Aucun utilisateur trouve'))
                          : ListView.builder(
                              itemCount: grouped.length,
                              itemBuilder: (context, index) {
                                final entry = grouped[index];
                                final role = entry.key;
                                final roleUsers = entry.value;
                                return ExpansionTile(
                                  key: ValueKey('chat-direct-role-$role'),
                                  title: Text('${_roleLabel(role)} (${roleUsers.length})'),
                                  children: roleUsers.map((user) {
                                    final online = _presenceByUser[_asInt(user['id'])] ?? (user['online'] == true);
                                    return ListTile(
                                      onTap: () async {
                                        Navigator.of(context).pop();
                                        await _openDirectConversation(user);
                                      },
                                      title: Text(
                                        _asString(user['full_name']).isEmpty
                                            ? _asString(user['username'])
                                            : _asString(user['full_name']),
                                      ),
                                      subtitle: Text(_asString(user['username'])),
                                      trailing: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: online ? const Color(0xFF12B76A) : Colors.grey,
                                        ),
                                      ),
                                    );
                                  }).toList(growable: false),
                                );
                              },
                            ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showNewGroupDialog(List<Map<String, dynamic>> initialUsers) async {
    final titleController = TextEditingController();
    final selectedUserIds = <int>{};
    _searchController.clear();

    await showDialog<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final users = initialUsers.where((user) {
              final q = _searchController.text.trim().toLowerCase();
              if (q.isEmpty) return true;
              final txt = '${_asString(user['full_name'])} ${_asString(user['username'])}'.toLowerCase();
              return txt.contains(q);
            }).toList(growable: false);
            final grouped = _groupUsersByRole(users);

            return AlertDialog(
              title: const Text('Nouveau groupe'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Nom du groupe',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setLocal(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Rechercher des participants',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 320,
                      child: grouped.isEmpty
                          ? const Center(child: Text('Aucun utilisateur trouve'))
                          : ListView.builder(
                              itemCount: grouped.length,
                              itemBuilder: (context, index) {
                                final entry = grouped[index];
                                final role = entry.key;
                                final roleUsers = entry.value;
                                return ExpansionTile(
                                  key: ValueKey('chat-group-role-$role'),
                                  title: Text('${_roleLabel(role)} (${roleUsers.length})'),
                                  children: roleUsers.map((user) {
                                    final userId = _asInt(user['id']);
                                    final checked = selectedUserIds.contains(userId);
                                    final online = _presenceByUser[userId] ?? (user['online'] == true);

                                    return CheckboxListTile(
                                      value: checked,
                                      onChanged: (_) {
                                        setLocal(() {
                                          if (checked) {
                                            selectedUserIds.remove(userId);
                                          } else {
                                            selectedUserIds.add(userId);
                                          }
                                        });
                                      },
                                      title: Text(
                                        _asString(user['full_name']).isEmpty
                                            ? _asString(user['username'])
                                            : _asString(user['full_name']),
                                      ),
                                      subtitle: Text(_asString(user['username'])),
                                      secondary: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: online ? const Color(0xFF12B76A) : Colors.grey,
                                        ),
                                      ),
                                      controlAffinity: ListTileControlAffinity.leading,
                                    );
                                  }).toList(growable: false),
                                );
                              },
                            ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () async {
                    final title = titleController.text.trim();
                    if (title.isEmpty || selectedUserIds.isEmpty) {
                      return;
                    }
                    try {
                      final resp = await widget.dio.post(
                        '/chat/conversations/group/',
                        data: <String, dynamic>{
                          'title': title,
                          'participant_ids': selectedUserIds.toList(growable: false),
                        },
                      );
                      final conversation = Map<String, dynamic>.from(resp.data as Map);
                      final cid = _asInt(conversation['id']);
                      if (!mounted) return;

                      setState(() {
                        final exists = _conversations.any((row) => _asInt(row['id']) == cid);
                        if (!exists) {
                          _conversations = <Map<String, dynamic>>[
                            conversation,
                            ..._conversations,
                          ];
                        }
                        _selectedConversationId = cid;
                      });
                      Navigator.of(context).pop();
                      await _loadMessages(cid, reset: true);
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Impossible de creer le groupe.')),
                      );
                    }
                  },
                  child: const Text('Creer'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
  }

  Future<void> _renameGroupConversation(Map<String, dynamic> conversation) async {
    final conversationId = _asInt(conversation['id']);
    final titleController = TextEditingController(
      text: _asString(conversation['title']),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le groupe'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: 'Nouveau nom'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              final nextTitle = titleController.text.trim();
              if (nextTitle.isEmpty) {
                return;
              }
              try {
                await widget.dio.patch(
                  '/chat/conversations/$conversationId/group/',
                  data: <String, dynamic>{'title': nextTitle},
                );
                if (!mounted) return;
                Navigator.of(ctx).pop();
                await _reloadConversationsOnly();
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Impossible de renommer le groupe.')),
                );
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );

    titleController.dispose();
  }

  Future<void> _groupAddMember(Map<String, dynamic> conversation) async {
    final conversationId = _asInt(conversation['id']);
    final existing = ((conversation['group_participants'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => _asInt(e['id']))
        .toSet();
    final candidates = _users.where((u) => !existing.contains(_asInt(u['id']))).toList(growable: false);
    int? selectedUserId;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: const Text('Ajouter un membre'),
          content: DropdownButtonFormField<int?>(
            initialValue: selectedUserId,
            items: candidates
                .map(
                  (u) => DropdownMenuItem<int?>(
                    value: _asInt(u['id']),
                    child: Text(
                      _asString(u['full_name']).isEmpty
                          ? _asString(u['username'])
                          : _asString(u['full_name']),
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (v) => setLocal(() => selectedUserId = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: selectedUserId == null
                  ? null
                  : () async {
                      try {
                        await widget.dio.post(
                          '/chat/conversations/$conversationId/group/add-member/',
                          data: <String, dynamic>{'user_id': selectedUserId},
                        );
                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        await _reloadConversationsOnly();
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ajout membre impossible.')),
                        );
                      }
                    },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _groupRemoveOrPromoteMember(Map<String, dynamic> conversation) async {
    final conversationId = _asInt(conversation['id']);
    final members = ((conversation['group_participants'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => _asInt(m['id']) != _currentUserId)
        .toList(growable: false);
    final adminCount = members.where((m) => m['is_admin'] == true).length + 1;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Membres du groupe'),
        content: SizedBox(
          width: 520,
          height: 360,
          child: ListView.separated(
            itemCount: members.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final member = members[index];
              final memberId = _asInt(member['id']);
              final isAdmin = member['is_admin'] == true;
              return ListTile(
                title: Text(_asString(member['full_name'])),
                subtitle: Text(isAdmin ? 'Admin' : 'Membre'),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    OutlinedButton(
                      onPressed: isAdmin
                          ? null
                          : () async {
                              try {
                                await widget.dio.post(
                                  '/chat/conversations/$conversationId/group/promote-admin/',
                                  data: <String, dynamic>{'user_id': memberId},
                                );
                                if (!mounted) return;
                                await _reloadConversationsOnly();
                                Navigator.of(ctx).pop();
                              } catch (_) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Promotion admin impossible.')),
                                );
                              }
                            },
                      child: const Text('Promouvoir'),
                    ),
                    OutlinedButton(
                      onPressed: !isAdmin || adminCount <= 1
                          ? null
                          : () async {
                              try {
                                await widget.dio.post(
                                  '/chat/conversations/$conversationId/group/demote-admin/',
                                  data: <String, dynamic>{'user_id': memberId},
                                );
                                if (!mounted) return;
                                await _reloadConversationsOnly();
                                Navigator.of(ctx).pop();
                              } catch (_) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Retrogradation admin impossible.')),
                                );
                              }
                            },
                      child: const Text('Retrograder'),
                    ),
                    OutlinedButton(
                      onPressed: !isAdmin
                          ? null
                          : () async {
                              try {
                                await widget.dio.post(
                                  '/chat/conversations/$conversationId/group/transfer-admin/',
                                  data: <String, dynamic>{'user_id': memberId},
                                );
                                if (!mounted) return;
                                await _reloadConversationsOnly();
                                Navigator.of(ctx).pop();
                              } catch (_) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Transfert admin impossible.')),
                                );
                              }
                            },
                      child: const Text('Transferer'),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        try {
                          await widget.dio.post(
                            '/chat/conversations/$conversationId/group/remove-member/',
                            data: <String, dynamic>{'user_id': memberId},
                          );
                          if (!mounted) return;
                          await _reloadConversationsOnly();
                          Navigator.of(ctx).pop();
                        } catch (_) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Suppression membre impossible.')),
                          );
                        }
                      },
                      child: const Text('Retirer'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildThread(Map<String, dynamic> conversation, {required bool compact}) {
    final title = _conversationTitle(conversation);
    final online = _conversationOnline(conversation);
    final conversationId = _asInt(conversation['id']);
    final isTyping = _typingByConversation[conversationId] == true;
    final isGroup = conversation['is_group'] == true;
    final isGroupAdmin = conversation['is_group_admin'] == true;

    return Column(
      children: [
        ListTile(
          leading: compact
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() {
                    _storeCurrentDraft();
                    _selectedConversationId = null;
                    _messages = <Map<String, dynamic>>[];
                    _pendingInThreadCount = 0;
                  }),
                )
              : null,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            isTyping
                ? 'Ecrit...'
                : (online ? 'En ligne' : 'Hors ligne'),
          ),
          trailing: Container(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isGroup)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFF12B76A) : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (isGroup && isGroupAdmin)
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'rename') {
                        await _renameGroupConversation(conversation);
                      } else if (value == 'add') {
                        await _groupAddMember(conversation);
                      } else if (value == 'members') {
                        await _groupRemoveOrPromoteMember(conversation);
                      } else if (value == 'delete') {
                        await _deleteGroupConversation(conversation);
                      } else if (value == 'leave') {
                        await _leaveGroupConversation(conversation);
                      } else if (value == 'close') {
                        await _closeConversation(conversation);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Renommer groupe')),
                      PopupMenuItem(value: 'add', child: Text('Ajouter membre')),
                      PopupMenuItem(value: 'members', child: Text('Gerer membres')),
                      PopupMenuItem(value: 'close', child: Text('Fermer groupe')),
                      PopupMenuItem(value: 'leave', child: Text('Quitter groupe')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer groupe')),
                    ],
                  ),
                if (isGroup && !isGroupAdmin)
                  IconButton(
                    tooltip: 'Quitter groupe',
                    onPressed: () => _leaveGroupConversation(conversation),
                    icon: const Icon(Icons.logout_outlined),
                  ),
                if (!isGroup)
                  IconButton(
                    tooltip: 'Fermer conversation directe',
                    onPressed: () => _closeConversation(conversation),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _messageScrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                if (_messages.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'Aucun message pour le moment. Lance la conversation.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      if (_hasMoreMessages)
                        TextButton.icon(
                          onPressed: _loadingOlderMessages
                              ? null
                              : () => _loadMessages(conversationId, appendOlder: true),
                          icon: _loadingOlderMessages
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.history_outlined),
                          label: Text(
                            _loadingOlderMessages
                                ? 'Chargement...'
                                : 'Charger les anciens messages',
                          ),
                        )
                      else
                        Text(
                          'Debut de la conversation',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                    ],
                  ),
                );
              }

              final message = _messages[index - 1];
        final messageIndex = index - 1;
              final previousMessage = index > 1 ? _messages[index - 2] : null;
              final nextMessage = index < _messages.length ? _messages[index] : null;
              final mine = _currentUserId != null &&
                  _asInt(message['sender'] ?? message['sender_id']) == _currentUserId;
              final groupedWithPrevious =
                  _shouldGroupAttachmentMessages(message, previousMessage);
              final groupedWithNext = _shouldGroupAttachmentMessages(message, nextMessage);
              final showSender = !groupedWithPrevious;
                final attachmentRun = _attachmentRunForMessageIndex(messageIndex);
                final failedBatch = attachmentRun
                  .where(_isRetriableFailedAttachment)
                  .toList(growable: false);
                final failedBatchCount = failedBatch.length;
                final firstFailedClientMessageId = failedBatchCount > 0
                  ? _asString(failedBatch.first['client_message_id']).trim()
                  : '';
                final showBatchRetryAction = message['upload_failed'] == true &&
                  failedBatchCount > 1 &&
                  _asString(message['client_message_id']).trim() == firstFailedClientMessageId;
              final messageTime = _formatMessageTime(message['created_at']);
              final lastRead = _lastReadByConversation[conversationId] ?? 0;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: EdgeInsets.only(
                    top: groupedWithPrevious ? 2 : 5,
                    bottom: groupedWithNext ? 2 : 5,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: mine
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: _messageBubbleRadius(
                      mine: mine,
                      groupedWithPrevious: groupedWithPrevious,
                      groupedWithNext: groupedWithNext,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      if (showSender)
                        Text(
                          _senderLabel(message),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (showSender)
                        const SizedBox(height: 2),
                      if (_messageHasAttachment(message))
                        Column(
                          crossAxisAlignment:
                              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (_isImageAttachment(message))
                              Builder(
                                builder: (context) {
                                  final attachmentBytes = message['attachment_bytes'];
                                  final attachmentUrl = _asString(message['attachment_url']).trim();
                                  Widget imageChild;
                                  if (attachmentBytes is Uint8List && attachmentBytes.isNotEmpty) {
                                    imageChild = Image.memory(
                                      attachmentBytes,
                                      fit: BoxFit.cover,
                                      width: 220,
                                      height: 180,
                                    );
                                  } else if (attachmentUrl.isNotEmpty) {
                                    imageChild = Image.network(
                                      attachmentUrl,
                                      fit: BoxFit.cover,
                                      width: 220,
                                      height: 180,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 220,
                                        height: 180,
                                        color: Theme.of(context).colorScheme.surface,
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.broken_image_outlined),
                                      ),
                                    );
                                  } else {
                                    imageChild = Container(
                                      width: 220,
                                      height: 180,
                                      color: Theme.of(context).colorScheme.surface,
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.image_outlined),
                                    );
                                  }

                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      onTap: message['is_local_pending'] == true
                                          ? null
                                          : () => _showImageGalleryAt(messageIndex),
                                      child: imageChild,
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: message['is_local_pending'] == true
                                  ? null
                                  : () => _openAttachment(message),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _attachmentIcon(message),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _asString(message['attachment_name']).trim().isNotEmpty
                                                ? _asString(message['attachment_name']).trim()
                                                : 'Piece jointe',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatFileSize(_asInt(message['attachment_size'])),
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                          if (_isPdfAttachment(message) &&
                                              message['is_local_pending'] != true)
                                            Text(
                                              'Apercu PDF disponible',
                                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: Theme.of(context).colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          if (message['is_local_pending'] == true)
                                            Text(
                                              'Upload: ${_asInt(message['upload_progress'])}%',
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          if (message['upload_failed'] == true)
                                            Text(
                                              (_asString(message['upload_error']).trim().isNotEmpty)
                                                  ? _asString(message['upload_error']).trim()
                                                  : 'Echec de l\'upload',
                                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: Theme.of(context).colorScheme.error,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (message['is_local_pending'] != true) ...[
                                      const SizedBox(width: 8),
                                      if (message['upload_failed'] == true)
                                        IconButton(
                                          tooltip: 'Reessayer',
                                          onPressed: _sending ? null : () => _retryFailedFileUpload(message),
                                          icon: const Icon(Icons.refresh_rounded),
                                        )
                                      else
                                        const Icon(Icons.download_outlined),
                                    ] else ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: 'Annuler l\'upload',
                                        onPressed: _asString(message['client_message_id']) == _activeUploadClientMessageId
                                            ? _cancelActiveUpload
                                            : null,
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (showBatchRetryAction)
                              Align(
                                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: TextButton.icon(
                                    onPressed: _sending
                                        ? null
                                        : () => _retryFailedAttachmentBatchFrom(messageIndex),
                                    icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                                    label: Text('Reessayer le lot ($failedBatchCount)'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (_messageHasAttachment(message) && _asString(message['content']).trim().isNotEmpty)
                        const SizedBox(height: 6),
                      if (_asString(message['content']).trim().isNotEmpty)
                        Text(_asString(message['content'])),
                      if (messageTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            messageTime,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      if (mine)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _outgoingStatusLabel(message, lastRead),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        if (_pendingInThreadCount > 0)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _pendingInThreadCount = 0);
                  _scrollToBottom();
                  if (conversationId > 0) {
                    unawaited(_markRead(conversationId));
                  }
                },
                icon: const Icon(Icons.arrow_downward),
                label: Text('$_pendingInThreadCount nouveaux messages'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_sendError != null) ...[
                Text(
                  _sendError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  IconButton(
                    tooltip: 'Envoyer un fichier',
                    onPressed: _sending ? null : _sendFile,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  if (_activeUploadCancelToken != null) ...[
                    IconButton(
                      tooltip: 'Annuler l\'upload en cours',
                      onPressed: _cancelActiveUpload,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: _onInputChanged,
                      onTap: () {
                        if (_pendingInThreadCount > 0) {
                          setState(() => _pendingInThreadCount = 0);
                        }
                      },
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Ecrire un message...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendMessage,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
