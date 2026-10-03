import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_stats.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.read(dioProvider));
});

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  return ref.read(dashboardRepositoryProvider).fetchStats();
});

/// Le rapport financier de l'année, mois par mois.
///
/// Séparé des compteurs du mois: il vise une autre période, coûte une
/// agrégation de plus, et l'écran doit pouvoir afficher les compteurs même
/// si ce rapport échoue.
final financesAnnuellesProvider = FutureProvider<FinancesAnnuelles>((ref) async {
  return ref.read(dashboardRepositoryProvider).fetchFinancesAnnuelles();
});

/// L'échéancier de l'année contre les encaissements.
///
/// Séparé des compteurs pour la même raison que le rapport financier: la page
/// doit afficher ses quatre chiffres même si cette agrégation échoue. Un
/// tableau de bord qui s'efface en entier parce qu'une courbe manque est
/// moins utile qu'un tableau de bord amputé d'une courbe.
final echeancierProvider = FutureProvider<Echeancier>((ref) async {
  return ref.read(dashboardRepositoryProvider).fetchEcheancier();
});


/// Qui est en ligne, rafraîchi toutes les quinze secondes par l'écran.
///
/// Séparé des compteurs: ceux-ci coûtent une quinzaine d'agrégations et sont
/// mis en cache soixante secondes côté serveur, alors que la présence est une
/// requête légère qui doit rester fraîche. Un rôle sans droit sur le module
/// `users` reçoit 403, et l'écran se contente alors de ne pas peindre le
/// bandeau.
final presenceProvider = FutureProvider<PresenceParRole>((ref) async {
  return ref.read(dashboardRepositoryProvider).fetchPresence();
});
