import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../data/students_repository.dart';
import '../domain/student.dart';

final studentsRepositoryProvider = Provider<StudentsRepository>((ref) {
  return StudentsRepository(ref.read(dioProvider));
});

final studentsProvider = FutureProvider<List<Student>>((ref) async {
  return ref.read(studentsRepositoryProvider).fetchStudents();
});
