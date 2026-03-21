import 'models/etablissement.dart';
import 'screens/etablissement_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/branding.dart';
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
import 'features/grades/presentation/grades_page.dart';
import 'features/library/presentation/library_page.dart';
import 'features/payments/presentation/payments_controller.dart';
import 'features/payments/presentation/payments_page.dart';
import 'features/reports/presentation/reports_page.dart';
import 'features/stock/presentation/stock_page.dart';
import 'features/students/presentation/students_controller.dart';
import 'features/students/presentation/students_page.dart';
import 'features/teachers/presentation/teachers_page.dart';
import 'features/timetable/presentation/timetable_page.dart';
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
        '/': (_) => const LoginPage(),
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
  final List<Tab> tabs;
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
    final etabName = etabProvider.selected?.name;
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.school, size: 18),
                      const SizedBox(width: 4),
                      Text(etabName, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                ).pushNamedAndRemoveUntil('/', (route) => false);
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
                      SchoolBranding.schoolName,
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
      view: TimetablePage(),
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
        'academics',
        'grades',
        'attendance',
        'teacher_attendance',
        'discipline',
        'exams',
        'timetable',
      ],
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
      itemKeys: ['users', 'communication', 'reports', 'activity_logs'],
      collapsible: true,
    ),
    _AdminMenuGroup(
      keyName: 'ressources',
      title: 'Ressources',
      itemKeys: ['library', 'canteen', 'stock'],
      collapsible: true,
    ),
  ];

  _AdminMenuItem get _selectedItem =>
      _items.firstWhere((item) => item.keyName == _selectedKey);

  @override
  void initState() {
    super.initState();
    for (final group in _groups) {
      if (group.collapsible) {
        _expandedGroups[group.keyName] = true;
      }
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

  List<Widget> _buildGroupedMenu(
    BuildContext context,
    ColorScheme scheme, {
    required bool closeDrawerOnItemTap,
  }) {
    final widgets = <Widget>[];

    for (final group in _groups) {
      final isExpanded = _expandedGroups[group.keyName] ?? true;

      if (group.collapsible) {
        widgets.add(
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            title: Text(
              group.title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
            ),
            onTap: () => _toggleGroup(group.keyName),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }

      if (!group.collapsible || isExpanded) {
        widgets.addAll(
          group.itemKeys.map((key) {
            final item = _items.firstWhere((element) => element.keyName == key);
            final selected = _selectedKey == item.keyName;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                selected: selected,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                selectedTileColor: scheme.primary.withValues(alpha: 0.18),
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () {
                  _selectItem(item.keyName);
                  if (closeDrawerOnItemTap) {
                    Navigator.of(context).pop();
                  }
                },
              ),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 900;

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_selectedItem.label),
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
                  child: Text(
                    _welcomeConnectedUser(user),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (!context.mounted) {
                  return;
                }
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/', (route) => false);
              },
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
                        SchoolBranding.appName,
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
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: _GlobalFeatureRefreshHost(
            key: ValueKey('admin-mobile-${_selectedItem.keyName}'),
            child: _selectedItem.view,
          ),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 280,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.22),
              border: Border(
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          SchoolBranding.appName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      children: _buildGroupedMenu(
                        context,
                        scheme,
                        closeDrawerOnItemTap: false,
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
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.surface,
                          scheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        SchoolBranding.schoolName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displayMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 12,
                              color: scheme.primary.withValues(alpha: 0.04),
                            ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            const Spacer(),
                            FilledButton.tonal(
                              onPressed: () {
                                final current = ref.read(themeModeProvider);
                                ref
                                    .read(themeModeProvider.notifier)
                                    .state = current == ThemeMode.dark
                                    ? ThemeMode.light
                                    : ThemeMode.dark;
                              },
                              child: const Icon(Icons.dark_mode_outlined),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                              child: Text(
                                _welcomeConnectedUser(user),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.tonal(
                              onPressed: () async {
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .logout();
                                if (!context.mounted) {
                                  return;
                                }
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/',
                                  (route) => false,
                                );
                              },
                              child: const Icon(Icons.logout),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: _GlobalFeatureRefreshHost(
                            key: ValueKey(
                              'admin-desktop-${_selectedItem.keyName}',
                            ),
                            child: _selectedItem.view,
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
    final fullName = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName.trim()
        : (user?.username ?? 'Utilisateur');

    return 'Bienvenue, $roleLabel $fullName';
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
    return RequireEtablissementSelection(
      child: const _RoleShell(
        title: '${SchoolBranding.appName} - Enseignant',
        tabs: [
          Tab(text: 'Dashboard'),
          Tab(text: 'Élèves'),
          Tab(text: 'Absences'),
          Tab(text: 'Examens'),
          Tab(text: 'Rapports'),
        ],
        views: [
          DashboardPage(),
          StudentsPage(),
          AttendancePage(),
          ExamsPage(),
          ReportsPage(),
        ],
      ),
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
