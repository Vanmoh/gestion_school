import 'package:dio/dio.dart';

import '../../../core/models/paginated_result.dart';
import '../domain/user_account.dart';

class UsersRepository {
  final Dio dio;

  UsersRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return [];
  }

  String _extractApiErrorMessage(DioException error) {
    final payload = error.response?.data;

    if (payload is Map<String, dynamic>) {
      final orderedKeys = [
        'detail',
        'message',
        'non_field_errors',
        'classroom',
        'students',
        'username',
        'email',
        'password',
        'role',
        'etablissement',
      ];

      for (final key in orderedKeys) {
        if (!payload.containsKey(key)) {
          continue;
        }
        final value = payload[key];
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }

      for (final entry in payload.entries) {
        final value = entry.value;
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
        if (value != null) {
          return value.toString();
        }
      }
    }

    if (payload is List && payload.isNotEmpty) {
      return payload.first.toString();
    }

    if (payload is String && payload.trim().isNotEmpty) {
      return payload.trim();
    }

    return 'Erreur de validation de la requete.';
  }

  Future<PaginatedResult<UserAccount>> fetchUsersPage({
    int page = 1,
    int pageSize = 25,
    String search = '',
    String? role,
    bool? actif,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (role != null && role.trim().isNotEmpty) 'role': role,
      // Le filtre par etat: c'est lui qui sort les comptes restes ouverts
      // apres un depart.
      'is_active': ?actif,
      'ordering': '-id',
    };

    final response = await dio.get('/auth/users/', queryParameters: query);
    final rows = _extractRows(response.data);

    // Le mapping vit dans le modele: recopie ici a la main, il oubliait
    // silencieusement tout champ ajoute cote serveur -- l'etat du compte et
    // sa derniere connexion arrivaient sans que rien ne les lise.
    final mapped = rows
        .whereType<Map<String, dynamic>>()
        .map(UserAccount.fromJson)
        .toList();

    final payload = response.data;
    if (payload is Map<String, dynamic>) {
      return PaginatedResult<UserAccount>(
        count: payload['count'] as int? ?? mapped.length,
        next: payload['next']?.toString(),
        previous: payload['previous']?.toString(),
        results: mapped,
      );
    }

    return PaginatedResult<UserAccount>(
      count: mapped.length,
      next: null,
      previous: null,
      results: mapped,
    );
  }

  Future<List<UserAccount>> fetchUsers() async {
    final page = await fetchUsersPage(page: 1, pageSize: 120);
    return page.results;
  }

  Future<void> createUser({
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    required String phone,
    int? etablissementId,
    int? classroomId,
    List<int>? studentIds,
  }) async {
    try {
      await dio.post(
        '/auth/register/',
        data: {
          'username': username,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'password': password,
          'role': role,
          'phone': phone,
          ...?(etablissementId == null ? null : {'etablissement': etablissementId}),
          ...?(classroomId == null ? null : {'classroom': classroomId}),
          ...?((studentIds == null || studentIds.isEmpty) ? null : {'students': studentIds}),
        },
      );
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }

  Future<void> updateUser({
    required int userId,
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String role,
    required String phone,
    int? etablissementId,
  }) async {
    try {
      await dio.patch(
        '/auth/users/$userId/',
        data: {
          'username': username,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'role': role,
          'phone': phone,
          ...?(etablissementId == null ? null : {'etablissement': etablissementId}),
        },
      );
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }

  /// Retire ou rend l'acces sans effacer ce que la personne a produit.
  ///
  /// C'est la bonne facon de traiter un depart: la suppression emporterait
  /// la fiche, les notes ou les pointages avec le compte.
  Future<void> setActive(int userId, bool actif) async {
    try {
      await dio.patch('/auth/users/$userId/', data: {'is_active': actif});
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }

  /// L'administration fixe un mot de passe provisoire, qu'elle communique.
  Future<String> resetPassword(int userId, String motDePasse) async {
    try {
      final reponse = await dio.post(
        '/auth/users/$userId/reset-password/',
        data: {'password': motDePasse},
      );
      final data = reponse.data;
      return data is Map && data['detail'] != null
          ? data['detail'].toString()
          : 'Mot de passe réinitialisé.';
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }

  /// Supprime un compte. Sans [confirme], le serveur refuse et rend
  /// l'inventaire de ce que la suppression emporterait: c'est ce qu'on
  /// montre avant de demander confirmation.
  Future<void> deleteUser(int userId, {bool confirme = false}) async {
    try {
      await dio.delete(
        '/auth/users/$userId/',
        queryParameters: confirme ? {'confirm': 'true'} : null,
      );
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }

  /// Ce que la suppression emporterait, ou null si elle ne casse rien.
  ///
  /// Lu depuis le refus du serveur: lui seul sait ce qui pend au compte, et
  /// le recalculer cote client donnerait un inventaire qui pourrait mentir.
  Future<Map<String, int>?> donneesLiees(int userId) async {
    try {
      await dio.delete('/auth/users/$userId/');
      // Aucune donnee liee: la suppression a eu lieu. Le cas est traite par
      // l'appelant, qui ne demande cet inventaire qu'avant de confirmer.
      return null;
    } on DioException catch (error) {
      final payload = error.response?.data;
      if (payload is Map && payload['linked_data'] is Map) {
        return (payload['linked_data'] as Map).map(
          (cle, valeur) => MapEntry(cle.toString(), (valeur as num).toInt()),
        );
      }
      throw Exception(_extractApiErrorMessage(error));
    }
  }
}
