import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/academic_imports_repository.dart';

final academicImportsRepositoryProvider = Provider<AcademicImportsRepository>((
  ref,
) {
  return AcademicImportsRepository(ref.read(dioProvider));
});