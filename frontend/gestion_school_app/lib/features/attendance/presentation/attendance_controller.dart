import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/attendance_repository.dart';
import '../domain/attendance_item.dart';
import '../domain/attendance_stats.dart';
import '../domain/attendance_student.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepository(ref.read(dioProvider));
});

final attendanceStudentsProvider = FutureProvider<List<AttendanceStudent>>((
  ref,
) async {
  return ref.read(attendanceRepositoryProvider).fetchStudents();
});

final attendancesProvider = FutureProvider<List<AttendanceItem>>((ref) async {
  return ref.read(attendanceRepositoryProvider).fetchAttendances();
});

final attendanceMonthProvider = StateProvider<String?>((ref) => null);

final attendanceMonthlyStatsProvider = FutureProvider<AttendanceMonthlyStats>((
  ref,
) async {
  final month = ref.watch(attendanceMonthProvider);
  return ref.read(attendanceRepositoryProvider).fetchMonthlyStats(month: month);
});

final attendanceMutationProvider =
    StateNotifierProvider<AttendanceMutationController, AsyncValue<void>>((
      ref,
    ) {
      return AttendanceMutationController(ref);
    });

class AttendanceMutationController extends StateNotifier<AsyncValue<void>> {
  AttendanceMutationController(this.ref) : super(const AsyncValue.data(null));

  final Ref ref;

  Future<void> createAttendance({
    required int studentId,
    required String date,
    required bool isAbsent,
    required bool isLate,
    required String reason,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() {
      return ref
          .read(attendanceRepositoryProvider)
          .createAttendance(
            studentId: studentId,
            date: date,
            isAbsent: isAbsent,
            isLate: isLate,
            reason: reason,
          );
    });

    if (!state.hasError) {
      ref.invalidate(attendancesProvider);
      ref.invalidate(attendanceMonthlyStatsProvider);
    }
  }
}
