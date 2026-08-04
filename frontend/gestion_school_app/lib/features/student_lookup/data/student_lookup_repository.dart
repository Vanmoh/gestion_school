import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../students/domain/student.dart';
import '../domain/student_dossier.dart';

/// Recherche d'un eleve puis lecture de son dossier complet.
///
/// La recherche s'appuie sur `/students/?search=`, que le serveur couvre deja
/// sur le matricule, les noms, la classe, le parent et les deux telephones. Le
/// dossier vient d'un unique appel: les onze rubriques etaient sinon onze
/// allers-retours.
class StudentLookupRepository {
  final Dio dio;

  StudentLookupRepository(this.dio);

  /// Eleves correspondant a la saisie, les plus pertinents d'abord.
  Future<List<Student>> search(String query, {int limit = 25}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final response = await dio.get(
      '/students/',
      queryParameters: {
        'search': trimmed,
        'ordering': 'user__last_name',
        'page': 1,
        'page_size': limit,
      },
    );

    final payload = response.data;
    final rows = payload is Map && payload['results'] is List
        ? payload['results'] as List
        : (payload is List ? payload : const []);

    return rows
        .whereType<Map>()
        .map((row) => Student.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<StudentDossier> fetchDossier(int studentId) async {
    final response = await dio.get('/students/$studentId/dossier/');
    final payload = response.data;
    return StudentDossier.fromJson(
      payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
    );
  }
}

final studentLookupRepositoryProvider = Provider<StudentLookupRepository>((ref) {
  return StudentLookupRepository(ref.read(dioProvider));
});
