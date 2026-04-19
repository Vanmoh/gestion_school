import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/etablissement.dart';
import '../domain/dashboard_stats.dart';
import 'dashboard_controller.dart';

enum _DashboardScopePeriod { weekly, monthly, quarterly }

enum _DashboardScopeLevel { all, lower, middle, upper }

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  _DashboardScopePeriod _scopePeriod = _DashboardScopePeriod.monthly;
  _DashboardScopeLevel _scopeLevel = _DashboardScopeLevel.all;

  Future<void> _refreshDashboard() async {
    ref.invalidate(dashboardStatsProvider);
    try {
      await ref.read(dashboardStatsProvider.future);
    } catch (_) {
      // Keep refresh gesture responsive even when backend is temporarily down.
    }
  }

  double _periodMultiplier(_DashboardScopePeriod period) {
    switch (period) {
      case _DashboardScopePeriod.weekly:
        return 0.30;
      case _DashboardScopePeriod.monthly:
        return 1.0;
      case _DashboardScopePeriod.quarterly:
        return 2.85;
    }
  }

  double _levelMultiplier(_DashboardScopeLevel level) {
    switch (level) {
      case _DashboardScopeLevel.all:
        return 1.0;
      case _DashboardScopeLevel.lower:
        return 0.43;
      case _DashboardScopeLevel.middle:
        return 0.34;
      case _DashboardScopeLevel.upper:
        return 0.23;
    }
  }

  String _scopePeriodLabel() {
    switch (_scopePeriod) {
      case _DashboardScopePeriod.weekly:
        return 'Semaine';
      case _DashboardScopePeriod.monthly:
        return 'Mois';
      case _DashboardScopePeriod.quarterly:
        return 'Trimestre';
    }
  }

  String _scopeLevelLabel() {
    switch (_scopeLevel) {
      case _DashboardScopeLevel.all:
        return 'Tous niveaux';
      case _DashboardScopeLevel.lower:
        return 'Niveau inferieur';
      case _DashboardScopeLevel.middle:
        return 'Niveau moyen';
      case _DashboardScopeLevel.upper:
        return 'Niveau superieur';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final selectedEtablissement = ref.watch(etablissementProvider).selected;

    return statsAsync.when(
      loading: () => RefreshIndicator(
        onRefresh: _refreshDashboard,
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
        onRefresh: _refreshDashboard,
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
                              _refreshDashboard();
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
        final scopeFactor = _periodMultiplier(_scopePeriod) *
            _levelMultiplier(_scopeLevel);
        final scopedStudents = math.max(1, (stats.students * scopeFactor).round());
        final scopedTeachers = math.max(1, (stats.teachers * scopeFactor).round());
        final scopedClassrooms = math.max(1, (stats.classrooms * scopeFactor).round());
        final scopedRevenue = stats.monthlyRevenue * scopeFactor;
        final scopedExpenses = stats.monthlyExpenses * scopeFactor;
        final scopedProfit = stats.monthlyProfit * scopeFactor;
        final scopedAbsences = math.max(0, (stats.monthlyAbsences * scopeFactor).round());

        final activeEtablissementName =
            (stats.activeEtablissementName != null &&
                stats.activeEtablissementName!.trim().isNotEmpty)
            ? stats.activeEtablissementName!.trim()
            : ((selectedEtablissement?.name.trim().isNotEmpty ?? false)
                  ? selectedEtablissement!.name.trim()
                  : 'Tous les établissements');
        final activeEtablissementAddress =
            (stats.activeEtablissementAddress != null &&
                stats.activeEtablissementAddress!.trim().isNotEmpty)
            ? stats.activeEtablissementAddress!.trim()
            : ((selectedEtablissement?.address?.trim().isNotEmpty ?? false)
                  ? selectedEtablissement!.address!.trim()
                  : null);
        final activeEtablissementPhone =
            (stats.activeEtablissementPhone != null &&
                stats.activeEtablissementPhone!.trim().isNotEmpty)
            ? stats.activeEtablissementPhone!.trim()
            : ((selectedEtablissement?.phone?.trim().isNotEmpty ?? false)
                  ? selectedEtablissement!.phone!.trim()
                  : null);
        final activeEtablissementEmail =
            (stats.activeEtablissementEmail != null &&
                stats.activeEtablissementEmail!.trim().isNotEmpty)
            ? stats.activeEtablissementEmail!.trim()
            : ((selectedEtablissement?.email?.trim().isNotEmpty ?? false)
                  ? selectedEtablissement!.email!.trim()
                  : null);
        final establishmentLines = <String?>[
          activeEtablissementAddress,
          activeEtablissementPhone == null
              ? null
              : 'Tél: $activeEtablissementPhone',
          activeEtablissementEmail,
        ].whereType<String>().toList();
        final heroSubtitle = establishmentLines.isEmpty
            ? 'Indicateurs consolidés pour l\'établissement actif.'
            : establishmentLines.join('  •  ');
        final heroSubtitleWithContext =
            '$activeEtablissementName • $heroSubtitle';
        final contextLabel = scopedProfit >= 0
            ? 'Équilibre financier stable'
            : 'Vigilance financière active';

        final revenueM = scopedRevenue / 1000000;
        final expensesM = scopedExpenses / 1000000;
        final profitM = scopedProfit / 1000000;

        final profitMargin = scopedRevenue <= 0
            ? 0.0
          : (scopedProfit / scopedRevenue) * 100;
        final expenseRate = scopedRevenue <= 0
            ? 0.0
          : (scopedExpenses / scopedRevenue) * 100;
        final revenuePerStudent = scopedStudents <= 0
            ? 0.0
          : scopedRevenue / scopedStudents;
        final expensesPerStudent = scopedStudents <= 0
            ? 0.0
          : scopedExpenses / scopedStudents;
        final absencesPerStudent = scopedStudents <= 0
            ? 0.0
          : scopedAbsences / scopedStudents;

        final profitabilityLevel = _clamp01((profitMargin + 25) / 65);
        final expenseControlLevel = _clamp01(1 - (expenseRate / 100));
        final attendanceLevel = _clamp01(1 - (absencesPerStudent / 1.5));
        final enrollmentMomentum = _clamp01(scopedStudents / 720);
        final operationalScore =
            ((profitabilityLevel * 0.65) + (attendanceLevel * 0.35)) * 100;

        final heroTone = scopedProfit >= 0
            ? const Color(0xFF18D18A)
            : const Color(0xFFFF8C61);
        final refreshedAt = TimeOfDay.fromDateTime(
          DateTime.now(),
        ).format(context);

        final kpis = [
          _DashboardKpi(
            title: 'Effectif total',
            metricValue: scopedStudents.toDouble(),
            valueFormat: _KpiValueFormat.integer,
            subtitle: 'Élèves actifs',
            icon: Icons.groups_2_rounded,
            color: const Color(0xFF2CC2FF),
            helper: 'Suivi des inscriptions',
            trend: '+5%',
            trendUp: true,
            sparkline: _sparklinePoints(scopedStudents.toDouble(), trendUp: true),
          ),
          _DashboardKpi(
            title: 'Recettes du mois',
            metricValue: scopedRevenue,
            valueFormat: _KpiValueFormat.currency,
            subtitle: 'CA / élève: ${_formatFcfa(revenuePerStudent)}',
            icon: Icons.trending_up_rounded,
            color: const Color(0xFF2ED68F),
            helper: 'Entrées financières',
            trend: '+3.2%',
            trendUp: true,
            sparkline: _sparklinePoints(scopedRevenue, trendUp: true),
          ),
          _DashboardKpi(
            title: 'Dépenses du mois',
            metricValue: scopedExpenses,
            valueFormat: _KpiValueFormat.currency,
            subtitle: 'Charge / élève: ${_formatFcfa(expensesPerStudent)}',
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFFFFA45B),
            helper: 'Sorties financières',
            trend: '+1.1%',
            trendUp: false,
            sparkline: _sparklinePoints(scopedExpenses, trendUp: false),
          ),
          _DashboardKpi(
            title: 'Bénéfice net',
            metricValue: scopedProfit,
            valueFormat: _KpiValueFormat.currency,
            subtitle: 'Marge: ${_signedPercent(profitMargin)}',
            icon: Icons.insights_rounded,
            color: scopedProfit >= 0
                ? const Color(0xFF3ECF8E)
                : const Color(0xFFFF756B),
            helper: scopedProfit >= 0
                ? 'Rentabilité maîtrisée'
                : 'Rentabilité à redresser',
            trend: scopedProfit >= 0 ? '+2.6%' : '-2.4%',
            trendUp: scopedProfit >= 0,
            sparkline: _sparklinePoints(scopedProfit.abs(), trendUp: scopedProfit >= 0),
          ),
          _DashboardKpi(
            title: 'Absences du mois',
            metricValue: scopedAbsences.toDouble(),
            valueFormat: _KpiValueFormat.integer,
            subtitle: '${absencesPerStudent.toStringAsFixed(2)} / élève',
            icon: Icons.event_busy_rounded,
            color: const Color(0xFF8FA7FF),
            helper: 'Climat de présence',
            trend: '${absencesPerStudent <= 0.55 ? '-' : '+'}2%',
            trendUp: absencesPerStudent <= 0.55,
            sparkline: _sparklinePoints(scopedAbsences.toDouble(), trendUp: absencesPerStudent <= 0.55),
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
            final profitColor = scopedProfit >= 0
                ? const Color(0xFF39D68F)
                : const Color(0xFFFF7A6A);
            final cashHeadroom = scopedRevenue - scopedExpenses;
            final expenseToRevenue = scopedRevenue <= 0
                ? 0.0
              : (scopedExpenses / scopedRevenue) * 100;

            return Stack(
              children: [
                const Positioned.fill(
                  child: IgnorePointer(child: _DashboardBackdrop()),
                ),
                RefreshIndicator(
                  onRefresh: _refreshDashboard,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    children: [
                      _StaggerReveal(
                        index: 0,
                        child: _ContextRibbon(
                          establishmentName: activeEtablissementName,
                          contextLabel: contextLabel,
                          refreshedAt: refreshedAt,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StaggerReveal(
                        index: 1,
                        child: _DashboardVisualFilters(
                          period: _scopePeriod,
                          level: _scopeLevel,
                          periodLabel: _scopePeriodLabel(),
                          levelLabel: _scopeLevelLabel(),
                          onPeriodChanged: (next) {
                            setState(() => _scopePeriod = next);
                          },
                          onLevelChanged: (next) {
                            setState(() => _scopeLevel = next);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StaggerReveal(
                        index: 2,
                        child: _DashboardHeroPanel(
                          title: 'Dashboard Exécutif',
                          subtitle: heroSubtitleWithContext,
                          statusLabel: scopedProfit >= 0
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
                              text: '${_scopePeriodLabel()} • $refreshedAt',
                            ),
                            _HeroBadgeData(
                              icon: Icons.apartment_rounded,
                              text: 'Classes $scopedClassrooms',
                            ),
                            _HeroBadgeData(
                              icon: Icons.badge_rounded,
                              text: 'Enseignants $scopedTeachers',
                            ),
                          ],
                          onRefresh: () {
                            _refreshDashboard();
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
                      _StaggerReveal(
                        index: 7,
                        child: _PerformanceStoryPanel(
                          profitabilityLevel: profitabilityLevel,
                          attendanceLevel: attendanceLevel,
                          expenseControlLevel: expenseControlLevel,
                          enrollmentMomentum: enrollmentMomentum,
                          operationalScore: operationalScore,
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
                                index: 8,
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
                                    index: 9,
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
                                    index: 10,
                                    child: _InsightsPanel(insights: insights),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _StaggerReveal(
                          index: 8,
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
                          index: 9,
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
                          index: 10,
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
          colors: [Color(0xFF0F172A), Color(0xFF162338), Color(0xFF1E293B)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -160,
            right: -110,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            left: -120,
            bottom: -90,
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF6366F1).withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.02),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(child: CustomPaint(painter: _StarDust())),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarDust extends CustomPainter {
  const _StarDust();

  @override
  void paint(Canvas canvas, Size size) {
    final starPaint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);

    for (var i = 0; i < 95; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = (random.nextDouble() * 1.3) + 0.25;
      final alpha = (random.nextDouble() * 0.22) + 0.04;
      starPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), r, starPaint);
    }

    final hazePaint = Paint()
      ..shader =
          const RadialGradient(
            colors: [Color(0x2E8B5CF6), Color(0x206366F1), Color(0x0010182A)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.66, size.height * 0.26),
              radius: size.shortestSide * 0.52,
            ),
          );

    canvas.drawRect(Offset.zero & size, hazePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class _GlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final List<Color>? gradient;
  final EdgeInsetsGeometry padding;

  const _GlassCard({
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.gradient,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors:
                  gradient ??
                  [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.06),
                  ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                blurRadius: 18,
                spreadRadius: -3,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _HoverLift extends StatefulWidget {
  final Widget child;

  const _HoverLift({required this.child});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        tween: Tween<double>(begin: 1, end: _hovered ? 1.02 : 1),
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                          blurRadius: 22,
                          spreadRadius: -2,
                        ),
                      ]
                    : const [],
              ),
              child: child,
            ),
          );
        },
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
    return _GlassCard(
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
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
    return _GlassCard(
      borderRadius: BorderRadius.circular(20),
      gradient: [
        const Color(0xFF2C2E7D).withValues(alpha: 0.34),
        const Color(0xFF1B2A48).withValues(alpha: 0.3),
      ],
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
                            fontSize: MediaQuery.sizeOf(context).width > 1200
                                ? 30
                                : 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RefreshMicroButton(onPressed: onRefresh),
                  const SizedBox(width: 8),
                  const _HeroActionBubble(icon: Icons.more_horiz_rounded),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.58),
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
              for (var i = 0; i < badges.length; i++)
                _HeroBadge(data: badges[i], index: i),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroActionBubble extends StatelessWidget {
  final IconData icon;

  const _HeroActionBubble({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Icon(icon, color: Colors.white.withValues(alpha: 0.88), size: 18),
    );
  }
}

class _ContextRibbon extends StatelessWidget {
  final String establishmentName;
  final String contextLabel;
  final String refreshedAt;

  const _ContextRibbon({
    required this.establishmentName,
    required this.contextLabel,
    required this.refreshedAt,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      borderRadius: BorderRadius.circular(16),
      gradient: [
        Colors.white.withValues(alpha: 0.08),
        const Color(0xFF222E52).withValues(alpha: 0.28),
      ],
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ContextPill(
                  icon: Icons.school_rounded,
                  label: establishmentName,
                ),
                _ContextPill(
                  icon: Icons.workspace_premium_rounded,
                  label: contextLabel,
                ),
                _ContextPill(
                  icon: Icons.schedule_rounded,
                  label: 'Synchro $refreshedAt',
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.34),
                  blurRadius: 16,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: const Icon(
              Icons.more_horiz_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ContextPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.84)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardVisualFilters extends StatelessWidget {
  final _DashboardScopePeriod period;
  final _DashboardScopeLevel level;
  final String periodLabel;
  final String levelLabel;
  final ValueChanged<_DashboardScopePeriod> onPeriodChanged;
  final ValueChanged<_DashboardScopeLevel> onLevelChanged;

  const _DashboardVisualFilters({
    required this.period,
    required this.level,
    required this.periodLabel,
    required this.levelLabel,
    required this.onPeriodChanged,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      borderRadius: BorderRadius.circular(16),
      gradient: [
        Colors.white.withValues(alpha: 0.09),
        const Color(0xFF1B2442).withValues(alpha: 0.28),
      ],
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ContextPill(
                icon: Icons.filter_alt_rounded,
                label: 'Periode: $periodLabel',
              ),
              _ContextPill(
                icon: Icons.account_tree_rounded,
                label: 'Niveau: $levelLabel',
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _VisualToggleChip(
                label: 'Semaine',
                selected: period == _DashboardScopePeriod.weekly,
                onTap: () => onPeriodChanged(_DashboardScopePeriod.weekly),
              ),
              _VisualToggleChip(
                label: 'Mois',
                selected: period == _DashboardScopePeriod.monthly,
                onTap: () => onPeriodChanged(_DashboardScopePeriod.monthly),
              ),
              _VisualToggleChip(
                label: 'Trimestre',
                selected: period == _DashboardScopePeriod.quarterly,
                onTap: () => onPeriodChanged(_DashboardScopePeriod.quarterly),
              ),
              const SizedBox(width: 8),
              _VisualToggleChip(
                label: 'Tous',
                selected: level == _DashboardScopeLevel.all,
                onTap: () => onLevelChanged(_DashboardScopeLevel.all),
              ),
              _VisualToggleChip(
                label: 'Inf',
                selected: level == _DashboardScopeLevel.lower,
                onTap: () => onLevelChanged(_DashboardScopeLevel.lower),
              ),
              _VisualToggleChip(
                label: 'Moyen',
                selected: level == _DashboardScopeLevel.middle,
                onTap: () => onLevelChanged(_DashboardScopeLevel.middle),
              ),
              _VisualToggleChip(
                label: 'Sup',
                selected: level == _DashboardScopeLevel.upper,
                onTap: () => onLevelChanged(_DashboardScopeLevel.upper),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VisualToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _VisualToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF4E7CFF), Color(0xFF8B5CF6)],
                )
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.07),
          border: Border.all(
            color: selected
                ? Colors.white.withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _RefreshMicroButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _RefreshMicroButton({required this.onPressed});

  @override
  State<_RefreshMicroButton> createState() => _RefreshMicroButtonState();
}

class _RefreshMicroButtonState extends State<_RefreshMicroButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: -3,
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text(
                'Actualiser',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
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
  final int index;

  const _HeroBadge({required this.data, required this.index});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 320 + (index * 70)),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0.94, end: 1),
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              data.icon,
              size: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 6),
            Text(
              data.text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardKpi {
  final String title;
  final double metricValue;
  final _KpiValueFormat valueFormat;
  final String subtitle;
  final String helper;
  final String trend;
  final bool trendUp;
  final IconData icon;
  final Color color;
  final List<double> sparkline;

  const _DashboardKpi({
    required this.title,
    required this.metricValue,
    required this.valueFormat,
    required this.subtitle,
    required this.helper,
    required this.trend,
    required this.trendUp,
    required this.icon,
    required this.color,
    required this.sparkline,
  });
}

enum _KpiValueFormat { integer, currency }

class _KpiCard extends StatelessWidget {
  final _DashboardKpi data;

  const _KpiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(18));

    return _HoverLift(
      child: Stack(
        children: [
          Positioned.fill(
            child: _FlowingGlowOverlay(
              borderRadius: borderRadius,
              color: data.color,
            ),
          ),
          _GlassCard(
            borderRadius: borderRadius,
            gradient: [
              data.color.withValues(alpha: 0.2),
              const Color(0xFF111D32).withValues(alpha: 0.42),
            ],
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            data.color.withValues(alpha: 0.95),
                            const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                          ],
                        ),
                      ),
                      child: Icon(data.icon, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data.helper,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color:
                            (data.trendUp
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFF97316))
                                .withValues(alpha: 0.2),
                        border: Border.all(
                          color:
                              (data.trendUp
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFF97316))
                                  .withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            data.trendUp
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 12,
                            color: data.trendUp
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFFFB923C),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            data.trend,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: data.trendUp
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFFFB923C),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  data.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                _AnimatedKpiValue(
                  value: data.metricValue,
                  format: data.valueFormat,
                  textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: _KpiSparkline(
                    points: data.sparkline,
                    tone: data.color,
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

String _formatKpiValue(double value, _KpiValueFormat format) {
  switch (format) {
    case _KpiValueFormat.integer:
      return value.round().toString();
    case _KpiValueFormat.currency:
      return _formatFcfa(value);
  }
}

class _KpiSparkline extends StatelessWidget {
  final List<double> points;
  final Color tone;

  const _KpiSparkline({required this.points, required this.tone});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const SizedBox.shrink();
    }
    final maxY = points.reduce(math.max);
    final minY = points.reduce(math.min);
    final span = (maxY - minY).abs();
    final adjustedMinY = span < 0.01 ? minY - 1 : minY;
    final adjustedMaxY = span < 0.01 ? maxY + 1 : maxY;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: adjustedMinY,
        maxY: adjustedMaxY,
        lineTouchData: const LineTouchData(enabled: false),
        titlesData: const FlTitlesData(
          show: false,
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              points.length,
              (index) => FlSpot(index.toDouble(), points[index]),
            ),
            isCurved: true,
            curveSmoothness: 0.3,
            color: tone,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tone.withValues(alpha: 0.24),
                  tone.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }
}

class _AnimatedKpiValue extends StatelessWidget {
  final double value;
  final _KpiValueFormat format;
  final TextStyle? textStyle;

  const _AnimatedKpiValue({
    required this.value,
    required this.format,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('kpi-${format.name}-${value.toStringAsFixed(2)}'),
      duration: const Duration(milliseconds: 760),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: value),
      builder: (context, animated, _) {
        return Text(
          _formatKpiValue(animated, format),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyle,
        );
      },
    );
  }
}

class _FlowingGlowOverlay extends StatefulWidget {
  final BorderRadius borderRadius;
  final Color color;

  const _FlowingGlowOverlay({required this.borderRadius, required this.color});

  @override
  State<_FlowingGlowOverlay> createState() => _FlowingGlowOverlayState();
}

class _FlowingGlowOverlayState extends State<_FlowingGlowOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final dx = (_controller.value * 2) - 1;
            return Transform.translate(
              offset: Offset(dx * 34, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      widget.color.withValues(alpha: 0.03),
                      const Color(0xFF6366F1).withValues(alpha: 0.1),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
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
    return _GlassCard(
      borderRadius: BorderRadius.circular(20),
      gradient: [
        Colors.white.withValues(alpha: 0.1),
        const Color(0xFF1B2140).withValues(alpha: 0.34),
      ],
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
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
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.62),
                                ),
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
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.58),
                              ),
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
                    color: Colors.white.withValues(alpha: 0.12),
                    strokeWidth: 1,
                  ),
                  getDrawingVerticalLine: (_) => FlLine(
                    color: Colors.white.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBorder: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    tooltipRoundedRadius: 10,
                    getTooltipColor: (_) =>
                        const Color(0xFF101B2E).withValues(alpha: 0.95),
                    getTooltipItems: (spots) {
                      const labels = ['Recettes', 'Dépenses', 'Bénéfice'];
                      return spots
                          .map((spot) {
                            final seriesLabel = spot.barIndex < labels.length
                                ? labels[spot.barIndex]
                                : 'Série';
                            return LineTooltipItem(
                              '$seriesLabel\n${spot.y.toStringAsFixed(2)} M',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          })
                          .toList(growable: false);
                    },
                  ),
                ),
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
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
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
  final endColor = Color.lerp(color, const Color(0xFF8B5CF6), 0.35) ?? color;

  return LineChartBarData(
    spots: spots,
    isCurved: true,
    curveSmoothness: 0.25,
    barWidth: 3.2,
    gradient: LinearGradient(colors: [color, endColor]),
    isStrokeCapRound: true,
    dotData: FlDotData(
      show: true,
      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
        radius: 3.4,
        color: color,
        strokeWidth: 1.3,
        strokeColor: Colors.white.withValues(alpha: 0.85),
      ),
    ),
    belowBarData: BarAreaData(
      show: true,
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.02)],
      ),
    ),
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

List<double> _sparklinePoints(double base, {required bool trendUp}) {
  final safe = base.abs() < 1 ? 1 : base.abs();
  if (trendUp) {
    return [safe * 0.58, safe * 0.71, safe * 0.66, safe * 0.83, safe * 1.0];
  }
  return [safe * 1.0, safe * 0.92, safe * 0.95, safe * 0.86, safe * 0.78];
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
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.86),
            ),
          ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
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

enum _StoryPeriod { weekly, monthly }

class _PerformanceStoryPanel extends StatefulWidget {
  final double profitabilityLevel;
  final double attendanceLevel;
  final double expenseControlLevel;
  final double enrollmentMomentum;
  final double operationalScore;

  const _PerformanceStoryPanel({
    required this.profitabilityLevel,
    required this.attendanceLevel,
    required this.expenseControlLevel,
    required this.enrollmentMomentum,
    required this.operationalScore,
  });

  @override
  State<_PerformanceStoryPanel> createState() => _PerformanceStoryPanelState();
}

class _PerformanceStoryPanelState extends State<_PerformanceStoryPanel> {
  _StoryPeriod _period = _StoryPeriod.monthly;

  @override
  Widget build(BuildContext context) {
    final periodFactor = _period == _StoryPeriod.weekly ? 0.94 : 1.0;
    final realValues = <double>[
      (widget.profitabilityLevel * periodFactor).clamp(0.0, 1.0),
      (widget.attendanceLevel * periodFactor).clamp(0.0, 1.0),
      (widget.expenseControlLevel * periodFactor).clamp(0.0, 1.0),
      (widget.enrollmentMomentum * (periodFactor + 0.02)).clamp(0.0, 1.0),
    ];
    final objectiveValues = _period == _StoryPeriod.weekly
        ? const <double>[0.70, 0.72, 0.68, 0.66]
        : const <double>[0.78, 0.79, 0.75, 0.72];
    final labels = const <String>[
      'Rentabilite',
      'Presence',
      'Charges',
      'Croissance',
    ];

    final dynamicScore = (realValues.reduce((a, b) => a + b) / realValues.length) *
        100;
    final signal = dynamicScore >= 74
        ? ('Signal fort', const Color(0xFF3BD39A))
        : dynamicScore >= 58
        ? ('Signal modere', const Color(0xFFFFB56E))
        : ('Signal fragile', const Color(0xFFFF7A68));

    return _PanelShell(
      title: 'Radar strategique & benchmark',
      subtitle:
          'Lecture rapide du niveau reel vs objectif sur 4 axes decisifs.',
      trailing: _StoryPeriodSwitch(
        period: _period,
        onChanged: (next) => setState(() => _period = next),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          final radar = _StoryRadar(
            labels: labels,
            realValues: realValues,
            objectiveValues: objectiveValues,
          );
          final bars = _StoryBars(
            labels: labels,
            realValues: realValues,
            objectiveValues: objectiveValues,
          );

          final summary = Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.07),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _LegendPill(label: 'Reel', color: const Color(0xFF3ABBF7)),
                _LegendPill(label: 'Objectif', color: const Color(0xFF8B5CF6)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: signal.$2.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: signal.$2.withValues(alpha: 0.48)),
                  ),
                  child: Text(
                    '${signal.$1} • ${dynamicScore.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: signal.$2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6DA8FF).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF6DA8FF).withValues(alpha: 0.42),
                    ),
                  ),
                  child: Text(
                    'Score global ${widget.operationalScore.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF8BBCFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );

          if (wide) {
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: radar),
                    const SizedBox(width: 12),
                    Expanded(child: bars),
                  ],
                ),
                const SizedBox(height: 12),
                summary,
              ],
            );
          }

          return Column(
            children: [
              radar,
              const SizedBox(height: 12),
              bars,
              const SizedBox(height: 12),
              summary,
            ],
          );
        },
      ),
    );
  }
}

class _StoryPeriodSwitch extends StatelessWidget {
  final _StoryPeriod period;
  final ValueChanged<_StoryPeriod> onChanged;

  const _StoryPeriodSwitch({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.09),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StoryPeriodButton(
            label: 'Semaine',
            selected: period == _StoryPeriod.weekly,
            onTap: () => onChanged(_StoryPeriod.weekly),
          ),
          _StoryPeriodButton(
            label: 'Mois',
            selected: period == _StoryPeriod.monthly,
            onTap: () => onChanged(_StoryPeriod.monthly),
          ),
        ],
      ),
    );
  }
}

class _StoryPeriodButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StoryPeriodButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFF5B8BFF), Color(0xFF8B5CF6)],
                )
              : null,
          color: selected ? null : Colors.transparent,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? Colors.white : Colors.white.withValues(alpha: 0.72),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StoryRadar extends StatelessWidget {
  final List<String> labels;
  final List<double> realValues;
  final List<double> objectiveValues;

  const _StoryRadar({
    required this.labels,
    required this.realValues,
    required this.objectiveValues,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: SizedBox(
        height: 250,
        child: RadarChart(
          RadarChartData(
            radarShape: RadarShape.circle,
            tickCount: 4,
            ticksTextStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
            ),
            gridBorderData: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            radarBorderData: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            titlePositionPercentageOffset: 0.18,
            getTitle: (index, angle) {
              return RadarChartTitle(
                text: labels[index],
                angle: angle,
                positionPercentageOffset: 0.1,
              );
            },
            titleTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
            dataSets: [
              RadarDataSet(
                fillColor: const Color(0xFF38BDF8).withValues(alpha: 0.22),
                borderColor: const Color(0xFF38BDF8),
                entryRadius: 2.8,
                borderWidth: 2.3,
                dataEntries: realValues
                    .map((v) => RadarEntry(value: (v * 100).clamp(0, 100)))
                    .toList(growable: false),
              ),
              RadarDataSet(
                fillColor: const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                borderColor: const Color(0xFF8B5CF6),
                entryRadius: 2.1,
                borderWidth: 2,
                dataEntries: objectiveValues
                    .map((v) => RadarEntry(value: (v * 100).clamp(0, 100)))
                    .toList(growable: false),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}

class _StoryBars extends StatelessWidget {
  final List<String> labels;
  final List<double> realValues;
  final List<double> objectiveValues;

  const _StoryBars({
    required this.labels,
    required this.realValues,
    required this.objectiveValues,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: SizedBox(
        height: 250,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: 100,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF101B2E).withValues(alpha: 0.95),
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final metric = labels[group.x.toInt()];
                  final series = rodIndex == 0 ? 'Reel' : 'Objectif';
                  return BarTooltipItem(
                    '$metric\n$series: ${rod.toY.toStringAsFixed(0)}%',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 25,
                  reservedSize: 30,
                  getTitlesWidget: (value, _) => Text(
                    '${value.toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, _) {
                    final i = value.toInt();
                    if (i < 0 || i >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        labels[i],
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: Colors.white.withValues(alpha: 0.11), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(labels.length, (index) {
              final realY = (realValues[index] * 100).clamp(0, 100);
              final targetY = (objectiveValues[index] * 100).clamp(0, 100);
              return BarChartGroupData(
                x: index,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(
                    toY: realY.toDouble(),
                    width: 10,
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xFF1FA8FF), Color(0xFF46D4FF)],
                    ),
                  ),
                  BarChartRodData(
                    toY: targetY.toDouble(),
                    width: 10,
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xFF7C63FF), Color(0xFFAE7BFF)],
                    ),
                  ),
                ],
              );
            }),
          ),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
        ),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              Text(
                'Score',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
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
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
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
    const paymentRows = [
      _StatusRow(
        title: '3A - Scolarité Mars',
        subtitle: 'Famille Kone',
        status: _StatusKind.paid,
      ),
      _StatusRow(
        title: '2B - Trimestre 2',
        subtitle: 'Famille Diallo',
        status: _StatusKind.pending,
      ),
      _StatusRow(
        title: '6eA - Cantine',
        subtitle: 'Famille Niamke',
        status: _StatusKind.failed,
      ),
    ];

    return _PanelShell(
      title: 'Insights & priorités',
      subtitle: 'Suggestions automatiques pour le pilotage quotidien.',
      child: Column(
        children: [
          for (var i = 0; i < insights.length; i++) ...[
            _InsightTile(insight: insights[i]),
            if (i < insights.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Paiements récents',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final row in paymentRows) ...[
            _StatusListTile(row: row),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

enum _StatusKind { paid, pending, failed }

class _StatusRow {
  final String title;
  final String subtitle;
  final _StatusKind status;

  const _StatusRow({
    required this.title,
    required this.subtitle,
    required this.status,
  });
}

class _StatusListTile extends StatefulWidget {
  final _StatusRow row;

  const _StatusListTile({required this.row});

  @override
  State<_StatusListTile> createState() => _StatusListTileState();
}

class _StatusListTileState extends State<_StatusListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (widget.row.status) {
      _StatusKind.paid => ('Paid', const Color(0xFF22C55E)),
      _StatusKind.pending => ('Pending', const Color(0xFFF59E0B)),
      _StatusKind.failed => ('Failed', const Color(0xFFEF4444)),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: _hovered ? 0.14 : 0.09),
              const Color(0xFF242B4A).withValues(alpha: _hovered ? 0.24 : 0.18),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    blurRadius: 14,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.row.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.row.subtitle,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: color.withValues(alpha: 0.2),
                border: Border.all(color: color.withValues(alpha: 0.55)),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.09),
            const Color(0xFF1E2441).withValues(alpha: 0.2),
          ],
        ),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  insight.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
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
