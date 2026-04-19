class AttendanceStudent {
  final int id;
  final String fullName;
  final String matricule;
  final int? classroomId;

  const AttendanceStudent({
    required this.id,
    required this.fullName,
    required this.matricule,
    this.classroomId,
  });
}
