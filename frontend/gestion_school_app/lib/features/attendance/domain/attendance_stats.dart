class AttendanceDailyStat {
  final String date;
  final int absences;
  final int lates;

  const AttendanceDailyStat({
    required this.date,
    required this.absences,
    required this.lates,
  });
}

class AttendanceMonthlyStats {
  final String month;
  final int totalRecords;
  final int absences;
  final int lates;
  final int justifications;
  final List<AttendanceDailyStat> daily;

  const AttendanceMonthlyStats({
    required this.month,
    required this.totalRecords,
    required this.absences,
    required this.lates,
    required this.justifications,
    required this.daily,
  });
}
