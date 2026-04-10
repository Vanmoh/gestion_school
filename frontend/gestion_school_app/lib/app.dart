import 'dart:ui' as ui;

import 'models/etablissement.dart';
import 'screens/etablissement_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/branding.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/attendance/presentation/attendance_controller.dart';
import 'features/attendance/presentation/attendance_page.dart';
import 'features/attendance/presentation/teacher_attendance_page.dart';
import 'features/academics/presentation/academics_page.dart';
import 'features/activity_logs/presentation/activity_logs_page.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/auth/domain/auth_user.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/canteen/presentation/canteen_page.dart';
import 'features/dashboard/presentation/dashboard_controller.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
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
        '/home/accountant': (_) => const _AccountantShell(),
        '/home/teacher': (_) => const _TeacherShell(),
        '/home/supervisor': (_) => const _SupervisorShell(),
        '/home/parent': (_) => const _ParentStudentShell(roleLabel: 'Parent'),
        '/home/student': (_) => const _ParentStudentShell(roleLabel: 'Élève'),
        '/attendance': (_) =>
            const _GlobalFeatureRefreshHost(child: AttendancePage()),
        '/exams': (_) => const _GlobalFeatureRefreshHost(child: ExamsPage()),
        '/students': (_) =>
            const _GlobalFeatureRefreshHost(child: StudentsPage()),
        '/payments': (_) =>
            const _GlobalFeatureRefreshHost(child: PaymentsPage()),
        '/reports': (_) =>
            const _GlobalFeatureRefreshHost(child: ReportsPage()),
        '/users': (_) => const _GlobalFeatureRefreshHost(child: UsersPage()),
      },
    );
  }
}

class _RoleShell extends ConsumerWidget {
  final List<Widget> tabs;
  final List<Widget> views;
  final String title;

  const _RoleShell({
    required this.tabs,
    required this.views,
    required this.title,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final watermarkSize = (screenWidth * 0.095).clamp(34.0, 92.0).toDouble();

    final etabProvider = ref.watch(etablissementProvider);
    final authUser = ref.watch(authControllerProvider).value;

    if (authUser != null && authUser.role != 'super_admin') {
      final userEtabId = authUser.etablissementId;
      if (userEtabId != null && etabProvider.selected?.id != userEtabId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final provider = ref.read(etablissementProvider);
          final candidates = provider.etablissements
              .where((item) => item.id == userEtabId)
              .toList();
          final target = candidates.isNotEmpty
              ? candidates.first
              : Etablissement(
                  id: userEtabId,
                  name: authUser.etablissementName.isNotEmpty
                      ? authUser.etablissementName
                      : 'Etablissement #$userEtabId',
                );
          provider.selectEtablissement(target);
        });
      }
    }

    final etabName = etabProvider.selected?.name ?? authUser?.etablissementName;
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(title),
              if (etabName != null) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.school, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        etabName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
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
              icon: const Icon(Icons.dark_mode),
            ),
            IconButton(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (!context.mounted) {
                  return;
                }
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              },
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.surface,
                      scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: Transform.rotate(
                    angle: -0.08,
                    child: Text(
                      etabName ?? SchoolBranding.schoolName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium
                          ?.copyWith(
                            fontSize: watermarkSize,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 12,
                            color: scheme.primary.withValues(alpha: 0.045),
                          ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: TabBarView(
                children: views
                    .map((view) => _GlobalFeatureRefreshHost(child: view))
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminShell extends ConsumerStatefulWidget {
  const _AdminShell();

  @override
  ConsumerState<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<_AdminShell> {
  String _selectedKey = 'dashboard';
  final Map<String, bool> _expandedGroups = {};
  bool _sidebarCollapsed = false;
  String? _hoveredKey;

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
        'discipline',
      ],
      collapsible: true,
    ),
    _AdminMenuGroup(
      keyName: 'academique',
      title: 'Académique',
      itemKeys: ['academics', 'grades', 'exams', 'timetable'],
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
    if (key == 'etablissements') {
      return role == 'super_admin';
    }
    return true;
  }

  _AdminMenuItem _selectedItemForRole(String? role) {
    final isVisible = _isItemVisibleForRole(_selectedKey, role);
    final targetKey = isVisible ? _selectedKey : 'dashboard';
    return _items.firstWhere((item) => item.keyName == targetKey);
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
  }

  Future<void> _warmUpAdminData() async {
    try {
      await Future.wait<void>([
        ref.read(dashboardStatsProvider.future).then((_) {}),
        ref.read(studentsProvider.future).then((_) {}),
        ref.read(usersProvider.future).then((_) {}),
        ref.read(paymentsProvider.future).then((_) {}),
      ]);
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

  List<Widget> _buildGroupedMenu(
    BuildContext context,
    ColorScheme scheme, {
    required bool closeDrawerOnItemTap,
    required String? role,
  }) {
    final widgets = <Widget>[];
    final compact = !closeDrawerOnItemTap && _sidebarCollapsed;

    for (final group in _groups) {
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
        final visibleKeys = group.itemKeys
            .where((key) => _isItemVisibleForRole(key, role))
            .toList();
        if (visibleKeys.isEmpty) {
          continue;
        }
        widgets.addAll(
          visibleKeys.map((key) {
            final item = _items.firstWhere((element) => element.keyName == key);
            final selected = _selectedKey == item.keyName;
            return _SidebarItem(
              icon: item.icon,
              label: item.label,
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
    final etabProvider = ref.watch(etablissementProvider);
    final selectedEtablissement = etabProvider.selected;
    if (!_isItemVisibleForRole(_selectedKey, user?.role)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        setState(() => _selectedKey = 'dashboard');
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
          final provider = ref.read(etablissementProvider);
          final candidates = provider.etablissements
              .where((item) => item.id == userEtabId)
              .toList();
          final target = candidates.isNotEmpty
              ? candidates.first
              : Etablissement(
                  id: userEtabId,
                  name: user.etablissementName.isNotEmpty
                      ? user.etablissementName
                      : 'Etablissement #$userEtabId',
                );
          provider.selectEtablissement(target);
        });
      }
    }

    final selectedItem = _selectedItemForRole(user.role);

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(selectedItem.label),
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
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 230,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _activeEtablissementLabel(selectedEtablissement?.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      Text(
                        _welcomeConnectedUser(user),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
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
                      Text(
                        selectedEtablissement?.name ?? SchoolBranding.appName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3,
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
            child: selectedItem.view,
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
                                  const _TopBarIconBubble(
                                    icon: Icons.notifications_none_rounded,
                                  ),
                                  const SizedBox(width: 8),
                                  const _TopBarIconBubble(
                                    icon: Icons.mail_outline_rounded,
                                  ),
                                  const SizedBox(width: 8),
                                  const _TopBarIconBubble(
                                    icon: Icons.insights_rounded,
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
                            child: selectedItem.view,
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
    final identifier = (user?.username.trim().isNotEmpty ?? false)
        ? user!.username.trim()
        : ((user?.fullName.trim().isNotEmpty ?? false)
              ? user!.fullName.trim()
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

  String _connectedRoleLabel(String? role) {
    switch (role) {
      case 'super_admin':
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

  const _TopBarIconBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
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

class _AccountantShell extends ConsumerWidget {
  const _AccountantShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RequireEtablissementSelection(
      child: const _RoleShell(
        title: '${SchoolBranding.appName} - Comptabilité',
        tabs: [
          Tab(text: 'Dashboard'),
          Tab(text: 'Absences'),
          Tab(text: 'Examens'),
          Tab(text: 'Paiements'),
          Tab(text: 'Rapports'),
        ],
        views: [
          DashboardPage(),
          AttendancePage(),
          ExamsPage(),
          PaymentsPage(),
          ReportsPage(),
        ],
      ),
    );
  }
}

class _TeacherShell extends ConsumerWidget {
  const _TeacherShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const RequireEtablissementSelection(child: _TeacherShellTabs());
  }
}

class _TeacherShellTabs extends ConsumerStatefulWidget {
  const _TeacherShellTabs();

  @override
  ConsumerState<_TeacherShellTabs> createState() => _TeacherShellTabsState();
}

class _TeacherShellTabsState extends ConsumerState<_TeacherShellTabs> {
  int _gradesBadge = 0;
  int _timetableBadge = 0;
  int _disciplineBadge = 0;
  bool _badgesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTeacherBadges();
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

  Future<void> _loadTeacherBadges() async {
    try {
      final authUser = ref.read(authControllerProvider).value;
      if (authUser == null || authUser.role != 'teacher') {
        return;
      }

      final dio = ref.read(dioProvider);
      final responses = await Future.wait([
        dio.get('/teachers/'),
        dio.get('/teacher-assignments/'),
        dio.get('/teacher-schedule-slots/'),
        dio.get('/students/'),
        dio.get('/discipline-incidents/'),
      ]);

      if (!mounted) return;

      final teachers = _extractRows(responses[0].data);
      final assignments = _extractRows(responses[1].data);
      final slots = _extractRows(responses[2].data);
      final students = _extractRows(responses[3].data);
      final incidents = _extractRows(responses[4].data);

      final teacherProfile = teachers.firstWhere(
        (row) => _asInt(row['user']) == authUser.id,
        orElse: () => <String, dynamic>{},
      );
      final teacherId = _asInt(teacherProfile['id']);
      if (teacherId <= 0) {
        setState(() => _badgesLoaded = true);
        return;
      }

      final ownAssignments = assignments
          .where((row) => _asInt(row['teacher']) == teacherId)
          .toList();
      final ownAssignmentIds = ownAssignments
          .map((row) => _asInt(row['id']))
          .where((id) => id > 0)
          .toSet();
      final ownClassroomIds = ownAssignments
          .map((row) => _asInt(row['classroom']))
          .where((id) => id > 0)
          .toSet();

      final ownStudentIds = students
          .where((row) => ownClassroomIds.contains(_asInt(row['classroom'])))
          .map((row) => _asInt(row['id']))
          .where((id) => id > 0)
          .toSet();

      final ownOpenIncidents = incidents
          .where(
            (row) =>
                ownStudentIds.contains(_asInt(row['student'])) &&
                (row['status']?.toString() ?? 'open') == 'open',
          )
          .length;

      final ownSlots = slots
          .where((row) => ownAssignmentIds.contains(_asInt(row['assignment'])))
          .length;

      setState(() {
        _gradesBadge = ownAssignments.length;
        _timetableBadge = ownSlots;
        _disciplineBadge = ownOpenIncidents;
        _badgesLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _badgesLoaded = true);
    }
  }

  Widget _tabLabel(String label, int? badge) {
    final showBadge = badge != null && badge > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (showBadge) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF1E40AF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$badge',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RoleShell(
      title: '${SchoolBranding.appName} - Enseignant',
      tabs: [
        Tab(
          child: _tabLabel(
            'Notes & Bulletin',
            _badgesLoaded ? _gradesBadge : null,
          ),
        ),
        Tab(
          child: _tabLabel(
            'Emploi du temps',
            _badgesLoaded ? _timetableBadge : null,
          ),
        ),
        Tab(
          child: _tabLabel(
            'Discipline',
            _badgesLoaded ? _disciplineBadge : null,
          ),
        ),
      ],
      views: const [GradesPage(), TimetableModulePage(), DisciplinePage()],
    );
  }
}

class _SupervisorShell extends ConsumerWidget {
  const _SupervisorShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RequireEtablissementSelection(
      child: const _RoleShell(
        title: '${SchoolBranding.appName} - Surveillant',
        tabs: [
          Tab(text: 'Dashboard'),
          Tab(text: 'Élèves'),
          Tab(text: 'Absences'),
        ],
        views: [DashboardPage(), StudentsPage(), AttendancePage()],
      ),
    );
  }
}

class _ParentStudentShell extends ConsumerWidget {
  final String roleLabel;

  const _ParentStudentShell({required this.roleLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RequireEtablissementSelection(
      child: _RoleShell(
        title: '${SchoolBranding.appName} - $roleLabel',
        tabs: const [Tab(text: 'Rapports')],
        views: const [ReportsPage()],
      ),
    );
  }
}
