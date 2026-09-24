import 'package:dio/dio.dart';

import '../../../core/models/paginated_result.dart';
import '../domain/acces_rouverts.dart';
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
        'établissement',
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
    /// Numéro WhatsApp du parent, distinct du téléphone de répertoire.
    ///
    /// `null` quand le champ n'est pas concerné (compte non parent, ou
    /// dialogue qui ne le propose pas): le serveur n'y touche alors pas.
    /// Chaîne vide = effacer le numéro.
    String? whatsappPhone,
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
          'whatsapp_phone_input': ?whatsappPhone,
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
  ///
  /// [motDePasse] vide: c'est la règle de l'école qui s'applique — celle que
  /// « Personnalisation » affiche, le matricule pour un élève et le numéro
  /// pour un parent. Le serveur rend alors le mot de passe composé, pour
  /// qu'on puisse le lire à la famille: personne d'autre ne le connaît.
  Future<String> resetPassword(int userId, String motDePasse) async {
    try {
      final reponse = await dio.post(
        '/auth/users/$userId/reset-password/',
        data: motDePasse.isEmpty
            ? const <String, dynamic>{}
            : {'password': motDePasse},
      );
      final data = reponse.data;
      if (data is! Map) return 'Mot de passe réinitialisé.';

      final message = data['detail']?.toString() ?? 'Mot de passe réinitialisé.';
      final compose = data['mot_de_passe']?.toString() ?? '';
      // Composé par le serveur: sans le dire ici, le secrétariat n'aurait
      // rien à dicter.
      return compose.isEmpty ? message : 'Mot de passe : $compose. $message';
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }

  /// Rend leurs accès aux familles d'une classe qui n'ont jamais pu entrer.
  ///
  /// Le serveur ne touche qu'aux comptes jamais utilisés: un parent qui se
  /// connecte déjà garde son mot de passe. Il rend les accès en clair — ils
  /// n'existent qu'à cet instant, et ce qui n'est pas noté devra être
  /// réinitialisé.
  Future<AccesRouverts> rouvrirLesAcces({required int classroomId}) async {
    try {
      final reponse = await dio.post(
        '/auth/users/rouvrir-les-acces/',
        data: {'classroom': classroomId},
      );
      return AccesRouverts.fromJson(reponse.data);
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
  /// Ce qu'une suppression emporterait, sans rien supprimer.
  ///
  /// Cet inventaire s'obtenait en lançant la suppression et en lisant le
  /// refus. Un compte sans rien d'attaché n'était donc jamais refusé: il
  /// partait à l'instant où l'écran cherchait à savoir ce qu'il emportait,
  /// sans qu'aucune question ait été posée. C'est désormais une lecture.
  Future<Map<String, int>> donneesLiees(int userId) async {
    try {
      final response = await dio.get('/auth/users/$userId/donnees-liees/');
      final payload = response.data;
      if (payload is Map && payload['linked_data'] is Map) {
        return (payload['linked_data'] as Map).map(
          (cle, valeur) => MapEntry(cle.toString(), (valeur as num).toInt()),
        );
      }
      return const {};
    } on DioException catch (error) {
      throw Exception(_extractApiErrorMessage(error));
    }
  }
}
