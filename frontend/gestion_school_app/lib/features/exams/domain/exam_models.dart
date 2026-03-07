class ExamSessionItem {
  final int id;
  final String title;
  final int academicYearId;
  final String startDate;
  final String endDate;

  const ExamSessionItem({
    required this.id,
    required this.title,
    required this.academicYearId,
    required this.startDate,
    required this.endDate,
  });
}

class ExamPlanningItem {
  final int id;
  final int sessionId;
  final int classroomId;
  final int subjectId;
  final String examDate;
  final String startTime;
  final String endTime;

  const ExamPlanningItem({
    required this.id,
    required this.sessionId,
    required this.classroomId,
    required this.subjectId,
    required this.examDate,
    required this.startTime,
    required this.endTime,
  });
}

class ExamResultItem {
  final int id;
  final int sessionId;
  final int studentId;
  final int subjectId;
  final double score;

  const ExamResultItem({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.subjectId,
    required this.score,
  });
}

class ExamInvigilationItem {
  final int id;
  final int planningId;
  final int supervisorId;
  final String supervisorName;

  const ExamInvigilationItem({
    required this.id,
    required this.planningId,
    required this.supervisorId,
    required this.supervisorName,
  });
}

class OptionItem {
  final int id;
  final String label;

  const OptionItem({required this.id, required this.label});
}
