import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/users_repository.dart';
import '../domain/user_account.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.read(dioProvider));
});

final usersProvider = FutureProvider<List<UserAccount>>((ref) async {
  return ref.read(usersRepositoryProvider).fetchUsers();
});

final userMutationProvider =
    StateNotifierProvider<UserMutationController, AsyncValue<void>>((ref) {
      return UserMutationController(ref);
    });

class UserMutationController extends StateNotifier<AsyncValue<void>> {
  UserMutationController(this.ref) : super(const AsyncValue.data(null));

  final Ref ref;

  Future<void> createUser({
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    required String phone,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref
          .read(usersRepositoryProvider)
          .createUser(
            username: username,
            firstName: firstName,
            lastName: lastName,
            email: email,
            password: password,
            role: role,
            phone: phone,
          );
    });

    if (!state.hasError) {
      ref.invalidate(usersProvider);
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
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref
          .read(usersRepositoryProvider)
          .updateUser(
            userId: userId,
            username: username,
            firstName: firstName,
            lastName: lastName,
            email: email,
            role: role,
            phone: phone,
          );
    });

    if (!state.hasError) {
      ref.invalidate(usersProvider);
    }
  }

  Future<void> deleteUser({required int userId}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref.read(usersRepositoryProvider).deleteUser(userId);
    });

    if (!state.hasError) {
      ref.invalidate(usersProvider);
    }
  }
}
