import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'models/etablissement.dart';
import 'screens/etablissement_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'core/constants/branding.dart';
import 'core/network/api_client.dart';
import 'core/providers/navigation_intents.dart';
import 'core/theme/app_theme.dart';
import 'features/attendance/presentation/attendance_controller.dart';
import 'features/attendance/presentation/attendance_page.dart';
import 'features/attendance/presentation/teacher_attendance_page.dart';
import 'features/attendance/presentation/teacher_timesheet_page.dart';
import 'features/academics/presentation/academics_page.dart';
import 'features/activity_logs/presentation/activity_logs_page.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/domain/auth_user.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/canteen/presentation/canteen_page.dart';
import 'features/chat/presentation/chat_panel.dart';
import 'features/backup/presentation/backup_restore_page.dart';
import 'features/promotion/presentation/promotion_page.dart';
import 'features/dashboard/presentation/dashboard_controller.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/dashboard/presentation/role_dashboards.dart';
import 'features/exams/presentation/exams_controller.dart';
import 'features/exams/presentation/exams_page.dart';
import 'features/communication/presentation/communication_page.dart';
import 'features/discipline/presentation/discipline_page.dart';
import 'features/etablissements/presentation/etablissements_page.dart';
import 'features/grades/presentation/grades_page.dart';
import 'features/library/presentation/library_page.dart';
import 'features/payments/presentation/payments_controller.dart';
import 'features/payments/presentation/payments_page.dart';
import 'features/reports/presentation/reports_page.dart';
import 'features/stock/presentation/stock_page.dart';
import 'features/students/presentation/students_controller.dart';
import 'features/students/presentation/students_page.dart';
import 'features/teachers/presentation/teachers_page.dart';
import 'features/timetable/presentation/timetable_module_page.dart';
import 'features/users/presentation/users_controller.dart';
import 'features/users/presentation/users_page.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final parent = super.getScrollPhysics(context);
    return const AlwaysScrollableScrollPhysics().applyTo(parent);
  }
}

Future<void> _invalidateRefreshProvidersForView(
  WidgetRef ref,
  Widget view,
) async {
  if (view is DashboardPage) {
    ref.invalidate(dashboardStatsProvider);
    await ref.read(dashboardStatsProvider.future);
    return;
  }

  if (view is AttendancePage || view is TeacherAttendancePage) {
    ref.invalidate(attendanceStudentsProvider);
    ref.invalidate(attendancesProvider);
    ref.invalidate(attendanceMonthlyStatsProvider);
    await ref.read(attendancesProvider.future);
    return;
  }

  if (view is ExamsPage) {
    ref.invalidate(examSessionsProvider);
    ref.invalidate(examPlanningsProvider);
    ref.invalidate(examResultsProvider);
    ref.invalidate(examInvigilationsProvider);
    ref.invalidate(examAcademicYearsProvider);
    ref.invalidate(examClassroomsProvider);
    ref.invalidate(examSubjectsProvider);
    ref.invalidate(examStudentsProvider);
    ref.invalidate(examSupervisorsProvider);
    await ref.read(examSessionsProvider.future);
    return;
  }

  if (view is PaymentsPage) {
    ref.invalidate(paymentsProvider);
    ref.invalidate(feesProvider);
    await ref.read(paymentsProvider.future);
    return;
  }

  if (view is UsersPage) {
    ref.invalidate(usersProvider);
    await ref.read(usersProvider.future);
    return;
  }

  if (view is StudentsPage) {
    ref.invalidate(studentsProvider);
    await ref.read(studentsProvider.future);
    return;
  }

  // For feature pages loading data in initState, remount is enough.
  await Future<void>.delayed(const Duration(milliseconds: 150));
}

class _GlobalFeatureRefreshHost extends ConsumerStatefulWidget {
  final Widget child;

  const _GlobalFeatureRefreshHost({super.key, required this.child});

  @override
  ConsumerState<_GlobalFeatureRefreshHost> createState() =>
      _GlobalFeatureRefreshHostState();
}

class _GlobalFeatureRefreshHostState
    extends ConsumerState<_GlobalFeatureRefreshHost> {
  int _epoch = 0;

  Future<void> _handleRefresh() async {
    try {
      await _invalidateRefreshProvidersForView(ref, widget.child);
    } catch (_) {
      // Keep pull-to-refresh usable even if a provider refresh fails.
    }
    if (!mounted) {
      return;
    }
    setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      notificationPredicate: (_) => true,
      onRefresh: _handleRefresh,
      child: KeyedSubtree(
        key: ValueKey('${widget.child.runtimeType}-$_epoch'),
        child: widget.child,
      ),
    );
  }
}

class GestionSchoolApp extends ConsumerWidget {
  const GestionSchoolApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: SchoolBranding.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      scrollBehavior: const _AppScrollBehavior(),
      routes: {
        '/': (_) => const PublicEtablissementEntryPage(),
        '/login': (_) => const LoginPage(),
        '/dashboard': (_) =>
            const RequireEtablissementSelection(child: _AdminShell()),
        '/home/admin': (_) =>
            const RequireEtablissementSelection(child: _AdminShell()),
        '/home/accountant': (_) =>
          const RequireEtablissementSelection(child: _AdminShell()),
        '/home/teacher': (_) =>
          const RequireEtablissementSelection(child: _AdminShell()),
        '/home/supervisor': (_) =>
          const RequireEtablissementSelection(child: _AdminShell()),
        '/home/parent': (_) =>
          const RequireEtablissementSelection(child: _AdminShell()),
        '/home/student': (_) =>
          const RequireEtablissementSelection(child: _AdminShell()),
        '/attendance': (_) =>
            const _GlobalFeatureRefreshHost(child: AttendancePage()),
        '/exams': (_) => const _GlobalFeatureRefreshHost(child: ExamsPage()),
        '/students': (_) =>
            const _GlobalFeatureRefreshHost(child: StudentsPage()),
        '/payments': (_) =>
            const _GlobalFeatureRefreshHost(child: PaymentsPage()),
        '/timetable': (_) =>
          const _GlobalFeatureRefreshHost(child: TimetableModulePage()),
        '/reports': (_) =>
            const _GlobalFeatureRefreshHost(child: ReportsPage()),
        '/users': (_) => const _GlobalFeatureRefreshHost(child: UsersPage()),
      },
    );
  }
}

class _AdminShell extends ConsumerStatefulWidget {
  const _AdminShell();

  @override
  ConsumerState<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<_AdminShell> {
  static const Duration _chatWsHeartbeatInterval = Duration(seconds: 20);

  String _selectedKey = 'dashboard';
  final Map<String, bool> _expandedGroups = {};
  bool _sidebarCollapsed = false;
  String? _hoveredKey;
  int _chatUnread = 0;
  bool _chatPanelOpen = false;
  final Map<int, int> _chatUnreadByConversation = <int, int>{};
  final Set<String> _seenShellMessageKeys = <String>{};
  Timer? _chatUnreadTimer;
  WebSocketChannel? _chatChannel;
  StreamSubscription<dynamic>? _chatChannelSub;
  Timer? _chatWsReconnectTimer;
  Timer? _chatWsHeartbeatTimer;
  bool _chatWsAwaitingPong = false;
  String? _chatWsBaseUrl;
  String? _chatWsToken;

  int _shellAsInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _shellAsString(dynamic value) => value?.toString() ?? '';

  String _shellMessageKey(int conversationId, int messageId) => '$conversationId:$messageId';

  static const _items = [
    _AdminMenuItem(
      keyName: 'dashboard',
      label: 'Tableau de bord',
      icon: Icons.grid_view_rounded,
      view: DashboardPage(),
    ),
    _AdminMenuItem(
      keyName: 'students',
      label: 'Gestion des élèves',
      icon: Icons.school_outlined,
      view: StudentsPage(),
    ),
    _AdminMenuItem(
      keyName: 'teachers',
      label: 'Enseignants',
      icon: Icons.badge_outlined,
      view: TeachersPage(),
    ),
    _AdminMenuItem(
      keyName: 'academics',
      label: 'Académique',
      icon: Icons.account_tree_outlined,
      view: AcademicsPage(),
    ),
    _AdminMenuItem(
      keyName: 'grades',
      label: 'Notes & Bulletins',
      icon: Icons.auto_stories_outlined,
      view: GradesPage(),
    ),
    _AdminMenuItem(
      keyName: 'promotion',
      label: 'Passation & Archivage',
      icon: Icons.trending_up_outlined,
      view: PromotionPage(),
    ),
    _AdminMenuItem(
      keyName: 'attendance',
      label: 'Absences',
      icon: Icons.fact_check_outlined,
      view: AttendancePage(),
    ),
    _AdminMenuItem(
      keyName: 'teacher_attendance',
      label: 'Absences enseignants',
      icon: Icons.assignment_ind_outlined,
      view: TeacherAttendancePage(),
    ),
    _AdminMenuItem(
      keyName: 'teacher_timesheet',
      label: 'Emargement enseignants',
      icon: Icons.access_time_rounded,
      view: TeacherTimesheetPage(),
    ),
    _AdminMenuItem(
      keyName: 'discipline',
      label: 'Discipline',
      icon: Icons.gavel_outlined,
      view: DisciplinePage(),
    ),
    _AdminMenuItem(
      keyName: 'exams',
      label: 'Examens',
      icon: Icons.quiz_outlined,
      view: ExamsPage(),
    ),
    _AdminMenuItem(
      keyName: 'timetable',
      label: 'Emploi du temps',
      icon: Icons.calendar_month_outlined,
      view: TimetableModulePage(),
    ),
    _AdminMenuItem(
      keyName: 'finance',
      label: 'Finances',
      icon: Icons.account_balance_wallet_outlined,
      view: PaymentsPage(),
    ),
    _AdminMenuItem(
      keyName: 'reports',
      label: 'Rapports',
      icon: Icons.description_outlined,
      view: ReportsPage(),
    ),
    _AdminMenuItem(
      keyName: 'activity_logs',
      label: 'Logs activités',
      icon: Icons.history_edu_outlined,
      view: ActivityLogsPage(),
    ),
    _AdminMenuItem(
      keyName: 'backup_restore',
      label: 'Backup & Restore',
      icon: Icons.backup_table_outlined,
      view: BackupRestorePage(),
    ),
    _AdminMenuItem(
      keyName: 'users',
      label: 'Gestion des utilisateurs',
      icon: Icons.group_outlined,
      view: UsersPage(),
    ),
    _AdminMenuItem(
      keyName: 'etablissements',
      label: 'Gestion etablissements',
      icon: Icons.apartment_outlined,
      view: EtablissementsPage(),
    ),
    _AdminMenuItem(
      keyName: 'communication',
      label: 'Communication',
      icon: Icons.campaign_outlined,
      view: CommunicationPage(),
    ),
    _AdminMenuItem(
      keyName: 'library',
      label: 'Bibliothèque',
      icon: Icons.menu_book_outlined,
      view: LibraryPage(),
    ),
    _AdminMenuItem(
      keyName: 'canteen',
      label: 'Cantine',
      icon: Icons.restaurant_menu_outlined,
      view: CanteenPage(),
    ),
    _AdminMenuItem(
      keyName: 'stock',
      label: 'Stock & Fournitures',
      icon: Icons.inventory_2_outlined,
      view: StockPage(),
    ),
  ];

  static const _groups = [
    _AdminMenuGroup(
      keyName: 'pilotage',
      title: 'Pilotage',
      itemKeys: ['dashboard'],
    ),
    _AdminMenuGroup(
      keyName: 'pedagogie',
      title: 'Pédagogie',
      itemKeys: [
        'students',
        'teachers',
        'attendance',
        'teacher_attendance',
        'teacher_timesheet',
        'discipline',
      ],
      collapsible: true,
    ),
    _AdminMenuGroup(
      keyName: 'academique',
      title: 'Académique',
      itemKeys: ['academics', 'grades', 'promotion', 'exams', 'timetable'],
      collapsible: true,
    ),
    _AdminMenuGroup(
      keyName: 'finances',
      title: 'Finances',
      itemKeys: ['finance'],
      collapsible: true,
    ),
    _AdminMenuGroup(
      keyName: 'administration',
      title: 'Administration',
      itemKeys: [
        'users',
        'etablissements',
        'communication',
        'reports',
        'activity_logs',
        'backup_restore',
      ],
      collapsible: true,
    ),
    _AdminMenuGroup(
      keyName: 'ressources',
      title: 'Ressources',
      itemKeys: ['library', 'canteen', 'stock'],
      collapsible: true,
    ),
  ];

  bool _isItemVisibleForRole(String key, String? role) {
    if (role == 'parent' || role == 'student') {
      const parentStudentKeys = {
        'dashboard',
        'reports',
      };
      return parentStudentKeys.contains(key);
    }

    if (role == 'teacher') {
      const teacherKeys = {
        'dashboard',
        'teacher_timesheet',
        'grades',
        'timetable',
        'discipline',
      };
      return teacherKeys.contains(key);
    }

    if (role == 'accountant') {
      const accountantKeys = {
        'dashboard',
        'finance',
        'reports',
      };
      return accountantKeys.contains(key);
    }

    if (role == 'supervisor') {
      const supervisorKeys = {
        'dashboard',
        'students',
        'attendance',
        'teacher_attendance',
        'teacher_timesheet',
        'discipline',
        'timetable',
      };
      return supervisorKeys.contains(key);
    }

    if (key == 'etablissements') {
      return role == 'super_admin';
    }
    return true;
  }

  bool _isItemReadOnlyForRole(String key, String? role) {
    if (role == 'parent' || role == 'student') {
      return true;
    }

    if (role == 'teacher') {
      return key == 'timetable';
    }

    if (role == 'accountant') {
      return key == 'dashboard' || key == 'reports';
    }

    if (role == 'supervisor') {
      return key == 'dashboard' ||
          key == 'students' ||
          key == 'timetable';
    }

    return false;
  }

  String _firstVisibleKeyForRole(String? role) {
    for (final item in _items) {
      if (_isItemVisibleForRole(item.keyName, role)) {
        return item.keyName;
      }
    }
    return 'dashboard';
  }

  _AdminMenuItem _selectedItemForRole(String? role) {
    final isVisible = _isItemVisibleForRole(_selectedKey, role);
    final targetKey = isVisible ? _selectedKey : _firstVisibleKeyForRole(role);
    return _items.firstWhere((item) => item.keyName == targetKey);
  }

  Widget _buildRoleSpecificView(_AdminMenuItem item, String? role) {
    if (item.keyName != 'dashboard') {
      return item.view;
    }

    switch (role) {
      case 'teacher':
        return const TeacherDashboardPage();
      case 'supervisor':
        return const SupervisorDashboardPage();
      case 'accountant':
        return const AccountantDashboardPage();
      case 'parent':
        return const ParentDashboardPage();
      case 'student':
        return const StudentDashboardPage();
      default:
        return item.view;
    }
  }

  @override
  void initState() {
    super.initState();
    for (final group in _groups) {
      if (group.collapsible) {
        _expandedGroups[group.keyName] = true;
      }
    }
    Future.microtask(_warmUpAdminData);
    Future.microtask(_refreshChatUnread);
    Future.microtask(_initChatUnreadRealtime);
    _chatUnreadTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refreshChatUnread(),
    );
  }

  @override
  void dispose() {
    _chatUnreadTimer?.cancel();
    _chatWsReconnectTimer?.cancel();
    _chatWsHeartbeatTimer?.cancel();
    _chatChannelSub?.cancel();
    _chatChannel?.sink.close();
    super.dispose();
  }

  String _chatWsUrlFromApiBase(String apiBase, String token) {
    final base = Uri.parse(apiBase.trim());
    final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';

    var path = base.path;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/api')) {
      path = path.substring(0, path.length - 4);
    }

    return Uri(
      scheme: wsScheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '$path/ws/chat/stream/',
      queryParameters: <String, String>{'token': token},
    ).toString();
  }

  Future<void> _initChatUnreadRealtime() async {
    try {
      final storage = ref.read(tokenStorageProvider);
      final token = await storage.accessToken();
      if (token == null || token.isEmpty) {
        _chatWsReconnectTimer ??= Timer(
          const Duration(seconds: 2),
          () {
            _chatWsReconnectTimer = null;
            _initChatUnreadRealtime();
          },
        );
        return;
      }
      final storedBase = (await storage.apiBaseUrl()) ?? '';
      final activeBase = ref.read(dioProvider).options.baseUrl.trim();
      final base = activeBase.isNotEmpty ? activeBase : storedBase;
      _connectChatUnreadWs(base, token);
    } catch (_) {
      // Fallback polling remains active.
    }
  }

  void _connectChatUnreadWs(String baseUrl, String token) {
    _chatWsBaseUrl = baseUrl;
    _chatWsToken = token;
    _chatWsReconnectTimer?.cancel();
    _chatWsHeartbeatTimer?.cancel();
    _chatWsAwaitingPong = false;
    _chatChannelSub?.cancel();
    _chatChannel?.sink.close();

    final wsUrl = _chatWsUrlFromApiBase(baseUrl, token);
    _chatChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _chatChannelSub = _chatChannel!.stream.listen(
      _handleChatUnreadWsEvent,
      onError: (_) => _scheduleChatUnreadReconnect(),
      onDone: _scheduleChatUnreadReconnect,
    );
    _startChatUnreadHeartbeat();
  }

  void _startChatUnreadHeartbeat() {
    _chatWsHeartbeatTimer?.cancel();
    _chatWsHeartbeatTimer = Timer.periodic(_chatWsHeartbeatInterval, (_) {
      if (_chatChannel == null) {
        return;
      }
      if (_chatWsAwaitingPong) {
        _chatChannel?.sink.close();
        _scheduleChatUnreadReconnect();
        return;
      }
      _chatWsAwaitingPong = true;
      _chatChannel?.sink.add(jsonEncode(<String, dynamic>{'action': 'ping'}));
    });
  }

  void _scheduleChatUnreadReconnect() {
    if (!mounted || _chatWsReconnectTimer != null) {
      return;
    }
    _chatWsHeartbeatTimer?.cancel();
    final base = _chatWsBaseUrl;
    final token = _chatWsToken;
    if (base == null || token == null || token.isEmpty) {
      return;
    }
    _chatWsReconnectTimer = Timer(const Duration(seconds: 4), () {
      _chatWsReconnectTimer = null;
      _connectChatUnreadWs(base, token);
    });
  }

  void _handleChatUnreadWsEvent(dynamic payload) {
    try {
      final data = jsonDecode(payload.toString());
      if (data is! Map) {
        return;
      }
      final event = (data['event'] ?? '').toString();
      if (event == 'pong') {
        _chatWsAwaitingPong = false;
        return;
      }

      if (event == 'connected') {
        _chatWsAwaitingPong = false;
        _refreshChatUnread();
        return;
      }

      if (event == 'message') {
        final senderId = _shellAsInt(data['sender_id']);
        final conversationId = _shellAsInt(data['conversation_id']);
        final messageId = _shellAsInt(data['message_id']);
        final currentUserId = ref.read(authControllerProvider).value?.id;
        final isExternalMessage = currentUserId != null && senderId > 0 && senderId != currentUserId;
        if (isExternalMessage && conversationId > 0 && messageId > 0) {
          final messageKey = _shellMessageKey(conversationId, messageId);
          if (!_seenShellMessageKeys.contains(messageKey)) {
            _seenShellMessageKeys.add(messageKey);
            if (!_chatPanelOpen && mounted) {
              final senderName = _shellAsString(data['sender_name']).trim();
              final contentPreview = _shellAsString(data['content']).trim();
              final title = senderName.isNotEmpty ? senderName : 'Nouveau message';
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      contentPreview.isEmpty ? title : '$title: $contentPreview',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
            }
          }
        }
        _refreshChatUnread();
        return;
      }

      if (event == 'read_receipt') {
        _refreshChatUnread();
      }
    } catch (_) {
      // Ignore malformed websocket payloads.
    }
  }

  Future<void> _refreshChatUnread() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('/chat/conversations/');
      final data = resp.data;
      List rows;
      if (data is List) {
        rows = data;
      } else if (data is Map && data['results'] is List) {
        rows = data['results'] as List;
      } else {
        rows = const [];
      }

      final nextUnreadByConversation = <int, int>{};
      var unread = 0;
      for (final row in rows) {
        if (row is Map) {
          final conversationId = _shellAsInt(row['id']);
          final raw = row['unread_count'];
          final unreadCount = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
          if (conversationId > 0) {
            nextUnreadByConversation[conversationId] = unreadCount;
          }
          unread += unreadCount;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _chatUnread = unread;
        _chatUnreadByConversation
          ..clear()
          ..addAll(nextUnreadByConversation);
      });
    } catch (_) {
      // Keep shell stable if chat API is temporarily unavailable.
    }
  }

  Future<void> _openChatPanel() async {
    if (mounted) {
      setState(() => _chatPanelOpen = true);
    }
    await showDialog<void>(
      context: context,
      builder: (_) {
        return ChatPanel(
          dio: ref.read(dioProvider),
          tokenStorage: ref.read(tokenStorageProvider),
          onUnreadChanged: (value) {
            if (!mounted) {
              return;
            }
            setState(() => _chatUnread = value);
          },
        );
      },
    );

    if (!mounted) {
      return;
    }
    setState(() => _chatPanelOpen = false);
    await _refreshChatUnread();
  }

  Future<void> _warmUpAdminData() async {
    try {
      final role = ref.read(authControllerProvider).value?.role;
      final warmups = <Future<void>>[
        ref.read(dashboardStatsProvider.future).then((_) {}),
      ];

      if (_isItemVisibleForRole('students', role)) {
        warmups.add(ref.read(studentsProvider.future).then((_) {}));
      }
      if (_isItemVisibleForRole('users', role)) {
        warmups.add(ref.read(usersProvider.future).then((_) {}));
      }
      if (_isItemVisibleForRole('finance', role)) {
        warmups.add(ref.read(paymentsProvider.future).then((_) {}));
      }

      await Future.wait<void>(warmups);
    } catch (_) {
      // Keep UI responsive even if one warm-up request fails.
    }
  }

  void _selectItem(String key) {
    for (final group in _groups) {
      if (group.itemKeys.contains(key) && group.collapsible) {
        _expandedGroups[group.keyName] = true;
      }
    }
    setState(() => _selectedKey = key);
  }

  void _toggleGroup(String keyName) {
    setState(() {
      _expandedGroups[keyName] = !(_expandedGroups[keyName] ?? true);
    });
  }

  Future<void> _logoutToLogin() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Deconnexion'),
          content: const Text('Voulez-vous vous deconnecter ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Se deconnecter'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !mounted) {
      return;
    }

    await ref.read(authControllerProvider.notifier).logout();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _showConnectionInfo(AuthUser user, Etablissement? selectedEtablissement) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${_activeEtablissementLabel(selectedEtablissement?.name)}\n${_welcomeConnectedUser(user)}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  void _navigateToShellItem(String key) {
    if (!mounted) {
      return;
    }
    if (_isItemVisibleForRole(key, ref.read(authControllerProvider).value?.role)) {
      _selectItem(key);
      ref.read(adminShellNavigationKeyProvider.notifier).state = key;
    }
  }

  Future<void> _openNotificationsCenter(AuthUser user) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Centre de notifications'),
                subtitle: Text(_welcomeConnectedUser(user)),
              ),
              if (_isItemVisibleForRole('activity_logs', user.role))
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Journal d\'activité'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToShellItem('activity_logs');
                  },
                ),
              if (_isItemVisibleForRole('communication', user.role))
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('Communication'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToShellItem('communication');
                  },
                ),
              if (_isItemVisibleForRole('reports', user.role))
                ListTile(
                  leading: const Icon(Icons.summarize_outlined),
                  title: const Text('Rapports'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToShellItem('reports');
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openInsightsCenter(AuthUser user) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                leading: Icon(Icons.insights_rounded),
                title: Text('Insights & raccourcis'),
                subtitle: Text('Accès rapide aux modules d\'analyse utiles.'),
              ),
              if (_isItemVisibleForRole('reports', user.role))
                ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('Rapports analytiques'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToShellItem('reports');
                  },
                ),
              if (_isItemVisibleForRole('finance', user.role))
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Vue finances'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToShellItem('finance');
                  },
                ),
              if (_isItemVisibleForRole('timetable', user.role))
                ListTile(
                  leading: const Icon(Icons.calendar_month_rounded),
                  title: const Text('Emploi du temps'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToShellItem('timetable');
                  },
                ),
              if (_isItemVisibleForRole('grades', user.role))
                ListTile(
                  leading: const Icon(Icons.auto_stories_outlined),
                  title: const Text('Notes & bulletins'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _navigateToShellItem('grades');
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildGroupedMenu(
    BuildContext context,
    ColorScheme scheme, {
    required bool closeDrawerOnItemTap,
    required String? role,
  }) {
    final widgets = <Widget>[];
    final compact = !closeDrawerOnItemTap && _sidebarCollapsed;

    for (final group in _groups) {
      final visibleKeys = group.itemKeys
          .where((key) => _isItemVisibleForRole(key, role))
          .toList();
      if (visibleKeys.isEmpty) {
        continue;
      }

      final isExpanded = _expandedGroups[group.keyName] ?? true;

      if (compact) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Divider(
              color: Colors.white.withValues(alpha: 0.14),
              height: 1,
            ),
          ),
        );
      } else {
        widgets.add(
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: group.collapsible ? () => _toggleGroup(group.keyName) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      group.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.64),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  if (group.collapsible)
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                ],
              ),
            ),
          ),
        );
      }

      if (!group.collapsible || isExpanded) {
        widgets.addAll(
          visibleKeys.map((key) {
            final item = _items.firstWhere((element) => element.keyName == key);
            final selected = _selectedKey == item.keyName;
            return _SidebarItem(
              icon: item.icon,
              label: _isItemReadOnlyForRole(item.keyName, role)
                  ? '${item.label} (Lecture seule)'
                  : item.label,
              compact: compact,
              selected: selected,
              hovered: _hoveredKey == item.keyName,
              onHoverChanged: (value) {
                if (closeDrawerOnItemTap) {
                  return;
                }
                setState(() => _hoveredKey = value ? item.keyName : null);
              },
              onTap: () {
                _selectItem(item.keyName);
                if (closeDrawerOnItemTap) {
                  Navigator.of(context).pop();
                }
              },
            );
          }),
        );
      }
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).value;
    final pendingShellNavigationKey = ref.watch(adminShellNavigationKeyProvider);
    final etabProvider = ref.watch(etablissementProvider);
    final selectedEtablissement = etabProvider.selected;

    if (pendingShellNavigationKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_isItemVisibleForRole(pendingShellNavigationKey, user?.role)) {
          _selectItem(pendingShellNavigationKey);
        }
        ref.read(adminShellNavigationKeyProvider.notifier).state = null;
      });
    }

    if (!_isItemVisibleForRole(_selectedKey, user?.role)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() => _selectedKey = _firstVisibleKeyForRole(user?.role));
      });
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 900;

    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/login', (route) => false);
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (user.role != 'super_admin') {
      final userEtabId = user.etablissementId;
      if (userEtabId != null && selectedEtablissement?.id != userEtabId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          final concerned = _userEtablissementLabel(user);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Ce compte appartient a "$concerned". Veuillez vous connecter sur cet etablissement.',
                ),
              ),
            );
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        });
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    final selectedItem = _selectedItemForRole(user.role);
    final selectedView = _buildRoleSpecificView(selectedItem, user.role);

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            selectedItem.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              onPressed: () {
                final current = ref.read(themeModeProvider);
                ref
                    .read(themeModeProvider.notifier)
                    .state = current == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
              },
              icon: const Icon(Icons.dark_mode_outlined),
            ),
            IconButton(
              tooltip: 'Informations session',
              onPressed: () => _showConnectionInfo(user, selectedEtablissement),
              icon: const Icon(Icons.info_outline_rounded),
            ),
            IconButton(
              onPressed: _logoutToLogin,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          selectedEtablissement?.name ?? SchoolBranding.appName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.3,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: _buildGroupedMenu(
                      context,
                      scheme,
                      closeDrawerOnItemTap: true,
                      role: user.role,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: _GlobalFeatureRefreshHost(
            key: ValueKey('admin-mobile-${selectedItem.keyName}'),
            child: selectedView,
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: _sidebarCollapsed ? 96 : 292,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0B1222),
                  Color(0xFF121C34),
                  Color(0xFF17233D),
                ],
              ),
              border: Border(
                right: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                  blurRadius: 30,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 16, 12, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        if (!_sidebarCollapsed) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedEtablissement?.name ??
                                  SchoolBranding.appName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                    color: Colors.white,
                                  ),
                            ),
                          ),
                        ],
                        IconButton(
                          tooltip: _sidebarCollapsed ? 'Développer' : 'Réduire',
                          onPressed: () => setState(
                            () => _sidebarCollapsed = !_sidebarCollapsed,
                          ),
                          icon: Icon(
                            _sidebarCollapsed
                                ? Icons.keyboard_double_arrow_right_rounded
                                : Icons.keyboard_double_arrow_left_rounded,
                            color: Colors.white.withValues(alpha: 0.82),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      children: _buildGroupedMenu(
                        context,
                        scheme,
                        closeDrawerOnItemTap: false,
                        role: user.role,
                      ),
                    ),
                  ),
                  if (!_sidebarCollapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: const Color(
                                0xFF8B5CF6,
                              ).withValues(alpha: 0.35),
                              child: Text(
                                _connectedRoleLabel(user.role).substring(0, 1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _connectedRoleLabel(user.role),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  Text(
                                    user.username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.66,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0F172A),
                          Color(0xFF131F35),
                          Color(0xFF1E293B),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -120,
                  right: -80,
                  child: IgnorePointer(
                    child: Container(
                      width: 340,
                      height: 340,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        selectedEtablissement?.name ??
                            SchoolBranding.schoolName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 12,
                              color: Colors.white.withValues(alpha: 0.03),
                            ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                10,
                                10,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.1),
                                    Colors.white.withValues(alpha: 0.05),
                                  ],
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_activeEtablissementLabel(selectedEtablissement?.name)}  |  ${_welcomeConnectedUser(user)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _TopBarIconBubble(
                                    icon: Icons.notifications_none_rounded,
                                    tooltip: 'Notifications',
                                    onTap: () => _openNotificationsCenter(user),
                                  ),
                                  const SizedBox(width: 8),
                                  _TopBarIconBubble(
                                    icon: Icons.mail_outline_rounded,
                                    tooltip: 'Messages',
                                    badge: _chatUnread,
                                    onTap: _openChatPanel,
                                  ),
                                  const SizedBox(width: 8),
                                  _TopBarIconBubble(
                                    icon: Icons.insights_rounded,
                                    tooltip: 'Insights',
                                    onTap: () => _openInsightsCenter(user),
                                  ),
                                  const SizedBox(width: 10),
                                  Tooltip(
                                    message:
                                        'Compte connecte (cliquer pour se deconnecter)',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(999),
                                      onTap: _logoutToLogin,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          5,
                                          10,
                                          5,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          color: Colors.white.withValues(
                                            alpha: 0.1,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 15,
                                              backgroundColor: const Color(
                                                0xFF8B5CF6,
                                              ).withValues(alpha: 0.42),
                                              child: Text(
                                                user.username.isNotEmpty
                                                    ? user.username[0]
                                                          .toUpperCase()
                                                    : 'U',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              color: Colors.white.withValues(
                                                alpha: 0.84,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton.filledTonal(
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                    ),
                                    tooltip: 'Paramètres de thème',
                                    onPressed: () {
                                      final current = ref.read(
                                        themeModeProvider,
                                      );
                                      ref
                                          .read(themeModeProvider.notifier)
                                          .state = current == ThemeMode.dark
                                          ? ThemeMode.light
                                          : ThemeMode.dark;
                                    },
                                    icon: const Icon(Icons.settings_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: _GlobalFeatureRefreshHost(
                            key: ValueKey(
                              'admin-desktop-${selectedItem.keyName}',
                            ),
                            child: selectedView,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _welcomeConnectedUser(AuthUser? user) {
    final roleLabel = _connectedRoleLabel(user?.role);
    final identifier = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim()
        : ((user?.username.trim().isNotEmpty ?? false)
              ? user!.username.trim()
              : 'Utilisateur');

    return 'Utilisateur connecté: $roleLabel ($identifier)';
  }

  String _activeEtablissementLabel(String? etablissementName) {
    final label =
        (etablissementName != null && etablissementName.trim().isNotEmpty)
        ? etablissementName.trim()
        : 'Non défini';
    return 'Etablissement actif: $label';
  }

  String _userEtablissementLabel(AuthUser user) {
    final name = user.etablissementName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final id = user.etablissementId;
    if (id != null) {
      return 'Etablissement #$id';
    }
    return 'etablissement associe a votre compte';
  }

  String _connectedRoleLabel(String? role) {
    switch (role) {
      case 'super_admin':
        return 'Admin';
      case 'director':
        return 'Directeur';
      case 'accountant':
        return 'Comptable';
      case 'teacher':
        return 'Enseignant';
      case 'supervisor':
        return 'Surveillant';
      case 'parent':
        return 'Parent';
      case 'student':
        return 'Élève';
      default:
        return 'Utilisateur';
    }
  }
}

class _TopBarIconBubble extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int badge;
  final String? tooltip;

  const _TopBarIconBubble({
    required this.icon,
    this.onTap,
    this.badge = 0,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withValues(alpha: 0.1),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Center(
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminMenuItem {
  final String keyName;
  final String label;
  final IconData icon;
  final Widget view;

  const _AdminMenuItem({
    required this.keyName,
    required this.label,
    required this.icon,
    required this.view,
  });
}

class _AdminMenuGroup {
  final String keyName;
  final String title;
  final List<String> itemKeys;
  final bool collapsible;

  const _AdminMenuGroup({
    required this.keyName,
    required this.title,
    required this.itemKeys,
    this.collapsible = false,
  });
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;
  final bool selected;
  final bool hovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.compact,
    required this.selected,
    required this.hovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = selected || hovered;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: selected
            ? const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              )
            : null,
        color: selected
            ? null
            : Colors.white.withValues(alpha: isActive ? 0.1 : 0.04),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: isActive ? 0.14 : 0.08),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.32),
                  blurRadius: 20,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: selected ? Colors.white : Colors.transparent,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.8),
                        blurRadius: 10,
                        spreadRadius: 0.5,
                      ),
                    ]
                  : null,
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Icon(
            icon,
            size: 20,
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: isActive ? 0.95 : 0.72),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: isActive ? 0.95 : 0.72),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final interactiveChild = MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(onTap: onTap, child: child),
    );

    if (!compact) {
      return interactiveChild;
    }
    return Tooltip(message: label, child: interactiveChild);
  }
}

