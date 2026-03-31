import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    dio: ref.read(dioProvider),
    tokenStorage: ref.read(tokenStorageProvider),
  );
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthUser?>>((ref) {
      return AuthController(ref.read(authRepositoryProvider));
    });

class AuthController extends StateNotifier<AsyncValue<AuthUser?>> {
  AuthController(this._repository) : super(const AsyncValue.data(null));

  final AuthRepository _repository;

  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repository.login(username: username, password: password),
    );
  }

  Future<void> restoreSession() async {
    final hasSession = await _repository.hasSession();
    if (!hasSession) {
      state = const AsyncValue.data(null);
      return;
    }

    final restored = await AsyncValue.guard(
      () => _repository.fetchCurrentUser(),
    );
    if (restored.hasError) {
      final err = restored.error;
      if (err is DioException && err.response?.statusCode == 401) {
        // Token invalid/expired and refresh failed: force clean login state.
        await _repository.logout();
      }
      state = const AsyncValue.data(null);
      return;
    }

    state = restored;
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AsyncValue.data(null);
  }
}
