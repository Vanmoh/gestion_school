import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/paginated_result.dart';
import '../domain/resultat_inscription.dart';
import '../domain/student.dart';
import '../domain/students_stats.dart';

class StudentsRepository {
  final Dio dio;
  StudentsRepository(this.dio);

  Future<List<Student>> fetchStudents({
    String search = '',
    int? classroomId,
    bool? isArchived,
    String ordering = '-created_at',
  }) async {
    final page = await fetchStudentsPage(
      search: search,
      classroomId: classroomId,
      isArchived: isArchived,
      ordering: ordering,
      page: 1,
      pageSize: 120,
    );
    return page.results;
  }

  Future<PaginatedResult<Student>> fetchStudentsPage({
    String search = '',
    int? classroomId,
    bool? isArchived,
    String ordering = '-created_at',
    int page = 1,
    int pageSize = 25,
  }) async {
    final query = <String, dynamic>{};
    if (search.trim().isNotEmpty) query['search'] = search.trim();
    if (classroomId != null) query['classroom'] = classroomId;
    if (isArchived != null) query['is_archived'] = isArchived;
    query['ordering'] = ordering;
    query['page'] = page;
    query['page_size'] = pageSize;

    final response = await dio.get('/students/', queryParameters: query);
    final rows = _extractRows(response.data);
    final mapped = rows.map(_toStudent).toList();

    final payload = response.data;
    if (payload is Map<String, dynamic>) {
      return PaginatedResult<Student>(
        count: payload['count'] as int? ?? mapped.length,
        next: payload['next']?.toString(),
        previous: payload['previous']?.toString(),
        results: mapped,
      );
    }

    return PaginatedResult<Student>(
      count: mapped.length,
      next: null,
      previous: null,
      results: mapped,
    );
  }

  /// Effectifs de l'etablissement, comptes par le serveur.
  ///
  /// Ils ne dependent ni de la pagination ni des filtres du tableau: l'en-tete
  /// decrit l'ecole, le tableau decrit ce qu'on regarde. Les compter sur la
  /// page recue faisait afficher « 15 actifs » a une ecole de 800 eleves.
  Future<StudentsStats> fetchStats() async {
    final response = await dio.get('/students/stats/');
    final data = response.data;
    if (data is! Map) return const StudentsStats.empty();

    int lire(String cle) => (data[cle] as num?)?.toInt() ?? 0;
    return StudentsStats(
      total: lire('total'),
      active: lire('active'),
      archived: lire('archived'),
      newThisYear: lire('new_this_year'),
      genderMissing: lire('gender_missing'),
      academicYear: data['academic_year']?.toString() ?? '',
    );
  }

  /// Applique une meme modification a plusieurs eleves, en un appel.
  ///
  /// En appels unitaires, deplacer une classe de 30 eleves fait 30 allers-
  /// retours; une coupure au milieu laisse la moitie du travail faite. Le
  /// serveur refuse la demande entiere si un seul identifiant sort du
  /// perimetre, plutot que d'en appliquer une partie.
  Future<int> bulkUpdate({
    required List<int> ids,
    bool? isArchived,
    int? classroomId,
    bool clearClassroom = false,
  }) async {
    final payload = <String, dynamic>{'ids': ids};
    if (isArchived != null) payload['is_archived'] = isArchived;
    if (clearClassroom) {
      payload['classroom'] = null;
    } else if (classroomId != null) {
      payload['classroom'] = classroomId;
    }

    final response = await dio.post('/students/bulk-update/', data: payload);
    final data = response.data;
    if (data is Map && data['updated'] is num) {
      return (data['updated'] as num).toInt();
    }
    return ids.length;
  }

  Future<List<Map<String, dynamic>>> fetchClassrooms() async {
    final response = await dio.get('/classrooms/');
    return _extractRows(response.data);
  }

  Future<List<Map<String, dynamic>>> fetchParents() async {
    final response = await dio.get('/parents/');
    return _extractRows(response.data);
  }

  /// Ce parent est-il déjà enregistré ?
  ///
  /// Posée avant toute création: trois frères inscrits séparément donnaient
  /// trois comptes parents, et le père recevait trois accès pour voir ses
  /// trois enfants.
  Future<List<Map<String, dynamic>>> chercherDesParents({
    String telephone = '',
    String texte = '',
  }) async {
    final response = await dio.get<Map<String, dynamic>>(
      '/parents/recherche/',
      queryParameters: {
        if (telephone.trim().isNotEmpty) 'telephone': telephone.trim(),
        if (texte.trim().isNotEmpty) 'q': texte.trim(),
      },
    );
    final resultats = response.data?['resultats'];
    if (resultats is! List) return const [];
    return resultats
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchAcademicYears() async {
    final response = await dio.get('/academic-years/');
    return _extractRows(response.data);
  }

  /// Inscrit un élève et sa famille en une seule opération.
  ///
  /// Remplace les deux appels d'avant -- créer le compte, puis la fiche --
  /// qui rattrapaient l'échec du second en supprimant le premier. Un
  /// rattrapage qui échoue laisse un compte orphelin; avec la famille, on
  /// serait passé à quatre appels. Le serveur fait tout, ou rien.
  Future<ResultatInscription> inscrire({
    required String firstName,
    required String lastName,
    required String gender,
    required int classroomId,
    required String lienParente,
    String email = '',
    String phone = '',
    DateTime? birthDate,
    DateTime? enrollmentDate,
    int? parentId,
    String parentFirstName = '',
    String parentLastName = '',
    String parentPhone = '',
    String parentWhatsapp = '',
    bool parentWhatsappConsent = false,
    String parentEmail = '',
    String? photoPath,
    Uint8List? photoBytes,
    String? photoFileName,
  }) async {
    final payload = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      'gender': gender,
      'classroom': classroomId,
      'lien_parente': lienParente,
      'email': email,
      'phone': phone,
      if (birthDate != null) 'birth_date': _apiDate(birthDate),
      if (enrollmentDate != null) 'enrollment_date': _apiDate(enrollmentDate),
      'parent_id': ?parentId,
      if (parentId == null) ...{
        'parent_first_name': parentFirstName,
        'parent_last_name': parentLastName,
        'parent_phone': parentPhone,
        'parent_whatsapp_phone': parentWhatsapp,
        'parent_whatsapp_consent': parentWhatsappConsent,
        'parent_email': parentEmail,
      },
    };

    final bool hasPhoto =
        (photoPath != null && photoPath.trim().isNotEmpty) ||
        (photoBytes != null && photoBytes.isNotEmpty);

    Response<dynamic> response;
    if (hasPhoto) {
      payload['photo'] = await _buildMultipartFile(
        path: photoPath,
        bytes: photoBytes,
        fileName: photoFileName,
        fallbackFileNamePrefix: 'photo',
        defaultExtension: 'jpg',
        fieldLabel: 'photo de profil',
      );
      if (payload['photo'] == null) {
        throw Exception('Aucune photo valide fournie pour l\'inscription.');
      }
      response = await dio.post(
        '/students/inscription/',
        data: FormData.fromMap(payload),
      );
    } else {
      response = await dio.post('/students/inscription/', data: payload);
    }

    return ResultatInscription.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
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

  /// Dispense un élève du paiement de son inscription, ou lève la dispense.
  ///
  /// Sans elle, le secrétariat n'avait qu'un moyen de délivrer le bulletin
  /// d'un boursier: saisir un faux versement, ce qui fausse la caisse.
  Future<Student> dispenserInscription(
    int studentId, {
    String motif = '',
    bool lever = false,
  }) async {
    final response = await dio.post(
      '/students/$studentId/dispense-inscription/',
      data: lever ? {'lever': true} : {'motif': motif},
    );
    return Student.fromJson(Map<String, dynamic>.from(response.data as Map));
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
    DateTime? enrollmentDate,
    String? gender,
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
        // Jamais envoyee a null, contrairement a birth_date: la colonne est
        // obligatoire cote base et un effacement partirait en 400.
        if (enrollmentDate != null)
          'enrollment_date': _apiDate(enrollmentDate),
        if (gender != null && gender.isNotEmpty) 'gender': gender,
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
    final multipartPhoto = await _buildMultipartFile(
      path: photoPath,
      bytes: photoBytes,
      fileName: photoFileName,
      fallbackFileNamePrefix: 'photo',
      defaultExtension: 'jpg',
      fieldLabel: 'photo de profil',
    );

    if (multipartPhoto == null) {
      throw Exception('Aucune photo sélectionnée.');
    }

    final payload = <String, dynamic>{'photo': multipartPhoto};

    final response = await dio.post(
      '/students/$studentId/upload-photo/',
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
    final multipartProof = await _buildMultipartFile(
      path: normalizedProofPath,
      bytes: proofBytes,
      fileName: proofFileName,
      fallbackFileNamePrefix: 'justificatif',
      defaultExtension: 'jpg',
      fieldLabel: 'justificatif',
    );

    if (multipartProof != null) {
      payload['proof'] = multipartProof;
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

  /// Le certificat de fréquentation d'un élève, en PDF.
  ///
  /// La famille le réclame pour un dossier de bourse, une demande de visa,
  /// un abonnement de transport ou une ouverture de compte. L'école le
  /// rédigeait à la main sur papier à en-tête.
  Future<Uint8List> fetchCertificatFrequentationPdf(int studentId) async {
    final response = await dio.get<List<int>>(
      '/reports/certificat-frequentation/$studentId/',
      queryParameters: {'_ts': DateTime.now().millisecondsSinceEpoch},
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Certificat de fréquentation vide');
    }
    return Uint8List.fromList(bytes);
  }

  /// Liste d'appel imprimable.
  ///
  /// Sans classe, le serveur rend toutes les classes de l'etablissement, une
  /// par page, suivies du recapitulatif des effectifs.
  Future<Uint8List> fetchClassRosterPdf({
    int? classroomId,
    String status = 'active',
  }) async {
    final chemin = classroomId == null
        ? '/reports/class-roster/'
        : '/reports/class-roster/$classroomId/';

    final response = await dio.get<List<int>>(
      chemin,
      queryParameters: {
        'status': status,
        '_ts': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(responseType: ResponseType.bytes),
    );

    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('PDF liste de classe vide');
    }
    return Uint8List.fromList(bytes);
  }

  Student _toStudent(Map<String, dynamic> map) => Student.fromJson(map);

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

  String _apiDate(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<MultipartFile?> _buildMultipartFile({
    String? path,
    Uint8List? bytes,
    String? fileName,
    required String fallbackFileNamePrefix,
    required String defaultExtension,
    required String fieldLabel,
  }) async {
    if (bytes != null && bytes.isNotEmpty) {
      return MultipartFile.fromBytes(
        bytes,
        filename: (fileName != null && fileName.trim().isNotEmpty)
            ? fileName.trim()
            : '${fallbackFileNamePrefix}_${DateTime.now().millisecondsSinceEpoch}.$defaultExtension',
      );
    }

    final normalizedPath = path?.trim() ?? '';
    if (normalizedPath.isEmpty) {
      return null;
    }

    if (kIsWeb) {
      throw Exception(
        'Upload web impossible pour $fieldLabel: le fichier doit etre charge en bytes.',
      );
    }

    return MultipartFile.fromFile(
      normalizedPath,
      filename: (fileName != null && fileName.trim().isNotEmpty)
          ? fileName.trim()
          : '${fallbackFileNamePrefix}_${DateTime.now().millisecondsSinceEpoch}.$defaultExtension',
    );
  }
}
