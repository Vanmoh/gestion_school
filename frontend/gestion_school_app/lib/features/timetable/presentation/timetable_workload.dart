class TeacherWorkloadRow {
  const TeacherWorkloadRow({
    required this.teacherId,
    required this.teacherCode,
    required this.teacherName,
    required this.slotCount,
    required this.classCount,
    required this.totalMinutes,
    required this.perDayMinutes,
    required this.level,
  });

  final int teacherId;
  final String teacherCode;
  final String teacherName;
  final int slotCount;
  final int classCount;
  final int totalMinutes;
  final Map<String, int> perDayMinutes;
  final String level;

  double get totalHours => totalMinutes / 60.0;
}

class _MutableWorkload {
  _MutableWorkload({
    required this.teacherId,
    required this.teacherCode,
    required this.teacherName,
  });

  final int teacherId;
  final String teacherCode;
  final String teacherName;
  int slotCount = 0;
  final Set<int> classIds = <int>{};
  final Map<String, int> perDayMinutes = {
    'MON': 0,
    'TUE': 0,
    'WED': 0,
    'THU': 0,
    'FRI': 0,
    'SAT': 0,
  };

  int get totalMinutes {
    var total = 0;
    for (final value in perDayMinutes.values) {
      total += value;
    }
    return total;
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse((value ?? '').toString()) ?? 0;
}

String _teacherNameFromTeacherRow(Map<String, dynamic>? row) {
  if (row == null) return '';
  final explicitFullName = (row['user_full_name'] ?? '').toString().trim();
  if (explicitFullName.isNotEmpty) return explicitFullName;

  final firstName = (row['user_first_name'] ?? '').toString().trim();
  final lastName = (row['user_last_name'] ?? '').toString().trim();
  final fullName = '$firstName $lastName'.trim();
  if (fullName.isNotEmpty) return fullName;

  final username = (row['user_username'] ?? '').toString().trim();
  if (username.isNotEmpty) return username;

  return (row['employee_code'] ?? '').toString().trim();
}

int _minutesFromTime(dynamic value) {
  final raw = (value ?? '').toString().trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw);
  if (match == null) return 0;

  final hour = int.tryParse(match.group(1) ?? '') ?? 0;
  final minute = int.tryParse(match.group(2) ?? '') ?? 0;
  return hour * 60 + minute;
}

String teacherLoadLevelFromMinutes(int totalMinutes) {
  if (totalMinutes >= 26 * 60) return 'Surcharge';
  if (totalMinutes >= 20 * 60) return 'A surveiller';
  return 'Equilibre';
}

List<TeacherWorkloadRow> buildTeacherWorkloadRows({
  required List<Map<String, dynamic>> teachers,
  required Map<int, Map<String, dynamic>> assignmentById,
  required List<Map<String, dynamic>> scheduleSlots,
  int? classroomFilter,
}) {
  final teacherById = {
    for (final teacher in teachers) _asInt(teacher['id']): teacher,
  };

  final rows = <int, _MutableWorkload>{};

  for (final slot in scheduleSlots) {
    final assignmentId = _asInt(slot['assignment']);
    final assignment = assignmentById[assignmentId];
    if (assignment == null) continue;

    final classroomId = _asInt(assignment['classroom']);
    if (classroomFilter != null &&
        classroomFilter > 0 &&
        classroomId != classroomFilter) {
      continue;
    }

    final teacherId = _asInt(assignment['teacher']);
    if (teacherId <= 0) continue;

    final teacherRow = teacherById[teacherId];
    final teacherCode =
        (teacherRow?['employee_code'] ??
                assignment['teacherCode'] ??
                'ENS-$teacherId')
            .toString();

    final mutable = rows.putIfAbsent(
      teacherId,
      () => _MutableWorkload(
        teacherId: teacherId,
        teacherCode: teacherCode,
        teacherName: _teacherNameFromTeacherRow(teacherRow),
      ),
    );

    final start = _minutesFromTime(slot['start_time']);
    final end = _minutesFromTime(slot['end_time']);
    final duration = end > start ? end - start : 0;
    final day = (slot['day_of_week'] ?? '').toString().trim().toUpperCase();

    mutable.slotCount += 1;
    mutable.classIds.add(classroomId);
    if (mutable.perDayMinutes.containsKey(day)) {
      mutable.perDayMinutes[day] = (mutable.perDayMinutes[day] ?? 0) + duration;
    }
  }

  final result = <TeacherWorkloadRow>[];
  for (final mutable in rows.values) {
    final total = mutable.totalMinutes;
    result.add(
      TeacherWorkloadRow(
        teacherId: mutable.teacherId,
        teacherCode: mutable.teacherCode,
        teacherName: mutable.teacherName,
        slotCount: mutable.slotCount,
        classCount: mutable.classIds.length,
        totalMinutes: total,
        perDayMinutes: Map<String, int>.from(mutable.perDayMinutes),
        level: teacherLoadLevelFromMinutes(total),
      ),
    );
  }

  result.sort((a, b) {
    final byMinutes = b.totalMinutes.compareTo(a.totalMinutes);
    if (byMinutes != 0) return byMinutes;
    return a.teacherCode.compareTo(b.teacherCode);
  });

  return result;
}
