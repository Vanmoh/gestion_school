import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paginated_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/provider_cache.dart';
import '../data/users_repository.dart';
import '../domain/user_account.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(ref.read(dioProvider));
});

final usersProvider = FutureProvider.autoDispose<List<UserAccount>>((
  ref,
) async {
  ref.cacheFor(const Duration(minutes: 3));
  return ref.read(usersRepositoryProvider).fetchUsers();
});

class UsersPageQuery {
  final int page;
  final int pageSize;
  final String search;
  final String? role;

  /// Filtre par etat du compte: vrai pour les seuls actifs, faux pour les
  /// seuls desactives, null pour tous. C'est lui qui sort les comptes restes
  /// ouverts apres un depart.
  final bool? actif;

  const UsersPageQuery({
    required this.page,
    required this.pageSize,
    this.search = '',
    this.role,
    this.actif,
  });

  @override
  bool operator ==(Object other) {
    return other is UsersPageQuery &&
        other.page == page &&
        other.pageSize == pageSize &&
        other.search == search &&
        other.role == role &&
        other.actif == actif;
  }

  @override
  int get hashCode => Object.hash(page, pageSize, search, role, actif);
}

final usersPaginatedProvider = FutureProvider.autoDispose
    .family<PaginatedResult<UserAccount>, UsersPageQuery>((ref, query) async {
      ref.cacheFor(const Duration(minutes: 3));
      return ref
          .read(usersRepositoryProvider)
          .fetchUsersPage(
            page: query.page,
            pageSize: query.pageSize,
            search: query.search,
            role: query.role,
            actif: query.actif,
          );
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
    int? etablissementId,
    int? classroomId,
    List<int>? studentIds,
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
            etablissementId: etablissementId,
            classroomId: classroomId,
            studentIds: studentIds,
          );
    });

    if (!state.hasError) {
      ref.invalidate(usersProvider);
      ref.invalidate(usersPaginatedProvider);
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
            etablissementId: etablissementId,
          );
    });

    if (!state.hasError) {
      ref.invalidate(usersProvider);
      ref.invalidate(usersPaginatedProvider);
    }
  }

  Future<void> deleteUser({required int userId, bool confirme = false}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref
          .read(usersRepositoryProvider)
          .deleteUser(userId, confirme: confirme);
    });

    _rafraichir();
  }

  /// Retire ou rend l'acces sans effacer ce que la personne a produit.
  Future<void> setActive({required int userId, required bool actif}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref.read(usersRepositoryProvider).setActive(userId, actif);
    });

    _rafraichir();
  }

  /// L'administration fixe un mot de passe provisoire. Rend le message du
  /// serveur, qui rappelle qu'il faut le communiquer.
  Future<String?> resetPassword({
    required int userId,
    required String motDePasse,
  }) async {
    state = const AsyncValue.loading();
    String? message;
    state = await AsyncValue.guard(() async {
      message = await ref
          .read(usersRepositoryProvider)
          .resetPassword(userId, motDePasse);
    });
    // Pas d'invalidation: un mot de passe ne change rien a ce que la liste
    // affiche.
    return state.hasError ? null : message;
  }

  /// Ce que la suppression emporterait, ou null si elle ne casse rien.
  Future<Map<String, int>?> donneesLiees(int userId) {
    return ref.read(usersRepositoryProvider).donneesLiees(userId);
  }

  void _rafraichir() {
    if (!state.hasError) {
      ref.invalidate(usersProvider);
      ref.invalidate(usersPaginatedProvider);
    }
  }
}
