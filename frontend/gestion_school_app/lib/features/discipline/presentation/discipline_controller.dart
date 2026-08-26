import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/discipline_repository.dart';

final disciplineRepositoryProvider = Provider<DisciplineRepository>((ref) {
  return DisciplineRepository(ref.read(dioProvider));
});
