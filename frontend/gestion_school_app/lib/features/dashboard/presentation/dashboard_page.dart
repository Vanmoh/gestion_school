import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_controller.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);

    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Erreur: $error'),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => ref.invalidate(dashboardStatsProvider),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
      data: (stats) {
        final revenueM = stats.monthlyRevenue / 1000000;
        final expensesM = stats.monthlyExpenses / 1000000;
        final profitM = stats.monthlyProfit / 1000000;

        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(title: 'Élèves', value: stats.students.toString()),
                _StatCard(
                  title: 'Recettes (mois)',
                  value: '${stats.monthlyRevenue.toStringAsFixed(0)} FCFA',
                ),
                _StatCard(
                  title: 'Dépenses (mois)',
                  value: '${stats.monthlyExpenses.toStringAsFixed(0)} FCFA',
                ),
                _StatCard(
                  title: 'Bénéfice',
                  value: '${stats.monthlyProfit.toStringAsFixed(0)} FCFA',
                ),
                _StatCard(
                  title: 'Absences (mois)',
                  value: stats.monthlyAbsences.toString(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Finance mensuelle (en millions FCFA)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 280,
                      child: LineChart(
                        LineChartData(
                          minY: 0,
                          titlesData: const FlTitlesData(show: true),
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: true,
                            horizontalInterval: 0.05,
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                FlSpot(1, revenueM),
                                FlSpot(2, expensesM),
                                FlSpot(3, profitM),
                              ],
                              isCurved: true,
                              barWidth: 4,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(show: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;

  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
