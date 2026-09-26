import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/activity_logs_repository.dart';
import '../domain/activity_log_models.dart';

export '../data/activity_logs_repository.dart' show FiltreDuJournal;

final activityLogsRepositoryProvider = Provider<ActivityLogsRepository>((ref) {
  return ActivityLogsRepository(ref.read(dioProvider));
});

/// Les lignes du journal pour un jeu de filtres donné.
///
/// L'écran gérait lui-même l'anti-rebond et un `CancelToken` pour annuler la
/// requête précédente. Riverpod le fait: une nouvelle clé de `family` remplace
/// l'ancienne, et la réponse d'un filtre abandonné n'écrase plus l'affichage.
final lignesDuJournalProvider =
    FutureProvider.family<List<LigneDuJournal>, FiltreDuJournal>((
      ref,
      filtre,
    ) async {
      return ref.read(activityLogsRepositoryProvider).fetchLignes(filtre);
    });

final repertoireDuJournalProvider = FutureProvider<RepertoireDuJournal>((ref) {
  return ref.read(activityLogsRepositoryProvider).fetchRepertoire();
});
