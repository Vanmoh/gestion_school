import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dashboard_stats.dart';
import 'dashboard_controller.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  Future<void> _refreshDashboard(WidgetRef ref) async {
    ref.invalidate(dashboardStatsProvider);
    try {
      await ref.read(dashboardStatsProvider.future);
    } catch (_) {
      // Keep refresh gesture responsive even when backend is temporarily down.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return statsAsync.when(
      loading: () => RefreshIndicator(
        onRefresh: () => _refreshDashboard(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          children: const [
            SizedBox(
              height: 420,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
      error: (error, _) => RefreshIndicator(
        onRefresh: () => _refreshDashboard(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          children: [
            SizedBox(
              height: 420,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Impossible de charger le tableau de bord',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text('Erreur: $error'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () {
                              _refreshDashboard(ref);
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      data: (stats) {
        final revenueM = stats.monthlyRevenue / 1000000;
        final expensesM = stats.monthlyExpenses / 1000000;
        final profitM = stats.monthlyProfit / 1000000;

        final profitMargin = stats.monthlyRevenue <= 0
            ? 0.0
            : (stats.monthlyProfit / stats.monthlyRevenue) * 100;
        final expenseRate = stats.monthlyRevenue <= 0
            ? 0.0
            : (stats.monthlyExpenses / stats.monthlyRevenue) * 100;
        final revenuePerStudent = stats.students <= 0
            ? 0.0
            : stats.monthlyRevenue / stats.students;
        final expensesPerStudent = stats.students <= 0
            ? 0.0
            : stats.monthlyExpenses / stats.students;
        final absencesPerStudent = stats.students <= 0
            ? 0.0
            : stats.monthlyAbsences / stats.students;

        final profitabilityLevel = _clamp01((profitMargin + 25) / 65);
        final expenseControlLevel = _clamp01(1 - (expenseRate / 100));
        final attendanceLevel = _clamp01(1 - (absencesPerStudent / 1.5));
        final operationalScore =
            ((profitabilityLevel * 0.65) + (attendanceLevel * 0.35)) * 100;

        final heroTone = stats.monthlyProfit >= 0
            ? const Color(0xFF18D18A)
            : const Color(0xFFFF8C61);
        final refreshedAt = TimeOfDay.fromDateTime(
          DateTime.now(),
        ).format(context);

        final kpis = [
          _DashboardKpi(
            title: 'Effectif total',
            value: stats.students.toString(),
            subtitle: 'Élèves actifs',
            icon: Icons.groups_2_rounded,
            color: const Color(0xFF2CC2FF),
            helper: 'Suivi des inscriptions',
          ),
          _DashboardKpi(
            title: 'Recettes du mois',
            value: _formatFcfa(stats.monthlyRevenue),
            subtitle: 'CA / élève: ${_formatFcfa(revenuePerStudent)}',
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF2ED68F),
            helper: 'Entrées financières',
          ),
          _DashboardKpi(
            title: 'Dépenses du mois',
            value: _formatFcfa(stats.monthlyExpenses),
            subtitle: 'Charge / élève: ${_formatFcfa(expensesPerStudent)}',
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFFFFA45B),
            helper: 'Sorties financières',
          ),
          _DashboardKpi(
            title: 'Bénéfice net',
            value: _formatFcfa(stats.monthlyProfit),
            subtitle: 'Marge: ${_signedPercent(profitMargin)}',
            icon: Icons.insights_rounded,
            color: stats.monthlyProfit >= 0
                ? const Color(0xFF3ECF8E)
                : const Color(0xFFFF756B),
            helper: stats.monthlyProfit >= 0
                ? 'Rentabilité maîtrisée'
                : 'Rentabilité à redresser',
          ),
          _DashboardKpi(
            title: 'Absences du mois',
            value: stats.monthlyAbsences.toString(),
            subtitle: '${absencesPerStudent.toStringAsFixed(2)} / élève',
            icon: Icons.event_busy_rounded,
            color: const Color(0xFF8FA7FF),
            helper: 'Climat de présence',
          ),
        ];

        final insights = _buildInsights(
          stats: stats,
          profitMargin: profitMargin,
          expenseRate: expenseRate,
          absencesPerStudent: absencesPerStudent,
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= 1120;
            final kpiColumns = width >= 1400
                ? 5
                : width >= 980
                ? 3
                : width >= 640
                ? 2
                : 1;
            final kpiAspectRatio = kpiColumns == 1
                ? 3.2
                : kpiColumns == 2
                ? 2.15
                : 1.7;
            final profitColor = stats.monthlyProfit >= 0
                ? const Color(0xFF39D68F)
                : const Color(0xFFFF7A6A);
            final cashHeadroom = stats.monthlyRevenue - stats.monthlyExpenses;
            final expenseToRevenue = stats.monthlyRevenue <= 0
                ? 0.0
                : (stats.monthlyExpenses / stats.monthlyRevenue) * 100;

            return Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(child: _DashboardBackdrop()),
                ),
                RefreshIndicator(
                  onRefresh: () => _refreshDashboard(ref),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    children: [
                      _StaggerReveal(
                        index: 0,
                        child: _DashboardHeroPanel(
                          title: 'Dashboard Exécutif',
                          subtitle:
                              'Vision consolidée des performances pédagogiques et financières.',
                          statusLabel: stats.monthlyProfit >= 0
                              ? 'Performance saine'
                              : 'Vigilance financière',
                          statusColor: heroTone,
                          badges: [
                            _HeroBadgeData(
                              icon: Icons.percent_rounded,
                              text: 'Marge ${_signedPercent(profitMargin)}',
                            ),
                            _HeroBadgeData(
                              icon: Icons.balance_rounded,
                              text:
                                  'Dépenses ${expenseRate.toStringAsFixed(1)}%',
                            ),
                            _HeroBadgeData(
                              icon: Icons.person_search_rounded,
                              text:
                                  'Absences/élève ${absencesPerStudent.toStringAsFixed(2)}',
                            ),
                            _HeroBadgeData(
                              icon: Icons.schedule_rounded,
                              text: 'Synchro $refreshedAt',
                            ),
                          ],
                          onRefresh: () {
                            _refreshDashboard(ref);
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      GridView.builder(
                        shrinkWrap: true,
                        itemCount: kpis.length,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: kpiColumns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: kpiAspectRatio,
                        ),
                        itemBuilder: (context, index) => _StaggerReveal(
                          index: index + 1,
                          child: _KpiCard(data: kpis[index]),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _StaggerReveal(
                        index: 6,
                        child: _ExecutiveHighlightsStrip(
                          items: [
                            _ExecutiveHighlight(
                              icon: Icons.auto_graph_rounded,
                              title: 'Marge opérationnelle',
                              value: _signedPercent(profitMargin),
                              tone: profitColor,
                            ),
                            _ExecutiveHighlight(
                              icon: Icons.swap_vert_circle_outlined,
                              title: 'Excédent mensuel',
                              value: _formatFcfa(cashHeadroom),
                              tone: cashHeadroom >= 0
                                  ? const Color(0xFF2ED08F)
                                  : const Color(0xFFFF8B6B),
                            ),
                            _ExecutiveHighlight(
                              icon: Icons.pie_chart_outline_rounded,
                              title: 'Poids des charges',
                              value: '${expenseToRevenue.toStringAsFixed(1)}%',
                              tone: const Color(0xFF79B7FF),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: _StaggerReveal(
                                index: 7,
                                child: _FinancePanel(
                                  revenueM: revenueM,
                                  expensesM: expensesM,
                                  profitM: profitM,
                                  totalRevenue: stats.monthlyRevenue,
                                  totalExpenses: stats.monthlyExpenses,
                                  totalProfit: stats.monthlyProfit,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 5,
                              child: Column(
                                children: [
                                  _StaggerReveal(
                                    index: 8,
                                    child: _OperationsPanel(
                                      operationalScore: operationalScore,
                                      profitLevel: profitabilityLevel,
                                      expenseLevel: expenseControlLevel,
                                      attendanceLevel: attendanceLevel,
                                      profitMargin: profitMargin,
                                      expenseRate: expenseRate,
                                      absencesPerStudent: absencesPerStudent,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _StaggerReveal(
                                    index: 9,
                                    child: _InsightsPanel(insights: insights),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _StaggerReveal(
                          index: 7,
                          child: _FinancePanel(
                            revenueM: revenueM,
                            expensesM: expensesM,
                            profitM: profitM,
                            totalRevenue: stats.monthlyRevenue,
                            totalExpenses: stats.monthlyExpenses,
                            totalProfit: stats.monthlyProfit,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _StaggerReveal(
                          index: 8,
                          child: _OperationsPanel(
                            operationalScore: operationalScore,
                            profitLevel: profitabilityLevel,
                            expenseLevel: expenseControlLevel,
                            attendanceLevel: attendanceLevel,
                            profitMargin: profitMargin,
                            expenseRate: expenseRate,
                            absencesPerStudent: absencesPerStudent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _StaggerReveal(
                          index: 9,
                          child: _InsightsPanel(insights: insights),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DashboardBackdrop extends StatelessWidget {
  const _DashboardBackdrop();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7FAFF), Color(0xFFEFF4FC), Color(0xFFE8F0FA)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF45B6FF).withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            left: -90,
            bottom: -70,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF28D298).withValues(alpha: 0.07),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaggerReveal extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggerReveal({required this.index, required this.child});

  @override
  State<_StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<_StaggerReveal> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 70 * widget.index);
    Future<void>.delayed(delay, () {
      if (!mounted) {
        return;
      }
      setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.045),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _ExecutiveHighlight {
  final IconData icon;
  final String title;
  final String value;
  final Color tone;

  const _ExecutiveHighlight({
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
  });
}

class _ExecutiveHighlightsStrip extends StatelessWidget {
  final List<_ExecutiveHighlight> items;

  const _ExecutiveHighlightsStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        color: scheme.surface.withValues(alpha: 0.92),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items)
            Container(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: item.tone.withValues(alpha: 0.12),
                border: Border.all(color: item.tone.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Icon(item.icon, color: item.tone, size: 17),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: item.tone,
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
}

class _DashboardHeroPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String statusLabel;
  final Color statusColor;
  final List<_HeroBadgeData> badges;
  final VoidCallback onRefresh;

  const _DashboardHeroPanel({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.statusColor,
    required this.badges,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10253C), Color(0xFF151D2C), Color(0xFF1B2835)],
          stops: [0, 0.58, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.76),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Actualiser'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final badge in badges) _HeroBadge(data: badge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBadgeData {
  final IconData icon;
  final String text;

  const _HeroBadgeData({required this.icon, required this.text});
}

class _HeroBadge extends StatelessWidget {
  final _HeroBadgeData data;

  const _HeroBadge({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 14, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 6),
          Text(
            data.text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardKpi {
  final String title;
  final String value;
  final String subtitle;
  final String helper;
  final IconData icon;
  final Color color;

  const _DashboardKpi({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.helper,
    required this.icon,
    required this.color,
  });
}

class _KpiCard extends StatelessWidget {
  final _DashboardKpi data;

  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surface.withValues(alpha: 0.92),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: data.color.withValues(alpha: 0.18),
                    border: Border.all(
                      color: data.color.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Icon(data.icon, color: data.color, size: 19),
                ),
                const Spacer(),
                Text(
                  data.helper,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              data.title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              data.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              data.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _PanelShell({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: scheme.surface.withValues(alpha: 0.96),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _FinancePanel extends StatelessWidget {
  final double revenueM;
  final double expensesM;
  final double profitM;
  final double totalRevenue;
  final double totalExpenses;
  final double totalProfit;

  const _FinancePanel({
    required this.revenueM,
    required this.expensesM,
    required this.profitM,
    required this.totalRevenue,
    required this.totalExpenses,
    required this.totalProfit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxAxis = math
        .max(0.08, math.max(revenueM, math.max(expensesM, profitM.abs())))
        .toDouble();
    final chartMaxY = maxAxis * 1.22;
    final chartMinY = (profitM < 0 ? (profitM * 1.28) : 0.0).toDouble();

    return _PanelShell(
      title: 'Performance financière mensuelle',
      subtitle:
          'Comparatif recettes, dépenses et bénéfice net (en millions FCFA).',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: totalProfit >= 0
              ? const Color(0xFF2ECF8F).withValues(alpha: 0.14)
              : const Color(0xFFFF7968).withValues(alpha: 0.14),
          border: Border.all(
            color: totalProfit >= 0
                ? const Color(0xFF2ECF8F).withValues(alpha: 0.5)
                : const Color(0xFFFF7968).withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          totalProfit >= 0 ? 'Excédent' : 'Déficit',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: totalProfit >= 0
                ? const Color(0xFF2ECF8F)
                : const Color(0xFFFF7968),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                minY: chartMinY,
                maxY: chartMaxY,
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        const labels = ['S-3', 'S-2', 'S-1', 'Mois'];
                        final index = value.round();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            labels[index],
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      interval: _axisInterval(chartMaxY, chartMinY),
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _millionsAxisLabel(value),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: chartMaxY / 5,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.2),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.14),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: true),
                lineBarsData: [
                  _lineSeries(
                    color: const Color(0xFF24D0F4),
                    spots: _trendSpots(revenueM, start: 0.42, mid: 0.74),
                  ),
                  _lineSeries(
                    color: const Color(0xFFFFB76C),
                    spots: _trendSpots(expensesM, start: 0.34, mid: 0.65),
                  ),
                  _lineSeries(
                    color: totalProfit >= 0
                        ? const Color(0xFF39D68F)
                        : const Color(0xFFFF7A6A),
                    spots: _trendSpots(profitM, start: 0.22, mid: 0.58),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const _LegendPill(label: 'Recettes', color: Color(0xFF24D0F4)),
              const _LegendPill(label: 'Dépenses', color: Color(0xFFFFB76C)),
              _LegendPill(
                label: 'Bénéfice',
                color: totalProfit >= 0
                    ? const Color(0xFF39D68F)
                    : const Color(0xFFFF7A6A),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FinanceFootValue(
                label: 'Recettes',
                value: _formatFcfa(totalRevenue),
                color: const Color(0xFF24D0F4),
              ),
              _FinanceFootValue(
                label: 'Dépenses',
                value: _formatFcfa(totalExpenses),
                color: const Color(0xFFFFB76C),
              ),
              _FinanceFootValue(
                label: 'Bénéfice net',
                value: _formatFcfa(totalProfit),
                color: totalProfit >= 0
                    ? const Color(0xFF39D68F)
                    : const Color(0xFFFF7A6A),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

LineChartBarData _lineSeries({
  required Color color,
  required List<FlSpot> spots,
}) {
  return LineChartBarData(
    spots: spots,
    isCurved: true,
    curveSmoothness: 0.25,
    barWidth: 3.2,
    color: color,
    isStrokeCapRound: true,
    dotData: FlDotData(
      show: true,
      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
        radius: 3.2,
        color: color,
        strokeWidth: 1.1,
        strokeColor: Colors.white.withValues(alpha: 0.85),
      ),
    ),
    belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
  );
}

List<FlSpot> _trendSpots(
  double value, {
  required double start,
  required double mid,
}) {
  final phase3 = (mid + 1) / 2;
  return [
    FlSpot(0, value * start),
    FlSpot(1, value * mid),
    FlSpot(2, value * phase3),
    FlSpot(3, value),
  ];
}

double _axisInterval(double maxY, double minY) {
  final span = (maxY - minY).abs();
  if (span <= 0.15) {
    return 0.03;
  }
  if (span <= 0.5) {
    return 0.08;
  }
  if (span <= 1.5) {
    return 0.25;
  }
  if (span <= 4) {
    return 0.5;
  }
  return (span / 5).clamp(0.5, 4.0).toDouble();
}

String _millionsAxisLabel(double value) {
  if (value.abs() < 0.01) {
    return '0';
  }
  if (value.abs() >= 10) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class _LegendPill extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _FinanceFootValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _FinanceFootValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  final double operationalScore;
  final double profitLevel;
  final double expenseLevel;
  final double attendanceLevel;
  final double profitMargin;
  final double expenseRate;
  final double absencesPerStudent;

  const _OperationsPanel({
    required this.operationalScore,
    required this.profitLevel,
    required this.expenseLevel,
    required this.attendanceLevel,
    required this.profitMargin,
    required this.expenseRate,
    required this.absencesPerStudent,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Santé opérationnelle',
      subtitle:
          'Mesure combinée de la rentabilité et de la discipline scolaire.',
      child: Column(
        children: [
          Row(
            children: [
              _ScoreRing(score: operationalScore),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    _ProgressMetricRow(
                      label: 'Marge nette',
                      value: _signedPercent(profitMargin),
                      progress: profitLevel,
                      color: const Color(0xFF35D497),
                    ),
                    const SizedBox(height: 9),
                    _ProgressMetricRow(
                      label: 'Contrôle des dépenses',
                      value: '${expenseRate.toStringAsFixed(1)}%',
                      progress: expenseLevel,
                      color: const Color(0xFFFFB46B),
                    ),
                    const SizedBox(height: 9),
                    _ProgressMetricRow(
                      label: 'Présence élèves',
                      value:
                          '${absencesPerStudent.toStringAsFixed(2)} abs./élève',
                      progress: attendanceLevel,
                      color: const Color(0xFF7FA2FF),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  final double score;

  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    final normalized = _clamp01(score / 100);
    final tone = score >= 75
        ? const Color(0xFF2FD18F)
        : score >= 55
        ? const Color(0xFFFFB35E)
        : const Color(0xFFFF7B66);

    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: normalized,
            strokeWidth: 7,
            backgroundColor: tone.withValues(alpha: 0.18),
            valueColor: AlwaysStoppedAnimation<Color>(tone),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.toStringAsFixed(0),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text('Score', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressMetricRow extends StatelessWidget {
  final String label;
  final String value;
  final double progress;
  final Color color;

  const _ProgressMetricRow({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: _clamp01(progress),
            minHeight: 7,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            backgroundColor: color.withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  final List<_DashboardInsight> insights;

  const _InsightsPanel({required this.insights});

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'Insights & priorités',
      subtitle: 'Suggestions automatiques pour le pilotage quotidien.',
      child: Column(
        children: [
          for (var i = 0; i < insights.length; i++) ...[
            _InsightTile(insight: insights[i]),
            if (i < insights.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _DashboardInsight {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  const _DashboardInsight({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });
}

class _InsightTile extends StatelessWidget {
  final _DashboardInsight insight;

  const _InsightTile({required this.insight});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.34),
        ),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.26),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: insight.color.withValues(alpha: 0.2),
            ),
            child: Icon(insight.icon, size: 16, color: insight.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  insight.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<_DashboardInsight> _buildInsights({
  required DashboardStats stats,
  required double profitMargin,
  required double expenseRate,
  required double absencesPerStudent,
}) {
  final items = <_DashboardInsight>[];

  if (stats.monthlyProfit < 0) {
    items.add(
      const _DashboardInsight(
        icon: Icons.warning_amber_rounded,
        color: Color(0xFFFF7A66),
        title: 'Déficit constaté ce mois-ci',
        detail:
            'Prioriser la réduction des charges non pédagogiques immédiates.',
      ),
    );
  } else {
    items.add(
      const _DashboardInsight(
        icon: Icons.check_circle_outline_rounded,
        color: Color(0xFF2FD08F),
        title: 'Rentabilité positive',
        detail:
            'Maintenir le cap et sécuriser les postes de dépenses critiques.',
      ),
    );
  }

  if (expenseRate > 72) {
    items.add(
      _DashboardInsight(
        icon: Icons.pie_chart_outline_rounded,
        color: const Color(0xFFFFB26D),
        title: 'Niveau de dépenses élevé (${expenseRate.toStringAsFixed(1)}%)',
        detail: 'Réviser les coûts variables et planifier un budget plafonné.',
      ),
    );
  } else {
    items.add(
      _DashboardInsight(
        icon: Icons.savings_outlined,
        color: const Color(0xFF72C8FF),
        title: 'Structure de coûts sous contrôle',
        detail:
            'Bonne tenue budgétaire, préserver la discipline d’achat actuelle.',
      ),
    );
  }

  if (absencesPerStudent > 0.55) {
    items.add(
      _DashboardInsight(
        icon: Icons.school_outlined,
        color: const Color(0xFF8EA4FF),
        title: 'Présence à renforcer',
        detail:
            'Absences moyennes ${absencesPerStudent.toStringAsFixed(2)} par élève: cibler les classes les plus touchées.',
      ),
    );
  } else {
    items.add(
      _DashboardInsight(
        icon: Icons.task_alt_rounded,
        color: const Color(0xFF57D8A1),
        title: 'Présence globalement satisfaisante',
        detail:
            'Maintenir la dynamique actuelle avec un suivi hebdomadaire simple.',
      ),
    );
  }

  items.add(
    _DashboardInsight(
      icon: Icons.analytics_outlined,
      color: const Color(0xFF63C8FF),
      title: 'Marge nette ${_signedPercent(profitMargin)}',
      detail:
          'Utiliser cet indicateur comme boussole pour les décisions mensuelles.',
    ),
  );

  return items;
}

double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

String _signedPercent(double value) {
  if (value > 0) {
    return '+${value.toStringAsFixed(1)}%';
  }
  return '${value.toStringAsFixed(1)}%';
}

String _formatFcfa(double value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(' ');
    }
  }

  final formatted = negative ? '-${buffer.toString()}' : buffer.toString();
  return '$formatted FCFA';
}
