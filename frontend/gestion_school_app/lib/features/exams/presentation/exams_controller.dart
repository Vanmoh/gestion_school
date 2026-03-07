import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/exams_repository.dart';
import '../domain/exam_models.dart';

final examsRepositoryProvider = Provider<ExamsRepository>((ref) {
  return ExamsRepository(ref.read(dioProvider));
});

final examSessionsProvider = FutureProvider<List<ExamSessionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchSessions();
});

final examPlanningsProvider = FutureProvider<List<ExamPlanningItem>>((
  ref,
) async {
  return ref.read(examsRepositoryProvider).fetchPlannings();
});

final examResultsProvider = FutureProvider<List<ExamResultItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchResults();
});

final examInvigilationsProvider = FutureProvider<List<ExamInvigilationItem>>((
  ref,
) async {
  return ref.read(examsRepositoryProvider).fetchInvigilations();
});

final examAcademicYearsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchAcademicYears();
});

final examClassroomsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchClassrooms();
});

final examSubjectsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchSubjects();
});

final examStudentsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchStudents();
});

final examSupervisorsProvider = FutureProvider<List<OptionItem>>((ref) async {
  return ref.read(examsRepositoryProvider).fetchSupervisors();
});

final examMutationProvider =
    StateNotifierProvider<ExamMutationController, AsyncValue<void>>((ref) {
      return ExamMutationController(ref);
    });

class ExamMutationController extends StateNotifier<AsyncValue<void>> {
  ExamMutationController(this.ref) : super(const AsyncValue.data(null));

  final Ref ref;

  Future<void> createSession({
    required String title,
    required int academicYear,
    required String startDate,
    required String endDate,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(examsRepositoryProvider)
          .createSession(
            title: title,
            academicYear: academicYear,
            startDate: startDate,
            endDate: endDate,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(examSessionsProvider);
    }
  }

  Future<void> createPlanning({
    required int session,
    required int classroom,
    required int subject,
    required String examDate,
    required String startTime,
    required String endTime,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(examsRepositoryProvider)
          .createPlanning(
            session: session,
            classroom: classroom,
            subject: subject,
            examDate: examDate,
            startTime: startTime,
            endTime: endTime,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(examPlanningsProvider);
    }
  }

  Future<void> createResult({
    required int session,
    required int student,
    required int subject,
    required double score,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(examsRepositoryProvider)
          .createResult(
            session: session,
            student: student,
            subject: subject,
            score: score,
          ),
    );
    if (!state.hasError) {
      ref.invalidate(examResultsProvider);
    }
  }

  Future<void> createInvigilation({
    required int planning,
    required int supervisor,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(examsRepositoryProvider)
          .createInvigilation(planning: planning, supervisor: supervisor),
    );
    if (!state.hasError) {
      ref.invalidate(examInvigilationsProvider);
    }
  }
}
