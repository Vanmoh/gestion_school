import 'package:dio/dio.dart';
import '../domain/dashboard_stats.dart';

class DashboardRepository {
  final Dio dio;

  DashboardRepository(this.dio);

  Future<DashboardStats> fetchStats() async {
    final response = await dio.get('/dashboard/');
    final data = response.data as Map<String, dynamic>;

    double toDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '0') ?? 0;
    }

    return DashboardStats(
      students: (data['students'] as num?)?.toInt() ?? 0,
      monthlyRevenue: toDouble(data['monthly_revenue']),
      monthlyExpenses: toDouble(data['monthly_expenses']),
      monthlyProfit: toDouble(data['monthly_profit']),
      monthlyAbsences: (data['monthly_absences'] as num?)?.toInt() ?? 0,
    );
  }
}
