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
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (role != null && role.trim().isNotEmpty) 'role': role,
      'ordering': '-id',
    };

    final response = await dio.get('/auth/users/', queryParameters: query);
    final rows = _extractRows(response.data);

    final mapped = rows.map((row) {
      final map = row as Map<String, dynamic>;
      return UserAccount(
        id: map['id'] as int,
        username: map['username']?.toString() ?? '',
        firstName: map['first_name']?.toString() ?? '',
        lastName: map['last_name']?.toString() ?? '',
        email: map['email']?.toString() ?? '',
        role: map['role']?.toString() ?? '',
        phone: map['phone']?.toString() ?? '',
        etablissementId: (map['etablissement'] as num?)?.toInt(),
        etablissementName: map['etablissement_name']?.toString() ?? '',
      );
    }).toList();

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
          ...?(etablissementId == null
              ? null
              : {'etablissement': etablissementId}),
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
          ...?(etablissementId == null
              ? null
              : {'etablissement': etablissementId}),
        },
      );
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }

  Future<void> deleteUser(int userId) async {
    try {
      await dio.delete('/auth/users/$userId/');
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
  }) async {
    await dio.patch(
      '/auth/users/$userId/',
      data: {
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'role': role,
        'phone': phone,
      },
    );
  }

  Future<void> deleteUser(int userId) async {
    await dio.delete('/auth/users/$userId/');
  }
}
