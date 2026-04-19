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
        classroomId: (map['classroom'] as num?)?.toInt(),
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
        conduite:
            (map['conduite'] as num?)?.toDouble() ??
            double.tryParse(map['conduite']?.toString() ?? '') ??
            18,
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> fetchSheetClassrooms() async {
    final response = await dio.get('/attendances/sheet_classrooms/');
    final rows = _extractRows(response.data);
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> fetchClassSheet({
    required int classroomId,
    required String date,
  }) async {
    final response = await dio.get(
      '/attendances/class-sheet/',
      queryParameters: {'classroom': classroomId, 'date': date},
    );
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> saveClassSheet({
    required int classroomId,
    required String date,
    required List<Map<String, dynamic>> items,
  }) async {
    final response = await dio.post(
      '/attendances/class-sheet/',
      data: {'classroom': classroomId, 'date': date, 'items': items},
    );
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> setClassSheetLock({
    required int classroomId,
    required String date,
    required bool lock,
    String notes = '',
  }) async {
    final response = await dio.post(
      '/attendances/class-sheet-validate/',
      data: {
        'classroom': classroomId,
        'date': date,
        'lock': lock,
        'notes': notes,
      },
    );
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  Future<List<int>> exportClassSheet({
    required int classroomId,
    required String date,
    required String format,
  }) async {
    final response = await dio.get(
      '/attendances/class-sheet-export/',
      queryParameters: {
        'classroom': classroomId,
        'date': date,
        'format': format,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    final data = response.data;
    if (data is List<int>) {
      return data;
    }
    if (data is List<dynamic>) {
      return data.whereType<int>().toList(growable: false);
    }
    return const <int>[];
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
    double? conduite,
  }) async {
    final payload = {
      'student': studentId,
      'date': date,
      'is_absent': isAbsent,
      'is_late': isLate,
      'reason': reason,
      ...?(conduite == null ? null : {'conduite': conduite}),
    };

    await dio.post('/attendances/', data: payload);
  }
}
