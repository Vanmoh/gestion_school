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
            resultatsPublies: row['results_published'] == true,
            resultatsPubliesLe:
                row['results_published_at']?.toString() ?? '',
            resultatsSaisis: (row['resultats_saisis'] as num?)?.toInt() ?? 0,
            epreuvesTotal: (row['epreuves_total'] as num?)?.toInt() ?? 0,
            epreuvesPubliees:
                (row['epreuves_publiees'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  /// Ouvre les résultats de la session aux familles.
  Future<String> publierLesResultats(int sessionId) async {
    final response = await dio.post('/exam-sessions/$sessionId/publier/');
    final data = response.data;
    return data is Map<String, dynamic>
        ? (data['detail']?.toString() ?? 'Résultats publiés.')
        : 'Résultats publiés.';
  }

  /// Referme l'accès, le temps d'une correction.
  Future<String> retirerLesResultats(int sessionId) async {
    final response = await dio.post('/exam-sessions/$sessionId/depublier/');
    final data = response.data;
    return data is Map<String, dynamic>
        ? (data['detail']?.toString() ?? 'Résultats retirés.')
        : 'Résultats retirés.';
  }

  /// Les épreuves, filtrées par le serveur et non en mémoire.
  ///
  /// Une école de quinze classes déroulait sinon tout son calendrier dans une
  /// seule liste. Les quatre critères sont ceux que l'API accepte déjà.
  Future<List<ExamPlanningItem>> fetchPlannings({
    int? sessionId,
    int? classroomId,
    int? subjectId,
    bool? publiees,
  }) async {
    final response = await dio.get(
      '/exam-plannings/',
      queryParameters: {
        'session': ?sessionId,
        'classroom': ?classroomId,
        'subject': ?subjectId,
        'results_published': ?publiees,
      },
    );
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
            classroomName: row['classroom_name']?.toString() ?? '',
            subjectName: row['subject_name']?.toString() ?? '',
            sessionTitle: row['session_title']?.toString() ?? '',
            resultatsSaisis: (row['resultats_saisis'] as num?)?.toInt() ?? 0,
            resultatsPublies: row['results_published'] == true,
            resultatsPubliesLe:
                row['results_published_at']?.toString() ?? '',
          ),
        )
        .toList();
  }

  /// Ouvre aux familles les résultats d'une épreuve, et d'elle seule.
  ///
  /// Les copies reviennent classe par classe : publier la campagne entière
  /// obligeait à ouvrir aussi ce qui n'était pas corrigé.
  Future<String> publierLEpreuve(int planningId) async {
    final response = await dio.post('/exam-plannings/$planningId/publier/');
    final data = response.data;
    return data is Map<String, dynamic>
        ? (data['detail']?.toString() ?? 'Résultats publiés.')
        : 'Résultats publiés.';
  }

  /// Referme une épreuve, le temps d'une correction.
  Future<String> retirerLEpreuve(int planningId) async {
    final response = await dio.post('/exam-plannings/$planningId/depublier/');
    final data = response.data;
    return data is Map<String, dynamic>
        ? (data['detail']?.toString() ?? 'Résultats retirés.')
        : 'Résultats retirés.';
  }

  /// Les notes, éventuellement celles d'une seule épreuve.
  ///
  /// C'est le grain de la correction : on corrige une épreuve, pas une
  /// session — et c'est ce qu'on veut relire avant de publier.
  Future<List<ExamResultItem>> fetchResults({int? planningId}) async {
    final response = await dio.get(
      '/exam-results/',
      queryParameters: {
        'planning': ?planningId,
      },
    );
    final rows = _extractRows(response.data);
    return rows
        .map(
          (row) => ExamResultItem(
            id: (row as Map<String, dynamic>)['id'] as int,
            sessionId: row['session'] as int,
            studentId: row['student'] as int,
            subjectId: row['subject'] as int,
            score: _toDouble(row['score']),
            subjectName: row['subject_name']?.toString() ?? '',
            sessionTitle: row['session_title']?.toString() ?? '',
            sessionTerm: row['session_term']?.toString() ?? '',
            studentFullName: row['student_full_name']?.toString() ?? '',
            studentMatricule: row['student_matricule']?.toString() ?? '',
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

  Future<List<OptionItem>> fetchSubjects({int? classroomId}) async {
    final response = await dio.get(
      '/subjects/',
      queryParameters: classroomId != null ? {'classroom': classroomId} : null,
    );
    final rows = _extractRows(response.data);
    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return OptionItem(
        id: map['id'] as int,
        label: map['name']?.toString() ?? '',
        classroomId: map['classroom'] as int?,
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
      return OptionItem(
        id: map['id'] as int,
        label: '$fullName ($matricule)',
        classroomId: map['classroom'] as int?,
      );
    }).toList();
  }

  Future<List<OptionItem>> fetchSupervisors() async {
    final response = await dio.get(
      // Annuaire en lecture: l'administration des comptes est un autre
      // module, ferme aux profils qui planifient les surveillances.
      '/auth/users/directory/',
      queryParameters: {'role': 'censor'},
    );
    final rows = _extractRows(response.data);
    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      final first = map['first_name']?.toString() ?? '';
      final last = map['last_name']?.toString() ?? '';
      final fullName = '$first $last'.trim();
      final label = fullName.isEmpty
          ? map['username']?.toString() ?? 'Censeur'
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

  /// Corrige une campagne déjà créée.
  ///
  /// Le dépôt n'avait que des `POST`, alors que l'API expose le CRUD complet
  /// depuis toujours : une session créée en double ou mal datée restait là
  /// pour toujours.
  Future<void> updateSession({
    required int id,
    String? title,
    String? term,
    String? startDate,
    String? endDate,
  }) async {
    await dio.patch(
      '/exam-sessions/$id/',
      data: {
        'title': ?title,
        'term': ?term,
        'start_date': ?startDate,
        'end_date': ?endDate,
      },
    );
  }

  /// Ce que la suppression d'une campagne emporterait.
  ///
  /// Ses épreuves, ses surveillances et **toutes ses notes** partent en
  /// cascade. Le serveur en rend l'inventaire ; il informe, il n'empêche pas.
  Future<InventaireDeSuppression> inventaireDeLaSession(int id) async {
    final response = await dio.get('/exam-sessions/$id/delete-check/');
    return InventaireDeSuppression.fromJson(response.data);
  }

  Future<void> deleteSession(int id) async {
    await dio.delete('/exam-sessions/$id/');
  }

  Future<void> updatePlanning({
    required int id,
    int? classroom,
    int? subject,
    String? examDate,
    String? startTime,
    String? endTime,
  }) async {
    await dio.patch(
      '/exam-plannings/$id/',
      data: {
        'classroom': ?classroom,
        'subject': ?subject,
        'exam_date': ?examDate,
        'start_time': ?startTime,
        'end_time': ?endTime,
      },
    );
  }

  /// Supprime une épreuve.
  ///
  /// Le serveur refuse en 409 si elle porte des notes — `ExamResult.planning`
  /// est en RESTRICT, et le message dit ce qui retient.
  Future<void> deletePlanning(int id) async {
    await dio.delete('/exam-plannings/$id/');
  }

  Future<void> deleteInvigilation(int id) async {
    await dio.delete('/exam-invigilations/$id/');
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
