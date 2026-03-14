import 'package:dio/dio.dart';
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

  Future<List<UserAccount>> fetchUsers() async {
    final response = await dio.get('/auth/users/');
    final rows = _extractRows(response.data);

    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      return UserAccount(
        id: map['id'] as int,
        username: map['username']?.toString() ?? '',
        firstName: map['first_name']?.toString() ?? '',
        lastName: map['last_name']?.toString() ?? '',
        email: map['email']?.toString() ?? '',
        role: map['role']?.toString() ?? '',
        phone: map['phone']?.toString() ?? '',
      );
    }).toList();
  }

  Future<void> createUser({
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    required String phone,
  }) async {
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
      },
    );
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
