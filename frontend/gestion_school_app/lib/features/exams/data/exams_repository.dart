import 'package:dio/dio.dart';

import '../domain/exam_models.dart';

class ExamsRepository {
  final Dio dio;

  ExamsRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return [];
  }

  double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '0') ?? 0;
  }

  Future<List<ExamSessionItem>> fetchSessions() async {
    final response = await dio.get('/exam-sessions/');
    final rows = _extractRows(response.data);
    return rows
        .map(
          (row) => ExamSessionItem(
            id: (row as Map<String, dynamic>)['id'] as int,
            title: row['title']?.toString() ?? '',
            term: row['term']?.toString() ?? 'T1',
            academicYearId: row['academic_year'] as int,
            startDate: row['start_date']?.toString() ?? '',
            endDate: row['end_date']?.toString() ?? '',
          ),
        )
        .toList();
  }

  Future<List<ExamPlanningItem>> fetchPlannings() async {
    final response = await dio.get('/exam-plannings/');
    final rows = _extractRows(response.data);
    return rows
        .map(
          (row) => ExamPlanningItem(
            id: (row as Map<String, dynamic>)['id'] as int,
            sessionId: row['session'] as int,
            classroomId: row['classroom'] as int,
            subjectId: row['subject'] as int,
            examDate: row['exam_date']?.toString() ?? '',
            startTime: row['start_time']?.toString() ?? '',
            endTime: row['end_time']?.toString() ?? '',
          ),
        )
        .toList();
  }

  Future<List<ExamResultItem>> fetchResults() async {
    final response = await dio.get('/exam-results/');
    final rows = _extractRows(response.data);
    return rows
        .map(
          (row) => ExamResultItem(
            id: (row as Map<String, dynamic>)['id'] as int,
            sessionId: row['session'] as int,
            studentId: row['student'] as int,
            subjectId: row['subject'] as int,
            score: _toDouble(row['score']),
          ),
        )
        .toList();
  }

  Future<List<ExamInvigilationItem>> fetchInvigilations() async {
    final response = await dio.get('/exam-invigilations/');
    final rows = _extractRows(response.data);
    return rows
        .map(
          (row) => ExamInvigilationItem(
            id: (row as Map<String, dynamic>)['id'] as int,
            planningId: row['planning'] as int,
            supervisorId: row['supervisor'] as int,
            supervisorName:
                row['supervisor_full_name']?.toString() ??
                row['supervisor_username']?.toString() ??
                'Surveillant',
          ),
        )
        .toList();
  }

  Future<List<OptionItem>> fetchAcademicYears() async {
    final response = await dio.get('/academic-years/');
    final rows = _extractRows(response.data);
    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return OptionItem(
        id: map['id'] as int,
        label: map['name']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<OptionItem>> fetchClassrooms() async {
    final response = await dio.get('/classrooms/');
    final rows = _extractRows(response.data);
    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return OptionItem(
        id: map['id'] as int,
        label: map['name']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<OptionItem>> fetchSubjects() async {
    final response = await dio.get('/subjects/');
    final rows = _extractRows(response.data);
    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return OptionItem(
        id: map['id'] as int,
        label: map['name']?.toString() ?? '',
      );
    }).toList();
  }

  Future<List<OptionItem>> fetchStudents() async {
    final response = await dio.get('/students/');
    final rows = _extractRows(response.data);
    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      final fullName = map['user_full_name']?.toString() ?? 'Inconnu';
      final matricule = map['matricule']?.toString() ?? '';
      return OptionItem(id: map['id'] as int, label: '$fullName ($matricule)');
    }).toList();
  }

  Future<List<OptionItem>> fetchSupervisors() async {
    final response = await dio.get(
      '/auth/users/',
      queryParameters: {'role': 'supervisor'},
    );
    final rows = _extractRows(response.data);
    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      final first = map['first_name']?.toString() ?? '';
      final last = map['last_name']?.toString() ?? '';
      final fullName = '$first $last'.trim();
      final label = fullName.isEmpty
          ? map['username']?.toString() ?? 'Surveillant'
          : fullName;
      return OptionItem(id: map['id'] as int, label: label);
    }).toList();
  }

  Future<void> createSession({
    required String title,
    required String term,
    required int academicYear,
    required String startDate,
    required String endDate,
  }) async {
    await dio.post(
      '/exam-sessions/',
      data: {
        'title': title,
        'term': term,
        'academic_year': academicYear,
        'start_date': startDate,
        'end_date': endDate,
      },
    );
  }

  Future<void> createPlanning({
    required int session,
    required int classroom,
    required int subject,
    required String examDate,
    required String startTime,
    required String endTime,
  }) async {
    await dio.post(
      '/exam-plannings/',
      data: {
        'session': session,
        'classroom': classroom,
        'subject': subject,
        'exam_date': examDate,
        'start_time': startTime,
        'end_time': endTime,
      },
    );
  }

  Future<void> createResult({
    required int session,
    required int student,
    required int subject,
    required double score,
  }) async {
    await dio.post(
      '/exam-results/',
      data: {
        'session': session,
        'student': student,
        'subject': subject,
        'score': score,
      },
    );
  }

  Future<void> createInvigilation({
    required int planning,
    required int supervisor,
  }) async {
    await dio.post(
      '/exam-invigilations/',
      data: {'planning': planning, 'supervisor': supervisor},
    );
  }
}
