import 'package:dio/dio.dart';
import 'dart:convert';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/token_storage.dart';
import '../domain/auth_user.dart';

class AuthRepository {
  final Dio dio;
  final TokenStorage tokenStorage;

  AuthRepository({required this.dio, required this.tokenStorage});

  Future<AuthUser> login({
    required String username,
    required String password,
  }) async {
    final tokenResponse = await dio.post(
      ApiConstants.login,
      data: {'username': username, 'password': password},
    );

    final access = tokenResponse.data['access'] as String;
    final refresh = tokenResponse.data['refresh'] as String;
    await tokenStorage.saveTokens(access: access, refresh: refresh);

    return fetchCurrentUser();
  }

  Future<AuthUser> fetchCurrentUser() async {
    final profileResponse = await dio.get(ApiConstants.me);
    final data = profileResponse.data as Map<String, dynamic>;

    final user = AuthUser(
      id: data['id'] as int,
      username: data['username'] as String,
      fullName: '${data['first_name']} ${data['last_name']}'.trim(),
      role: data['role'] as String,
    );

    await tokenStorage.saveCachedUser(
      jsonEncode({
        'id': user.id,
        'username': user.username,
        'fullName': user.fullName,
        'role': user.role,
      }),
    );

    return user;
  }

  Future<bool> hasSession() async {
    final access = await tokenStorage.accessToken();
    final refresh = await tokenStorage.refreshToken();
    return (access != null && access.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);
  }

  Future<AuthUser?> cachedUser() async {
    final raw = await tokenStorage.cachedUser();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return AuthUser(
        id: (data['id'] as num).toInt(),
        username: data['username'] as String,
        fullName: data['fullName'] as String,
        role: data['role'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() => tokenStorage.clear();
}
