import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/fee_schedules_repository.dart';
import '../domain/fee_schedule.dart';

final feeSchedulesRepositoryProvider = Provider<FeeSchedulesRepository>((ref) {
  return FeeSchedulesRepository(ref.read(dioProvider));
});

/// Les barèmes de l'année active.
///
/// Sans `cacheFor` ici, contrairement aux paiements: la liste change à chaque
/// application, et un barème appliqué doit se voir tout de suite.
final feeSchedulesProvider =
    FutureProvider.autoDispose<List<FeeSchedule>>((ref) async {
  return ref.read(feeSchedulesRepositoryProvider).fetchSchedules();
});
