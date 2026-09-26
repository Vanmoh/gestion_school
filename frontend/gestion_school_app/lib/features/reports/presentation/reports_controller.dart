import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/reports_repository.dart';
import '../domain/reports_models.dart';

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(ref.read(dioProvider));
});

final contexteDesRapportsProvider = FutureProvider<ContexteDesRapports>((ref) {
  return ref.read(reportsRepositoryProvider).fetchContexte();
});

/// Une page de reçus, demandée au serveur.
///
/// L'écran recevait la liste entière et la découpait lui-même. Une classe de
/// clé plutôt que deux paramètres: un `family` n'en prend qu'une, et elle doit
/// savoir se comparer.
class DemandeDeRecus {
  final String recherche;
  final int page;

  const DemandeDeRecus({this.recherche = '', this.page = 1});

  static const premiere = DemandeDeRecus();

  DemandeDeRecus avec({String? recherche, int? page}) {
    // Changer la recherche ramène à la première page: rester à la page 7
    // d'une autre recherche n'aurait aucun sens.
    final nouvelleRecherche = recherche ?? this.recherche;
    return DemandeDeRecus(
      recherche: nouvelleRecherche,
      page: recherche != null && recherche != this.recherche
          ? 1
          : (page ?? this.page),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DemandeDeRecus &&
      other.recherche == recherche &&
      other.page == page;

  @override
  int get hashCode => Object.hash(recherche, page);
}

final recusProvider = FutureProvider.family<PageDeRecus, DemandeDeRecus>((
  ref,
  demande,
) async {
  return ref.read(reportsRepositoryProvider).fetchRecus(
    recherche: demande.recherche,
    page: demande.page,
  );
});
