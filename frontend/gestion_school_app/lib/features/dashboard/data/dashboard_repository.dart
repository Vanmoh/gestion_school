import 'package:dio/dio.dart';
import '../domain/dashboard_stats.dart';

class DashboardRepository {
  final Dio dio;

  DashboardRepository(this.dio);

  Future<DashboardStats> fetchStats() async {
    final response = await dio.get('/dashboard/');
    final data = response.data as Map<String, dynamic>;
    final activeEtablissement =
        data['active_etablissement'] as Map<String, dynamic>?;

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
      monthlyExpensesPending: toDouble(data['monthly_expenses_pending']),
      monthlyProfit: toDouble(data['monthly_profit']),
      monthlyAbsences: (data['monthly_absences'] as num?)?.toInt() ?? 0,
      classrooms: (data['classrooms'] as num?)?.toInt() ?? 0,
      teachers: (data['teachers'] as num?)?.toInt() ?? 0,
      activeEtablissementId: (activeEtablissement?['id'] as num?)?.toInt(),
      activeEtablissementName: activeEtablissement?['name']?.toString(),
      activeEtablissementAddress: activeEtablissement?['address']?.toString(),
      activeEtablissementPhone: activeEtablissement?['phone']?.toString(),
      activeEtablissementEmail: activeEtablissement?['email']?.toString(),
    );
  }

  /// Le rapport financier de l'année, mois par mois.
  Future<FinancesAnnuelles> fetchFinancesAnnuelles() async {
    final response = await dio.get('/dashboard/finances-annuelles/');
    final data = response.data as Map<String, dynamic>;

    double toDouble(dynamic value) {
      if (value is num) {
        return value.toDouble();
      }
      return double.tryParse(value?.toString() ?? '0') ?? 0;
    }

    final lignes = data['mois'] is List
        ? (data['mois'] as List<dynamic>)
        : const <dynamic>[];

    return FinancesAnnuelles(
      academicYearName: data['academic_year_name']?.toString() ?? '',
      mois: lignes.whereType<Map<String, dynamic>>().map((ligne) {
        return MoisFinancier(
          mois: ligne['mois']?.toString() ?? '',
          libelle: ligne['libelle']?.toString() ?? '',
          recettes: toDouble(ligne['recettes']),
          depenses: toDouble(ligne['depenses']),
          benefice: toDouble(ligne['benefice']),
        );
      }).toList(growable: false),
      totalRecettes: toDouble(data['total_recettes']),
      totalDepenses: toDouble(data['total_depenses']),
      benefice: toDouble(data['benefice']),
    );
  }
}
