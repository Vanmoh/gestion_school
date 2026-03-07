import 'package:dio/dio.dart';

import '../domain/attendance_item.dart';
import '../domain/attendance_stats.dart';
import '../domain/attendance_student.dart';

class AttendanceRepository {
  final Dio dio;

  AttendanceRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return [];
  }

  Future<List<AttendanceStudent>> fetchStudents() async {
    final response = await dio.get('/students/');
    final rows = _extractRows(response.data);

    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return AttendanceStudent(
        id: map['id'] as int,
        fullName: map['user_full_name']?.toString() ?? 'Inconnu',
        matricule: map['matricule']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<AttendanceItem>> fetchAttendances() async {
    final response = await dio.get('/attendances/');
    final rows = _extractRows(response.data);

    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return AttendanceItem(
        id: map['id'] as int,
        studentId: map['student'] as int,
        studentFullName: map['student_full_name']?.toString() ?? 'Inconnu',
        studentMatricule: map['student_matricule']?.toString() ?? '',
        date: map['date']?.toString() ?? '',
        isAbsent: map['is_absent'] as bool? ?? false,
        isLate: map['is_late'] as bool? ?? false,
        reason: map['reason']?.toString() ?? '',
      );
    }).toList();
  }

  Future<AttendanceMonthlyStats> fetchMonthlyStats({String? month}) async {
    final response = await dio.get(
      '/attendances/monthly_stats/',
      queryParameters: month == null ? null : {'month': month},
    );
    final data = response.data as Map<String, dynamic>;
    final dailyRows = (data['daily'] as List<dynamic>? ?? []);

    return AttendanceMonthlyStats(
      month: data['month']?.toString() ?? '',
      totalRecords: (data['total_records'] as num?)?.toInt() ?? 0,
      absences: (data['absences'] as num?)?.toInt() ?? 0,
      lates: (data['lates'] as num?)?.toInt() ?? 0,
      justifications: (data['justifications'] as num?)?.toInt() ?? 0,
      daily: dailyRows
          .map(
            (row) => AttendanceDailyStat(
              date: (row as Map<String, dynamic>)['date']?.toString() ?? '',
              absences: (row['absences'] as num?)?.toInt() ?? 0,
              lates: (row['lates'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(),
    );
  }

  Future<void> createAttendance({
    required int studentId,
    required String date,
    required bool isAbsent,
    required bool isLate,
    required String reason,
  }) async {
    await dio.post(
      '/attendances/',
      data: {
        'student': studentId,
        'date': date,
        'is_absent': isAbsent,
        'is_late': isLate,
        'reason': reason,
      },
    );
  }
}
