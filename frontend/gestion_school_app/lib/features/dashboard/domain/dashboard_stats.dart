class DashboardStats {
  final int students;
  final double monthlyRevenue;
  final double monthlyExpenses;
  final double monthlyProfit;
  final int monthlyAbsences;
  final int classrooms;
  final int teachers;
  final int? activeEtablissementId;
  final String? activeEtablissementName;
  final String? activeEtablissementAddress;
  final String? activeEtablissementPhone;
  final String? activeEtablissementEmail;

  const DashboardStats({
    required this.students,
    required this.monthlyRevenue,
    required this.monthlyExpenses,
    required this.monthlyProfit,
    required this.monthlyAbsences,
    required this.classrooms,
    required this.teachers,
    this.activeEtablissementId,
    this.activeEtablissementName,
    this.activeEtablissementAddress,
    this.activeEtablissementPhone,
    this.activeEtablissementEmail,
  });
}
