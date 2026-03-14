import 'package:dio/dio.dart';
import 'dart:typed_data';
import '../domain/student.dart';

class StudentsRepository {
  final Dio dio;
  StudentsRepository(this.dio);

  Future<List<Student>> fetchStudents({
    String search = '',
    int? classroomId,
    bool? isArchived,
  }) async {
    final query = <String, dynamic>{};
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (classroomId != null) query['classroom'] = classroomId;
    if (isArchived != null) query['is_archived'] = isArchived;
    query['ordering'] = '-created_at';

    final response = await dio.get('/students/', queryParameters: query);
    final rows = _extractRows(response.data);
    return rows.map(_toStudent).toList();
  }

  Future<List<Map<String, dynamic>>> fetchClassrooms() async {
    final response = await dio.get('/classrooms/');
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchParents() async {
    final response = await dio.get('/parents/');
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchAcademicYears() async {
    final response = await dio.get('/academic-years/');
    return _extractRows(response.data);
  }

  Future<Student> createStudentWithUser({
    required String username,
    required String firstName,
    required String lastName,
    required String password,
    String email = '',
    String phone = '',
    required int classroomId,
    int? parentId,
    DateTime? birthDate,
    String? photoPath,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    int? createdUserId;
    try {
      final userResponse = await dio.post(
        '/auth/users/',
        data: {
          'username': username,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'password': password,
          'role': 'student',
          'phone': phone,
        },
      );

      createdUserId = _asInt((userResponse.data as Map<String, dynamic>)['id']);
      if (createdUserId <= 0) {
        throw Exception('Création utilisateur invalide.');
      }

      final payload = <String, dynamic>{
        'user': createdUserId,
        'classroom': classroomId,
        'parent': ?parentId,
        if (birthDate != null) 'birth_date': _apiDate(birthDate),
      };

      final bool hasPhoto =
          (photoPath != null && photoPath.trim().isNotEmpty) ||
          (photoBytes != null && photoBytes.isNotEmpty);

      Response<dynamic> studentResponse;
      if (hasPhoto) {
        if (photoPath != null && photoPath.trim().isNotEmpty) {
          payload['photo'] = await MultipartFile.fromFile(
            photoPath,
            filename:
                photoFileName ??
                'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
        } else if (photoBytes != null && photoBytes.isNotEmpty) {
          payload['photo'] = MultipartFile.fromBytes(
            photoBytes,
            filename:
                photoFileName ??
                'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
        }
        studentResponse = await dio.post(
          '/students/',
          data: FormData.fromMap(payload),
        );
      } else {
        studentResponse = await dio.post('/students/', data: payload);
      }

      return _toStudent(Map<String, dynamic>.from(studentResponse.data as Map));
    } catch (error) {
      if (createdUserId != null && createdUserId > 0) {
        try {
          await dio.delete('/auth/users/$createdUserId/');
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<Student> updateStudent(
    int studentId,
    Map<String, dynamic> payload,
  ) async {
    final response = await dio.patch('/students/$studentId/', data: payload);
    return _toStudent(Map<String, dynamic>.from(response.data as Map));
  }

  Future<Student> toggleArchive(int studentId, bool archive) {
    return updateStudent(studentId, {'is_archived': archive});
  }

  Future<Student> assignClassroom(int studentId, int classroomId) {
    return updateStudent(studentId, {'classroom': classroomId});
  }

  Future<Student> assignParent(int studentId, int? parentId) {
    return updateStudent(studentId, {'parent': parentId});
  }

  Future<Student> updateStudentProfile({
    required int studentId,
    required int userId,
    required String firstName,
    required String lastName,
    String email = '',
    String phone = '',
    int? classroomId,
    int? parentId,
    DateTime? birthDate,
  }) async {
    await dio.patch(
      '/auth/users/$userId/',
      data: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone,
      },
    );

    final response = await dio.patch(
      '/students/$studentId/',
      data: {
        'classroom': classroomId,
        'parent': parentId,
        'birth_date': birthDate == null ? null : _apiDate(birthDate),
      },
    );
    return _toStudent(Map<String, dynamic>.from(response.data as Map));
  }

  Future<Student> updateStudentPhoto(
    int studentId, {
    String? photoPath,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    final payload = <String, dynamic>{};
    if (photoPath != null && photoPath.trim().isNotEmpty) {
      payload['photo'] = await MultipartFile.fromFile(
        photoPath,
        filename:
            photoFileName ??
            'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } else if (photoBytes != null && photoBytes.isNotEmpty) {
      payload['photo'] = MultipartFile.fromBytes(
        photoBytes,
        filename:
            photoFileName ??
            'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } else {
      throw Exception('Aucune photo sélectionnée.');
    }

    final response = await dio.patch(
      '/students/$studentId/',
      data: FormData.fromMap(payload),
    );
    return _toStudent(Map<String, dynamic>.from(response.data as Map));
  }

  Future<List<Map<String, dynamic>>> fetchStudentHistory(int studentId) async {
    final response = await dio.get(
      '/student-history/',
      queryParameters: {'student': studentId},
    );
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchStudentDiscipline(
    int studentId,
  ) async {
    final response = await dio.get(
      '/discipline-incidents/',
      queryParameters: {'student': studentId},
    );
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchStudentAttendances(
    int studentId,
  ) async {
    final response = await dio.get(
      '/attendances/',
      queryParameters: {'student': studentId},
    );
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchStudentFees(int studentId) async {
    final response = await dio.get(
      '/fees/',
      queryParameters: {'student': studentId},
    );
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchStudentPayments(int studentId) async {
    final response = await dio.get(
      '/payments/',
      queryParameters: {'fee__student': studentId},
    );
    return _extractRows(response.data);
  }

  Future<Map<String, dynamic>> createStudentHistory({
    required int studentId,
    required int academicYearId,
    required int classroomId,
    required double average,
    required int rank,
  }) async {
    final response = await dio.post(
      '/student-history/',
      data: {
        'student': studentId,
        'academic_year': academicYearId,
        'classroom': classroomId,
        'average': average,
        'rank': rank,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createDisciplineIncident({
    required int studentId,
    required DateTime incidentDate,
    required String category,
    required String description,
    String severity = 'medium',
    String sanction = '',
    bool parentNotified = false,
  }) async {
    final response = await dio.post(
      '/discipline-incidents/',
      data: {
        'student': studentId,
        'incident_date': _apiDate(incidentDate),
        'category': category,
        'description': description,
        'severity': severity,
        'sanction': sanction,
        'parent_notified': parentNotified,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateDisciplineIncidentStatus({
    required int incidentId,
    required String status,
  }) async {
    final response = await dio.patch(
      '/discipline-incidents/$incidentId/',
      data: {'status': status},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createAttendance({
    required int studentId,
    required DateTime date,
    bool isAbsent = false,
    bool isLate = false,
    String reason = '',
    String? proofPath,
    Uint8List? proofBytes,
    String? proofFileName,
  }) async {
    final payload = <String, dynamic>{
      'student': studentId,
      'date': _apiDate(date),
      'is_absent': isAbsent,
      'is_late': isLate,
      'reason': reason,
    };

    final normalizedProofPath = proofPath?.trim() ?? '';
    final Response<dynamic> response;
    if (normalizedProofPath.isNotEmpty) {
      payload['proof'] = await MultipartFile.fromFile(
        normalizedProofPath,
        filename:
            proofFileName ??
            'justificatif_${DateTime.now().millisecondsSinceEpoch}',
      );
      response = await dio.post(
        '/attendances/',
        data: FormData.fromMap(payload),
      );
    } else if (proofBytes != null && proofBytes.isNotEmpty) {
      payload['proof'] = MultipartFile.fromBytes(
        proofBytes,
        filename:
            proofFileName ??
            'justificatif_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      response = await dio.post(
        '/attendances/',
        data: FormData.fromMap(payload),
      );
    } else {
      response = await dio.post('/attendances/', data: payload);
    }

    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createStudentFee({
    required int studentId,
    required int academicYearId,
    required String feeType,
    required double amountDue,
    required DateTime dueDate,
  }) async {
    final response = await dio.post(
      '/fees/',
      data: {
        'student': studentId,
        'academic_year': academicYearId,
        'fee_type': feeType,
        'amount_due': amountDue,
        'due_date': _apiDate(dueDate),
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> createPayment({
    required int feeId,
    required double amount,
    required String method,
    String reference = '',
  }) async {
    final response = await dio.post(
      '/payments/',
      data: {
        'fee': feeId,
        'amount': amount,
        'method': method,
        'reference': reference,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Uint8List> fetchReceiptPdf(int paymentId) async {
    final response = await dio.get<List<int>>(
      '/reports/receipt/$paymentId/',
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('PDF vide');
    }
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> fetchStudentCardPdf(int studentId) async {
    final cacheBust = DateTime.now().millisecondsSinceEpoch;
    final response = await dio.get<List<int>>(
      '/reports/student-card/$studentId/',
      queryParameters: {'_ts': cacheBust},
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('PDF carte élève vide');
    }
    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> fetchClassStudentCardsPdf(
    int classroomId, {
    String layoutMode = 'standard',
  }) async {
    final query = <String, dynamic>{};
    if (layoutMode.trim().isNotEmpty) {
      query['layout_mode'] = layoutMode.trim();
    }
    query['_ts'] = DateTime.now().millisecondsSinceEpoch;

    final response = await dio.get<List<int>>(
      '/reports/student-cards/class/$classroomId/',
      queryParameters: query,
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('PDF cartes classe vide');
    }
    return Uint8List.fromList(bytes);
  }

  Student _toStudent(Map<String, dynamic> map) {
    final fullName = map['user_full_name']?.toString().trim();
    return Student(
      id: _asInt(map['id']),
      userId: _asInt(map['user']),
      username: map['user_username']?.toString() ?? '',
      firstName: map['user_first_name']?.toString() ?? '',
      lastName: map['user_last_name']?.toString() ?? '',
      email: map['user_email']?.toString() ?? '',
      phone: map['user_phone']?.toString() ?? '',
      matricule: map['matricule'] as String? ?? '',
      fullName: (fullName != null && fullName.isNotEmpty)
          ? fullName
          : 'Inconnu',
      isArchived: map['is_archived'] as bool? ?? false,
      classroomId: map['classroom'] == null ? null : _asInt(map['classroom']),
      classroomName: map['classroom_name']?.toString() ?? '',
      parentId: map['parent'] == null ? null : _asInt(map['parent']),
      parentName: map['parent_name']?.toString() ?? '',
      parentPhone: map['parent_phone']?.toString() ?? '',
      photo: map['photo']?.toString() ?? '',
      birthDate: _toDate(map['birth_date']),
      enrollmentDate: _toDate(map['enrollment_date']),
    );
  }

  List<Map<String, dynamic>> _extractRows(dynamic data) {
    final List<dynamic> rows;
    if (data is Map<String, dynamic> && data['results'] is List) {
      rows = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      rows = data;
    } else {
      rows = [];
    }

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _apiDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
