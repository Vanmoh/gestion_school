import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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

  String _wsUrlFromApiBase(String apiBase, String token) {
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
    final uri = Uri(
      scheme: wsScheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: wsPath,
      queryParameters: <String, String>{'token': token},
    );
    return uri.toString();
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
        _connectWs(baseUrl, token);
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

  void _connectWs(String baseUrl, String token) {
    _wsBaseUrl = baseUrl;
    _wsToken = token;
    _reconnectTimer?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();

    final wsUrl = _wsUrlFromApiBase(baseUrl, token);
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
      _connectWs(base, token);
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
          'content': _asString(data['content']),
          'created_at': _asString(data['created_at']),
          'client_message_id': _asString(data['client_message_id']),
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

    setState(() {
      _sending = true;
      _sendError = null;
    });
    _typingStopTimer?.cancel();
    _onInputChanged('');

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
        if (msgId > 0 && !_seenMessageKeys.contains(dedupeKey)) {
          _messages = <Map<String, dynamic>>[..._messages, msg];
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

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _users;
    final conversationQuery = _conversationSearchController.text.trim().toLowerCase();
    final filteredConversations = _conversations.where((row) {
      if (conversationQuery.isEmpty) return true;
      final text = _conversationTitle(row).toLowerCase();
      final lastMessage = _asString((row['last_message'] as Map?)?['content']).toLowerCase();
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
                    _asString((row['last_message'] as Map?)?['content'] ?? ''),
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
              final mine = _currentUserId != null &&
                  _asInt(message['sender'] ?? message['sender_id']) == _currentUserId;
              final messageId = _asInt(message['id']);
                final messageTime = _formatMessageTime(message['created_at']);
              final lastRead = _lastReadByConversation[conversationId] ?? 0;
              final isLastMine = mine && index == _messages.length - 1;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  constraints: const BoxConstraints(maxWidth: 520),
                  decoration: BoxDecoration(
                    color: mine
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        _senderLabel(message),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(_asString(message['content'])),
                      if (messageTime.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            messageTime,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      if (isLastMine)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            lastRead >= messageId ? 'Lu' : 'Envoye',
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
