import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers/provider_cache.dart';
import '../data/students_repository.dart';
import '../domain/student.dart';

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  return StudentsRepository(ref.read(dioProvider));
});

final studentsProvider = FutureProvider.autoDispose<List<Student>>((ref) async {
  ref.cacheFor(const Duration(minutes: 3));
  return ref.read(studentsRepositoryProvider).fetchStudents();
});
