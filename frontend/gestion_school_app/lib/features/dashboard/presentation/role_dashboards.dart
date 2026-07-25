import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/navigation_intents.dart';
import '../../auth/presentation/auth_controller.dart';
import 'dashboard_shared_ui.dart';

List<Map<String, dynamic>> _rows(dynamic data) {
  if (data is Map<String, dynamic> && data['results'] is List) {
    return (data['results'] as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
  if (data is List) {
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _FetchRowsResult {
  final List<Map<String, dynamic>> rows;
  final bool restricted;

  const _FetchRowsResult({required this.rows, required this.restricted});
}

Future<_FetchRowsResult> _safeGetRows(Dio dio, String path) async {
  try {
    final response = await dio.get(path);
    return _FetchRowsResult(rows: _rows(response.data), restricted: false);
  } on DioException catch (error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const _FetchRowsResult(
        rows: <Map<String, dynamic>>[],
        restricted: true,
      );
    }
    return const _FetchRowsResult(
      rows: <Map<String, dynamic>>[],
      restricted: false,
    );
  } catch (_) {
    return const _FetchRowsResult(rows: <Map<String, dynamic>>[], restricted: false);
  }
}

class _RoleMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _RoleMetric({
    required this.label,
    required this.value,
    this.icon = Icons.insights_outlined,
    this.color = const Color(0xFF5B8CFF),
  });
}

class _RoleInsight {
  final String title;
  final String detail;
  final Color tone;

  const _RoleInsight({
    required this.title,
    required this.detail,
    required this.tone,
  });
}

enum _RoleQuickAction {
  attendance,
  discipline,
  students,
  teacherAttendance,
  teacherTimesheet,
  timetable,
  reports,
  finance,
  newPayment,
  grades,
}

class _RoleQuickActionMeta {
  final String label;
  final IconData icon;

  const _RoleQuickActionMeta({required this.label, required this.icon});
}

_RoleQuickActionMeta _roleQuickActionMeta(_RoleQuickAction action) {
  switch (action) {
    case _RoleQuickAction.attendance:
      return const _RoleQuickActionMeta(
        label: 'Absences',
        icon: Icons.event_busy_outlined,
      );
    case _RoleQuickAction.discipline:
      return const _RoleQuickActionMeta(
        label: 'Discipline',
        icon: Icons.gavel_rounded,
      );
    case _RoleQuickAction.students:
      return const _RoleQuickActionMeta(
        label: 'Élèves',
        icon: Icons.groups_rounded,
      );
    case _RoleQuickAction.teacherAttendance:
      return const _RoleQuickActionMeta(
        label: 'Absences enseignants',
        icon: Icons.assignment_ind_outlined,
      );
    case _RoleQuickAction.teacherTimesheet:
      return const _RoleQuickActionMeta(
        label: 'Émargement',
        icon: Icons.punch_clock_rounded,
      );
    case _RoleQuickAction.timetable:
      return const _RoleQuickActionMeta(
        label: 'Emploi du temps',
        icon: Icons.schedule_rounded,
      );
    case _RoleQuickAction.reports:
      return const _RoleQuickActionMeta(
        label: 'Rapports',
        icon: Icons.assessment_outlined,
      );
    case _RoleQuickAction.finance:
      return const _RoleQuickActionMeta(
        label: 'Finances',
        icon: Icons.account_balance_wallet_outlined,
      );
    case _RoleQuickAction.newPayment:
      return const _RoleQuickActionMeta(
        label: 'Encaisser',
        icon: Icons.point_of_sale_rounded,
      );
    case _RoleQuickAction.grades:
      return const _RoleQuickActionMeta(
        label: 'Notes',
        icon: Icons.fact_check_outlined,
      );
  }
}

void _navigateToRoleShellItem(WidgetRef ref, String key) {
  ref.read(adminShellNavigationKeyProvider.notifier).state = key;
}

void _handleRoleQuickAction(WidgetRef ref, _RoleQuickAction action) {
  switch (action) {
    case _RoleQuickAction.attendance:
      _navigateToRoleShellItem(ref, 'attendance');
      return;
    case _RoleQuickAction.discipline:
      _navigateToRoleShellItem(ref, 'discipline');
      return;
    case _RoleQuickAction.students:
      _navigateToRoleShellItem(ref, 'students');
      return;
    case _RoleQuickAction.teacherAttendance:
      _navigateToRoleShellItem(ref, 'teacher_attendance');
      return;
    case _RoleQuickAction.teacherTimesheet:
      _navigateToRoleShellItem(ref, 'teacher_timesheet');
      return;
    case _RoleQuickAction.timetable:
      _navigateToRoleShellItem(ref, 'timetable');
      return;
    case _RoleQuickAction.reports:
      _navigateToRoleShellItem(ref, 'reports');
      return;
    case _RoleQuickAction.finance:
      _navigateToRoleShellItem(ref, 'finance');
      return;
    case _RoleQuickAction.newPayment:
      ref.read(financeOpenGuidedPaymentIntentProvider.notifier).state = true;
      _navigateToRoleShellItem(ref, 'finance');
      return;
    case _RoleQuickAction.grades:
      _navigateToRoleShellItem(ref, 'grades');
      return;
  }
}

double _metricNumber(String raw) {
  final normalized = raw
      .replaceAll(',', '.')
      .replaceAll(RegExp(r'[^0-9.-]'), '');
  return double.tryParse(normalized) ?? 0;
}

List<FlSpot> _toTrendSpots(List<_RoleMetric> metrics) {
  if (metrics.isEmpty) {
    return const [FlSpot(0, 0), FlSpot(1, 0)];
  }
  final values = metrics
      .map((m) => _metricNumber(m.value).abs())
      .toList(growable: false);
  final maxValue = values.fold<double>(1, (maxSoFar, v) => math.max(maxSoFar, v));
  return List<FlSpot>.generate(values.length, (index) {
    final normalized = (values[index] / maxValue) * 100;
    return FlSpot(index.toDouble(), normalized);
  });
}

List<_RoleInsight> _buildAutoInsights(List<_RoleMetric> metrics) {
  if (metrics.isEmpty) {
    return const <_RoleInsight>[];
  }

  final parsed = metrics
      .map((metric) => (metric: metric, value: _metricNumber(metric.value).abs()))
      .toList(growable: false);

  parsed.sort((a, b) => b.value.compareTo(a.value));

  final strongest = parsed.first;
  final weakest = parsed.length > 1 ? parsed.last : parsed.first;
  final avg = parsed.fold<double>(0, (sum, row) => sum + row.value) / parsed.length;

  return [
    _RoleInsight(
      title: 'Point fort du moment',
      detail:
          '${strongest.metric.label} domine actuellement avec ${strongest.metric.value}.',
      tone: const Color(0xFF34D399),
    ),
    _RoleInsight(
      title: 'Zone à surveiller',
      detail:
          '${weakest.metric.label} reste le signal le plus faible (${weakest.metric.value}).',
      tone: const Color(0xFFF59E0B),
    ),
    _RoleInsight(
      title: 'Lecture globale',
      detail:
          'Niveau moyen observé: ${avg.toStringAsFixed(1)} (indice relatif des indicateurs).',
      tone: const Color(0xFF60A5FA),
    ),
  ];
}

class _RoleDashboardScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_RoleMetric> metrics;
  final Future<void> Function() onRefresh;
  final List<String> responsibilities;
  final List<_RoleQuickAction> quickActions;
  final ValueChanged<_RoleQuickAction>? onQuickActionSelected;
  final String? fallbackNote;

  const _RoleDashboardScaffold({
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.onRefresh,
    this.responsibilities = const <String>[],
    this.quickActions = const <_RoleQuickAction>[],
    this.onQuickActionSelected,
    this.fallbackNote,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1450
        ? 4
        : width >= 1100
        ? 3
        : width >= 760
        ? 2
        : 1;
    final chartSpots = _toTrendSpots(metrics);
    final insights = _buildAutoInsights(metrics);

    return Stack(
      children: [
        const Positioned.fill(child: IgnorePointer(child: SharedDashboardBackdrop())),
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            _RoleHeroCard(title: title, subtitle: subtitle, onRefresh: onRefresh),
            if (responsibilities.isNotEmpty) ...[
              const SizedBox(height: 10),
              _RoleResponsibilitiesPanel(items: responsibilities),
            ],
            if (quickActions.isNotEmpty && onQuickActionSelected != null) ...[
              const SizedBox(height: 10),
              _RoleQuickActionsPanel(
                actions: quickActions,
                onSelected: onQuickActionSelected!,
              ),
            ],
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metrics.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: columns == 1 ? 3.2 : 2.05,
              ),
              itemBuilder: (_, index) => _RoleMetricCard(
                metric: metrics[index],
                index: index,
                seed: _metricNumber(metrics[index].value),
              ),
            ),
            const SizedBox(height: 12),
            _RoleTrendPanel(metrics: metrics, spots: chartSpots),
            const SizedBox(height: 12),
            _RoleInsightsPanel(insights: insights),
            if (fallbackNote != null) ...[
              const SizedBox(height: 10),
              Text(
                fallbackNote!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.84),
                    ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RoleResponsibilitiesPanel extends StatelessWidget {
  final List<String> items;

  const _RoleResponsibilitiesPanel({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ce que vous pouvez faire',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withValues(alpha: 0.08),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleQuickActionsPanel extends StatelessWidget {
  final List<_RoleQuickAction> actions;
  final ValueChanged<_RoleQuickAction> onSelected;

  const _RoleQuickActionsPanel({
    required this.actions,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final action in actions)
          OutlinedButton.icon(
            onPressed: () => onSelected(action),
            icon: Icon(_roleQuickActionMeta(action).icon, size: 16),
            label: Text(_roleQuickActionMeta(action).label),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
      ],
    );
  }
}

class _RoleHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;

  const _RoleHeroCard({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardGlassCard(
      borderRadius: BorderRadius.circular(22),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRefresh,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5B8CFF).withValues(alpha: 0.88),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Actualiser'),
          ),
        ],
      ),
    );
  }
}

class _RoleMetricCard extends StatelessWidget {
  final _RoleMetric metric;
  final int index;
  final double seed;

  const _RoleMetricCard({
    required this.metric,
    required this.index,
    required this.seed,
  });

  List<FlSpot> _sparkline() {
    final base = seed.abs().clamp(1, 999999).toDouble();
    return List<FlSpot>.generate(7, (i) {
      final wave = math.sin((i + index + 1) * 0.78) * 10;
      final drift = (i * (index.isEven ? 1.8 : -1.4));
      return FlSpot(i.toDouble(), (base % 100) + wave + drift + 20);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sparklineColor = metric.color.withValues(alpha: 0.95);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: metric.color.withValues(alpha: 0.24),
                ),
                child: Icon(metric.icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            metric.value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _sparkline(),
                    isCurved: true,
                    color: sparklineColor,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: sparklineColor.withValues(alpha: 0.16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTrendPanel extends StatelessWidget {
  final List<_RoleMetric> metrics;
  final List<FlSpot> spots;

  const _RoleTrendPanel({required this.metrics, required this.spots});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tendance opérationnelle',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            'Projection visuelle des indicateurs clés du rôle.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 30,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= metrics.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    left: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    right: BorderSide.none,
                    top: BorderSide.none,
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    barWidth: 3,
                    color: const Color(0xFF5B8CFF),
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                        radius: 3,
                        color: const Color(0xFF7CD7FF),
                        strokeColor: Colors.white,
                        strokeWidth: 1,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF5B8CFF).withValues(alpha: 0.3),
                          const Color(0xFF5B8CFF).withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleInsightsPanel extends StatelessWidget {
  final List<_RoleInsight> insights;

  const _RoleInsightsPanel({required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Insights automatiques',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ...insights.map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: insight.tone.withValues(alpha: 0.18),
                  border: Border.all(color: insight.tone.withValues(alpha: 0.42)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      insight.detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SupervisorDashboardPage extends ConsumerStatefulWidget {
  const SupervisorDashboardPage({super.key});

  @override
  ConsumerState<SupervisorDashboardPage> createState() => _SupervisorDashboardPageState();
}

class _SupervisorDashboardPageState extends ConsumerState<SupervisorDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _students = 0;
  int _attendances = 0;
  int _incidentsOpen = 0;
  int _attendanceToday = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/students/'),
      _safeGetRows(dio, '/attendances/'),
      _safeGetRows(dio, '/discipline-incidents/'),
    ]);

    if (!mounted) return;
    setState(() {
      _students = results[0].rows.length;
      _attendances = results[1].rows.length;
      _incidentsOpen = results[2]
          .rows
          .where((row) => (row['status']?.toString() ?? 'open') == 'open')
          .length;
        final today = DateTime.now();
        final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        _attendanceToday = results[1]
          .rows
          .where((row) => (row['date']?.toString() ?? '') == todayStr)
          .length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Tableau de bord Surveillant',
      subtitle: 'Suivi ciblé assiduité, retards, absences et discipline.',
      responsibilities: const [
        'Suivre les absences et retards',
        'Gérer les incidents disciplinaires',
        'Contrôler l\'assiduité quotidienne',
      ],
      quickActions: const [
        _RoleQuickAction.attendance,
        _RoleQuickAction.discipline,
        _RoleQuickAction.reports,
      ],
      onQuickActionSelected: (action) => _handleRoleQuickAction(ref, action),
      metrics: [
        _RoleMetric(
          label: 'Élèves suivis',
          value: '$_students',
          icon: Icons.groups_rounded,
          color: const Color(0xFF2CC2FF),
        ),
        _RoleMetric(
          label: 'Absences et retards',
          value: '$_attendances',
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF8FA7FF),
        ),
        _RoleMetric(
          label: 'Pointages élèves (jour)',
          value: '$_attendanceToday',
          icon: Icons.today_rounded,
          color: const Color(0xFF5B8CFF),
        ),
        _RoleMetric(
          label: 'Incidents ouverts',
          value: '$_incidentsOpen',
          icon: Icons.gpp_maybe_outlined,
          color: const Color(0xFFFF8C61),
        ),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class CensorDashboardPage extends ConsumerStatefulWidget {
  const CensorDashboardPage({super.key});

  @override
  ConsumerState<CensorDashboardPage> createState() => _CensorDashboardPageState();
}

class _CensorDashboardPageState extends ConsumerState<CensorDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _students = 0;
  int _attendances = 0;
  int _incidentsOpen = 0;
  int _teacherEntries = 0;
  int _timetableSlots = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/students/'),
      _safeGetRows(dio, '/attendances/'),
      _safeGetRows(dio, '/discipline-incidents/'),
      _safeGetRows(dio, '/teacher-time-entries/'),
      _safeGetRows(dio, '/teacher-schedule-slots/'),
    ]);

    if (!mounted) return;
    setState(() {
      _students = results[0].rows.length;
      _attendances = results[1].rows.length;
      _incidentsOpen = results[2]
          .rows
          .where((row) => (row['status']?.toString() ?? 'open') == 'open')
          .length;
      _teacherEntries = results[3].rows.length;
      _timetableSlots = results[4].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Tableau de bord Censeur',
      subtitle: 'Pilotage pédagogique: élèves, discipline, pointages et planning.',
      responsibilities: const [
        'Piloter le suivi pédagogique',
        'Superviser pointages enseignants',
        'Coordonner discipline et emploi du temps',
      ],
      quickActions: const [
        _RoleQuickAction.students,
        _RoleQuickAction.teacherAttendance,
        _RoleQuickAction.teacherTimesheet,
        _RoleQuickAction.timetable,
        _RoleQuickAction.discipline,
      ],
      onQuickActionSelected: (action) => _handleRoleQuickAction(ref, action),
      metrics: [
        _RoleMetric(
          label: 'Élèves suivis',
          value: '$_students',
          icon: Icons.groups_rounded,
          color: const Color(0xFF2CC2FF),
        ),
        _RoleMetric(
          label: 'Absences et retards',
          value: '$_attendances',
          icon: Icons.fact_check_outlined,
          color: const Color(0xFF8FA7FF),
        ),
        _RoleMetric(
          label: 'Incidents ouverts',
          value: '$_incidentsOpen',
          icon: Icons.gpp_maybe_outlined,
          color: const Color(0xFFFF8C61),
        ),
        _RoleMetric(
          label: 'Pointages enseignants',
          value: '$_teacherEntries',
          icon: Icons.punch_clock_rounded,
          color: const Color(0xFF39D68F),
        ),
        _RoleMetric(
          label: 'Créneaux planning',
          value: '$_timetableSlots',
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF5B8CFF),
        ),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class TeacherDashboardPage extends ConsumerStatefulWidget {
  const TeacherDashboardPage({super.key});

  @override
  ConsumerState<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends ConsumerState<TeacherDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _assignedClasses = 0;
  int _assignedSubjects = 0;
  int _slots = 0;
  int _openIncidents = 0;
  int _myEntries = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final authUser = ref.read(authControllerProvider).value;
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/teachers/'),
      _safeGetRows(dio, '/teacher-assignments/'),
      _safeGetRows(dio, '/teacher-schedule-slots/'),
      _safeGetRows(dio, '/discipline-incidents/'),
      _safeGetRows(dio, '/teacher-time-entries/'),
    ]);

    final teachers = results[0].rows;
    final assignments = results[1].rows;
    final slots = results[2].rows;
    final incidents = results[3].rows;
    final entries = results[4].rows;

    final teacher = teachers.firstWhere(
      (row) => _asInt(row['user']) == (authUser?.id ?? 0),
      orElse: () => <String, dynamic>{},
    );
    final teacherId = _asInt(teacher['id']);

    final ownAssignments = assignments
        .where((row) => _asInt(row['teacher']) == teacherId)
        .toList(growable: false);
    final ownAssignmentIds = ownAssignments
        .map((row) => _asInt(row['id']))
        .where((id) => id > 0)
        .toSet();
    final ownClassroomIds = ownAssignments
        .map((row) => _asInt(row['classroom']))
        .where((id) => id > 0)
        .toSet();
    final ownSubjectIds = ownAssignments
        .map((row) => _asInt(row['subject']))
        .where((id) => id > 0)
        .toSet();

    if (!mounted) return;
    setState(() {
      _assignedClasses = ownClassroomIds.length;
      _assignedSubjects = ownSubjectIds.length;
      _slots = slots
          .where((row) => ownAssignmentIds.contains(_asInt(row['assignment'])))
          .length;
      _openIncidents = incidents
          .where((row) => (row['status']?.toString() ?? 'open') == 'open')
          .length;
      _myEntries = entries
          .where((row) => _asInt(row['teacher']) == teacherId)
          .length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Tableau de bord Enseignant',
      subtitle: 'Vue personnelle des classes, matières et actions pédagogiques.',
      responsibilities: const [
        'Suivre vos classes et matières',
        'Consulter planning et notes',
        'Suivre vos pointages',
      ],
      quickActions: const [
        _RoleQuickAction.grades,
        _RoleQuickAction.timetable,
        _RoleQuickAction.teacherTimesheet,
      ],
      onQuickActionSelected: (action) => _handleRoleQuickAction(ref, action),
      metrics: [
        _RoleMetric(
          label: 'Classes affectées',
          value: '$_assignedClasses',
          icon: Icons.class_outlined,
          color: const Color(0xFF2CC2FF),
        ),
        _RoleMetric(
          label: 'Matières affectées',
          value: '$_assignedSubjects',
          icon: Icons.menu_book_rounded,
          color: const Color(0xFF5B8CFF),
        ),
        _RoleMetric(
          label: 'Créneaux planifiés',
          value: '$_slots',
          icon: Icons.calendar_month_rounded,
          color: const Color(0xFF8FA7FF),
        ),
        _RoleMetric(
          label: 'Incidents ouverts (vos classes)',
          value: '$_openIncidents',
          icon: Icons.report_problem_outlined,
          color: const Color(0xFFFF8C61),
        ),
        _RoleMetric(
          label: 'Vos pointages',
          value: '$_myEntries',
          icon: Icons.punch_clock_rounded,
          color: const Color(0xFF39D68F),
        ),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class AccountantDashboardPage extends ConsumerStatefulWidget {
  const AccountantDashboardPage({super.key});

  @override
  ConsumerState<AccountantDashboardPage> createState() => _AccountantDashboardPageState();
}

class _AccountantDashboardPageState extends ConsumerState<AccountantDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _payments = 0;
  int _fees = 0;
  int _payrolls = 0;
  int _expenses = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/payments/'),
      _safeGetRows(dio, '/fees/'),
      _safeGetRows(dio, '/teacher-payrolls/'),
      _safeGetRows(dio, '/expenses/'),
    ]);

    if (!mounted) return;
    setState(() {
      _payments = results[0].rows.length;
      _fees = results[1].rows.length;
      _payrolls = results[2].rows.length;
      _expenses = results[3].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Tableau de bord Comptable',
      subtitle: 'Pilotage financier opérationnel de l\'établissement.',
      responsibilities: const [
        'Suivre encaissements et soldes',
        'Valider les dépenses niveau 2',
        'Gérer les paiements',
      ],
      quickActions: const [
        _RoleQuickAction.finance,
        _RoleQuickAction.newPayment,
        _RoleQuickAction.reports,
      ],
      onQuickActionSelected: (action) => _handleRoleQuickAction(ref, action),
      metrics: [
        _RoleMetric(
          label: 'Paiements enregistrés',
          value: '$_payments',
          icon: Icons.payments_rounded,
          color: const Color(0xFF39D68F),
        ),
        _RoleMetric(
          label: 'Frais élèves',
          value: '$_fees',
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFF5B8CFF),
        ),
        _RoleMetric(
          label: 'Bulletins de paie enseignants',
          value: '$_payrolls',
          icon: Icons.badge_outlined,
          color: const Color(0xFF8FA7FF),
        ),
        _RoleMetric(
          label: 'Dépenses',
          value: '$_expenses',
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFFFF8C61),
        ),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class ParentDashboardPage extends ConsumerStatefulWidget {
  const ParentDashboardPage({super.key});

  @override
  ConsumerState<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends ConsumerState<ParentDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _childrenGrades = 0;
  int _childrenAttendances = 0;
  int _childrenIncidents = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/grades/'),
      _safeGetRows(dio, '/attendances/'),
      _safeGetRows(dio, '/discipline-incidents/'),
    ]);

    if (!mounted) return;
    setState(() {
      _childrenGrades = results[0].rows.length;
      _childrenAttendances = results[1].rows.length;
      _childrenIncidents = results[2].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Tableau de bord Parent',
      subtitle: 'Suivi des informations scolaires liées à vos enfants.',
      responsibilities: const [
        'Consulter notes et absences',
        'Suivre la discipline',
        'Lire les rapports disponibles',
      ],
      quickActions: const [
        _RoleQuickAction.reports,
      ],
      onQuickActionSelected: (action) => _handleRoleQuickAction(ref, action),
      metrics: [
        _RoleMetric(
          label: 'Notes visibles',
          value: '$_childrenGrades',
          icon: Icons.grade_outlined,
          color: const Color(0xFF5B8CFF),
        ),
        _RoleMetric(
          label: 'Absences/retards visibles',
          value: '$_childrenAttendances',
          icon: Icons.event_busy_outlined,
          color: const Color(0xFF8FA7FF),
        ),
        _RoleMetric(
          label: 'Incidents visibles',
          value: '$_childrenIncidents',
          icon: Icons.gpp_maybe_outlined,
          color: const Color(0xFFFF8C61),
        ),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}

class StudentDashboardPage extends ConsumerStatefulWidget {
  const StudentDashboardPage({super.key});

  @override
  ConsumerState<StudentDashboardPage> createState() => _StudentDashboardPageState();
}

class _StudentDashboardPageState extends ConsumerState<StudentDashboardPage> {
  bool _loading = true;
  bool _hasRestrictedData = false;
  int _myGrades = 0;
  int _myAttendances = 0;
  int _myIncidents = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final dio = ref.read(dioProvider);
    final results = await Future.wait([
      _safeGetRows(dio, '/grades/'),
      _safeGetRows(dio, '/attendances/'),
      _safeGetRows(dio, '/discipline-incidents/'),
    ]);

    if (!mounted) return;
    setState(() {
      _myGrades = results[0].rows.length;
      _myAttendances = results[1].rows.length;
      _myIncidents = results[2].rows.length;
      _hasRestrictedData = results.any((result) => result.restricted);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _RoleDashboardScaffold(
      title: 'Tableau de bord Élève',
      subtitle: 'Vue personnelle de votre progression et de votre suivi.',
      responsibilities: const [
        'Consulter vos notes',
        'Suivre vos absences',
        'Voir vos incidents disciplinaires',
      ],
      quickActions: const [
        _RoleQuickAction.reports,
      ],
      onQuickActionSelected: (action) => _handleRoleQuickAction(ref, action),
      metrics: [
        _RoleMetric(
          label: 'Notes visibles',
          value: '$_myGrades',
          icon: Icons.grade_outlined,
          color: const Color(0xFF5B8CFF),
        ),
        _RoleMetric(
          label: 'Absences/retards',
          value: '$_myAttendances',
          icon: Icons.event_busy_outlined,
          color: const Color(0xFF8FA7FF),
        ),
        _RoleMetric(
          label: 'Incidents',
          value: '$_myIncidents',
          icon: Icons.gpp_maybe_outlined,
          color: const Color(0xFFFF8C61),
        ),
      ],
      fallbackNote: _hasRestrictedData
          ? 'Certaines statistiques sont masquées selon vos droits d\'accès.'
          : null,
      onRefresh: _load,
    );
  }
}
