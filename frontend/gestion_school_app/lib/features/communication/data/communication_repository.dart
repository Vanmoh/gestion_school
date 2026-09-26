import 'package:dio/dio.dart';

import '../../../core/roles/libelles_des_roles.dart';
import '../domain/communication_models.dart';

/// Les trois registres de la communication, et les filtres qui les réduisent.
///
/// L'écran appelait Dio depuis son `build`, chargeait les trois listes
/// entières et les cherchait en mémoire — sur la seule page qu'il avait reçue.
/// Une annonce plus ancienne que cette page était introuvable, et le serveur
/// ne proposait alors ni filtre ni recherche pour l'atteindre. Les deux
/// ViewSets en ont maintenant, et c'est ici qu'on les emploie.
class CommunicationRepository {
  final Dio dio;

  CommunicationRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return [];
  }

  Future<List<AnnonceItem>> fetchAnnonces({
    String recherche = '',
    PublicDeLAnnonce? public,
  }) async {
    final response = await dio.get(
      '/announcements/',
      queryParameters: {
        if (recherche.trim().isNotEmpty) 'search': recherche.trim(),
        if (public != null) 'audience': public.code,
      },
    );

    return _extractRows(response.data)
        .map((row) => (row as Map<String, dynamic>))
        .map(
          (row) => AnnonceItem(
            id: row['id'] as int,
            titre: row['title']?.toString() ?? '',
            message: row['message']?.toString() ?? '',
            public: PublicDeLAnnonce.depuisCode(row['audience']?.toString()),
            publieeLe: row['created_at']?.toString() ?? '',
            auteurId: row['author'] as int?,
          ),
        )
        .toList(growable: false);
  }

  Future<void> creerAnnonce({
    required String titre,
    required String message,
    required PublicDeLAnnonce public,
  }) async {
    await dio.post('/announcements/', data: {
      'title': titre,
      'message': message,
      'audience': public.code,
    });
  }

  /// Corriger une annonce plutôt que la supprimer et la réécrire.
  ///
  /// L'écran n'avait que `POST` et `DELETE`: une faute dans un titre déjà
  /// diffusé obligeait à retirer l'annonce et à la republier, ce qui la
  /// remontait en tête de liste comme une nouveauté.
  Future<void> modifierAnnonce({
    required int id,
    String? titre,
    String? message,
    PublicDeLAnnonce? public,
  }) async {
    await dio.patch('/announcements/$id/', data: {
      'title': ?titre,
      'message': ?message,
      if (public != null) 'audience': public.code,
    });
  }

  Future<void> supprimerAnnonce(int id) async {
    await dio.delete('/announcements/$id/');
  }

  Future<List<NotificationItem>> fetchNotifications({
    String recherche = '',
    CanalDeNotification? canal,
    bool? envoyees,
  }) async {
    final response = await dio.get(
      '/notifications/',
      queryParameters: {
        if (recherche.trim().isNotEmpty) 'search': recherche.trim(),
        if (canal != null) 'channel': canal.code,
        'is_sent': ?envoyees,
      },
    );

    return _extractRows(response.data)
        .map((row) => (row as Map<String, dynamic>))
        .map(
          (row) => NotificationItem(
            id: row['id'] as int,
            titre: row['title']?.toString() ?? '',
            message: row['message']?.toString() ?? '',
            canal: CanalDeNotification.depuisCode(row['channel']?.toString()),
            destinataireId: row['recipient'] as int?,
            destinataire: row['recipient_name']?.toString() ?? '',
            envoyee: row['is_sent'] == true,
            envoyeeLe: row['sent_at']?.toString() ?? '',
            creeeLe: row['created_at']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
  }

  Future<void> creerNotification({
    required String titre,
    required String message,
    required CanalDeNotification canal,
    int? destinataireId,
  }) async {
    await dio.post('/notifications/', data: {
      'title': titre,
      'message': message,
      'channel': canal.code,
      'recipient': ?destinataireId,
    });
  }

  Future<void> supprimerNotification(int id) async {
    await dio.delete('/notifications/$id/');
  }

  Future<List<PasserelleSmsItem>> fetchPasserelles() async {
    final response = await dio.get('/sms-providers/');

    return _extractRows(response.data)
        .map((row) => (row as Map<String, dynamic>))
        .map(
          (row) => PasserelleSmsItem(
            id: row['id'] as int,
            fournisseur: row['provider_name']?.toString() ?? '',
            urlApi: row['api_url']?.toString() ?? '',
            expediteur: row['sender_id']?.toString() ?? '',
            active: row['is_active'] == true,
          ),
        )
        .toList(growable: false);
  }

  Future<void> enregistrerPasserelle({
    required String fournisseur,
    required String urlApi,
    required String jeton,
    required String expediteur,
    required bool active,
  }) async {
    await dio.post('/sms-providers/', data: {
      'provider_name': fournisseur,
      'api_url': urlApi,
      'api_token': jeton,
      'sender_id': expediteur,
      'is_active': active,
    });
  }

  /// Activer ou couper une passerelle sans ressaisir son jeton.
  ///
  /// La coupure passait par une suppression, seule écriture que l'écran
  /// proposait — et le jeton d'API partait avec, à retrouver chez le
  /// fournisseur pour rouvrir le canal.
  Future<void> basculerPasserelle({required int id, required bool active}) async {
    await dio.patch('/sms-providers/$id/', data: {'is_active': active});
  }

  Future<void> supprimerPasserelle(int id) async {
    await dio.delete('/sms-providers/$id/');
  }

  /// L'annuaire des personnes à qui adresser une notification.
  Future<List<DestinataireItem>> fetchDestinataires() async {
    final response = await dio.get('/auth/users/directory/');

    return _extractRows(response.data)
        .map((row) => (row as Map<String, dynamic>))
        .map((row) {
          // `full_name` est servi par l'annuaire, déjà replié sur
          // l'identifiant quand la personne n'a pas de nom saisi.
          final nom = row['full_name']?.toString() ?? '';
          final role = row['role']?.toString() ?? '';
          return DestinataireItem(
            id: row['id'] as int,
            libelle: role.isEmpty ? nom : '$nom — ${roleEnClair(role)}',
          );
        })
        .toList(growable: false);
  }
}
