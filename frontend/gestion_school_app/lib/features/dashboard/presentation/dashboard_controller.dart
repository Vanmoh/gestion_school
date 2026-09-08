import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_stats.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.read(dioProvider));
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  return ref.read(dashboardRepositoryProvider).fetchStats();
});

/// Le rapport financier de l'année, mois par mois.
///
/// Séparé des compteurs du mois: il vise une autre période, coûte une
/// agrégation de plus, et l'écran doit pouvoir afficher les compteurs même
/// si ce rapport échoue.
final financesAnnuellesProvider = FutureProvider<FinancesAnnuelles>((ref) async {
  return ref.read(dashboardRepositoryProvider).fetchFinancesAnnuelles();
});
