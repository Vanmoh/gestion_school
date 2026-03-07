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
