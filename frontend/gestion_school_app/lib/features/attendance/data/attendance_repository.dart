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

  /// Fiches d'appel deja enregistrees, une ligne par classe et par date.
  ///
  /// Sans elle, revoir une fiche demandait de resaisir sa classe et sa date
  /// de memoire.
  Future<List<Map<String, dynamic>>> fetchSheetJournal({
    int? classroomId,
    String? from,
    String? to,
  }) async {
    final response = await dio.get(
      '/attendances/sheet-journal/',
      queryParameters: {
        'classroom': ?classroomId,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    return _extractRows(response.data)
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

  /// Toutes les fiches d'un jour, en un seul PDF.
  ///
  /// C'est le geste de fin de journee: l'administration archive l'appel de
  /// l'etablissement entier. Il fallait auparavant exporter classe par classe
  /// puis recoller les fichiers a la main.
  ///
  /// Le serveur annonce dans `X-Fiches-Count` combien de fiches le document
  /// rassemble: l'ecran peut le dire sans ouvrir le PDF.
  Future<({List<int> bytes, int nombreFiches})> exportDaySheets({
    required String date,
  }) async {
    final response = await dio.get(
      '/attendances/day-export/',
      queryParameters: {'date': date},
      options: Options(responseType: ResponseType.bytes),
    );

    final data = response.data;
    final bytes = data is List<int>
        ? data
        : data is List<dynamic>
        ? data.whereType<int>().toList(growable: false)
        : const <int>[];

    final annonce = response.headers.value('x-fiches-count');
    return (
      bytes: bytes,
      nombreFiches: int.tryParse(annonce ?? '') ?? 0,
    );
  }

  /// Depose ou remplace le justificatif d'une absence deja enregistree.
  ///
  /// Accepte sur une fiche verrouillee: le mot d'excuse arrive le lendemain,
  /// apres que la fiche du jour a ete validee.
  Future<Map<String, dynamic>> uploadProof({
    required int attendanceId,
    required String fileName,
    required List<int> bytes,
  }) async {
    final formData = FormData.fromMap({
      'proof': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final response = await dio.post(
      '/attendances/$attendanceId/proof/',
      data: formData,
    );
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
  }

  /// Retire un justificatif. Reserve au niveau administration cote serveur.
  Future<void> removeProof({required int attendanceId}) async {
    await dio.delete('/attendances/$attendanceId/proof/');
  }

  /// Note de conduite d'un eleve.
  ///
  /// Route dediee: la conduite ne s'ecrivait qu'en effet de bord de la
  /// creation d'une absence, et PATCH /students/ est ferme au censeur comme
  /// au surveillant, qui sont justement ceux qui la notent.
  Future<Map<String, dynamic>> saveConduite({
    required int studentId,
    required double conduite,
  }) async {
    final response = await dio.post(
      '/attendances/conduite/',
      data: {'student': studentId, 'conduite': conduite},
    );
    if (response.data is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response.data as Map);
    }
    return const <String, dynamic>{};
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
}
