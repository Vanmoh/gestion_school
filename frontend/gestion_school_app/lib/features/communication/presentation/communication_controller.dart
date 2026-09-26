import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/communication_repository.dart';
import '../domain/communication_models.dart';

final communicationRepositoryProvider = Provider<CommunicationRepository>((ref) {
  return CommunicationRepository(ref.read(dioProvider));
});

/// Ce sur quoi les annonces se filtrent, porté au serveur.
///
/// L'écran cherchait en mémoire dans la page qu'il avait chargée. Une classe
/// à part plutôt que deux paramètres: un `family` prend une seule clé, et elle
/// doit savoir se comparer, sans quoi chaque reconstruction relancerait la
/// requête.
class FiltreDesAnnonces {
  final String recherche;
  final PublicDeLAnnonce? public;

  const FiltreDesAnnonces({this.recherche = '', this.public});

  static const aucun = FiltreDesAnnonces();

  bool get estVide => recherche.trim().isEmpty && public == null;

  FiltreDesAnnonces avec({
    String? recherche,
    PublicDeLAnnonce? public,
    bool viderPublic = false,
  }) {
    return FiltreDesAnnonces(
      recherche: recherche ?? this.recherche,
      public: viderPublic ? null : (public ?? this.public),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FiltreDesAnnonces &&
      other.recherche == recherche &&
      other.public == public;

  @override
  int get hashCode => Object.hash(recherche, public);
}

/// Ce sur quoi la file d'envoi se filtre.
class FiltreDesNotifications {
  final String recherche;
  final CanalDeNotification? canal;
  final bool? envoyees;

  const FiltreDesNotifications({
    this.recherche = '',
    this.canal,
    this.envoyees,
  });

  static const aucun = FiltreDesNotifications();

  bool get estVide =>
      recherche.trim().isEmpty && canal == null && envoyees == null;

  FiltreDesNotifications avec({
    String? recherche,
    CanalDeNotification? canal,
    bool? envoyees,
    bool viderCanal = false,
    bool viderEnvoi = false,
  }) {
    return FiltreDesNotifications(
      recherche: recherche ?? this.recherche,
      canal: viderCanal ? null : (canal ?? this.canal),
      envoyees: viderEnvoi ? null : (envoyees ?? this.envoyees),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FiltreDesNotifications &&
      other.recherche == recherche &&
      other.canal == canal &&
      other.envoyees == envoyees;

  @override
  int get hashCode => Object.hash(recherche, canal, envoyees);
}

final annoncesProvider =
    FutureProvider.family<List<AnnonceItem>, FiltreDesAnnonces>((
      ref,
      filtre,
    ) async {
      return ref.read(communicationRepositoryProvider).fetchAnnonces(
        recherche: filtre.recherche,
        public: filtre.public,
      );
    });

final notificationsProvider =
    FutureProvider.family<List<NotificationItem>, FiltreDesNotifications>((
      ref,
      filtre,
    ) async {
      return ref.read(communicationRepositoryProvider).fetchNotifications(
        recherche: filtre.recherche,
        canal: filtre.canal,
        envoyees: filtre.envoyees,
      );
    });

final passerellesSmsProvider = FutureProvider<List<PasserelleSmsItem>>((ref) {
  return ref.read(communicationRepositoryProvider).fetchPasserelles();
});

final destinatairesProvider = FutureProvider<List<DestinataireItem>>((ref) {
  return ref.read(communicationRepositoryProvider).fetchDestinataires();
});

/// Les écritures du module, et l'attente qu'elles font peser sur l'écran.
class CommunicationMutation extends StateNotifier<AsyncValue<void>> {
  final Ref ref;

  CommunicationMutation(this.ref) : super(const AsyncValue.data(null));

  CommunicationRepository get _depot =>
      ref.read(communicationRepositoryProvider);

  void _rechargerLesAnnonces() => ref.invalidate(annoncesProvider);
  void _rechargerLesNotifications() => ref.invalidate(notificationsProvider);
  void _rechargerLesPasserelles() => ref.invalidate(passerellesSmsProvider);

  Future<void> _tenter(Future<void> Function() geste, void Function() apres) async {
    state = const AsyncValue.loading();
    try {
      await geste();
      apres();
      state = const AsyncValue.data(null);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> publierUneAnnonce({
    required String titre,
    required String message,
    required PublicDeLAnnonce public,
  }) {
    return _tenter(
      () => _depot.creerAnnonce(titre: titre, message: message, public: public),
      _rechargerLesAnnonces,
    );
  }

  Future<void> corrigerUneAnnonce({
    required int id,
    String? titre,
    String? message,
    PublicDeLAnnonce? public,
  }) {
    return _tenter(
      () => _depot.modifierAnnonce(
        id: id,
        titre: titre,
        message: message,
        public: public,
      ),
      _rechargerLesAnnonces,
    );
  }

  Future<void> retirerUneAnnonce(int id) {
    return _tenter(() => _depot.supprimerAnnonce(id), _rechargerLesAnnonces);
  }

  Future<void> creerUneNotification({
    required String titre,
    required String message,
    required CanalDeNotification canal,
    int? destinataireId,
  }) {
    return _tenter(
      () => _depot.creerNotification(
        titre: titre,
        message: message,
        canal: canal,
        destinataireId: destinataireId,
      ),
      _rechargerLesNotifications,
    );
  }

  Future<void> retirerUneNotification(int id) {
    return _tenter(
      () => _depot.supprimerNotification(id),
      _rechargerLesNotifications,
    );
  }

  Future<void> enregistrerUnePasserelle({
    required String fournisseur,
    required String urlApi,
    required String jeton,
    required String expediteur,
    required bool active,
  }) {
    return _tenter(
      () => _depot.enregistrerPasserelle(
        fournisseur: fournisseur,
        urlApi: urlApi,
        jeton: jeton,
        expediteur: expediteur,
        active: active,
      ),
      _rechargerLesPasserelles,
    );
  }

  Future<void> basculerUnePasserelle({required int id, required bool active}) {
    return _tenter(
      () => _depot.basculerPasserelle(id: id, active: active),
      _rechargerLesPasserelles,
    );
  }

  Future<void> retirerUnePasserelle(int id) {
    return _tenter(
      () => _depot.supprimerPasserelle(id),
      _rechargerLesPasserelles,
    );
  }
}

final communicationMutationProvider =
    StateNotifierProvider<CommunicationMutation, AsyncValue<void>>((ref) {
      return CommunicationMutation(ref);
    });
