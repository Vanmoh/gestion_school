class AttendanceItem {
  final int id;
  final int studentId;
  final String studentFullName;
  final String studentMatricule;
  final String date;
  final bool isAbsent;
  final bool isLate;
  final String reason;
  final double conduite;

  const AttendanceItem({
    required this.id,
    required this.studentId,
    required this.studentFullName,
    required this.studentMatricule,
    required this.date,
    required this.isAbsent,
    required this.isLate,
    required this.reason,
    required this.conduite,
  });
}
