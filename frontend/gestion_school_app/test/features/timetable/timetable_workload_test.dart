import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/timetable/presentation/timetable_workload.dart';

void main() {
  group('buildTeacherWorkloadRows', () {
    test('aggregates slots per teacher with class count and level', () {
      final teachers = <Map<String, dynamic>>[
        {
          'id': 1,
          'employee_code': 'ENS-001',
          'user_first_name': 'Marie',
          'user_last_name': 'Diallo',
          'user_username': 'marie',
        },
        {
          'id': 2,
          'employee_code': 'ENS-002',
          'user_first_name': 'Moussa',
          'user_last_name': 'Keita',
          'user_username': 'moussa',
        },
      ];

      final assignmentById = <int, Map<String, dynamic>>{
        11: {
          'id': 11,
          'teacher': 1,
          'classroom': 101,
          'teacherCode': 'ENS-001',
        },
        12: {
          'id': 12,
          'teacher': 1,
          'classroom': 102,
          'teacherCode': 'ENS-001',
        },
        21: {
          'id': 21,
          'teacher': 2,
          'classroom': 101,
          'teacherCode': 'ENS-002',
        },
      };

      final slots = <Map<String, dynamic>>[
        {
          'id': 1,
          'assignment': 11,
          'day_of_week': 'MON',
          'start_time': '08:00:00',
          'end_time': '10:00:00',
        },
        {
          'id': 2,
          'assignment': 12,
          'day_of_week': 'TUE',
          'start_time': '09:00:00',
          'end_time': '12:00:00',
        },
        {
          'id': 3,
          'assignment': 21,
          'day_of_week': 'MON',
          'start_time': '08:00:00',
          'end_time': '09:00:00',
        },
      ];

      final rows = buildTeacherWorkloadRows(
        teachers: teachers,
        assignmentById: assignmentById,
        scheduleSlots: slots,
      );

      expect(rows, hasLength(2));
      expect(rows.first.teacherCode, 'ENS-001');
      expect(rows.first.teacherName, 'Marie Diallo');
      expect(rows.first.slotCount, 2);
      expect(rows.first.classCount, 2);
      expect(rows.first.totalMinutes, 300);
      expect(rows.first.totalHours, closeTo(5.0, 0.0001));
      expect(rows.first.level, 'Equilibre');

      expect(rows.last.teacherCode, 'ENS-002');
      expect(rows.last.totalMinutes, 60);
    });

    test('applies classroom filter correctly', () {
      final teachers = <Map<String, dynamic>>[
        {
          'id': 1,
          'employee_code': 'ENS-001',
          'user_first_name': 'Marie',
          'user_last_name': 'Diallo',
        },
      ];

      final assignmentById = <int, Map<String, dynamic>>{
        11: {
          'id': 11,
          'teacher': 1,
          'classroom': 101,
          'teacherCode': 'ENS-001',
        },
        12: {
          'id': 12,
          'teacher': 1,
          'classroom': 102,
          'teacherCode': 'ENS-001',
        },
      };

      final slots = <Map<String, dynamic>>[
        {
          'id': 1,
          'assignment': 11,
          'day_of_week': 'MON',
          'start_time': '08:00:00',
          'end_time': '10:00:00',
        },
        {
          'id': 2,
          'assignment': 12,
          'day_of_week': 'TUE',
          'start_time': '09:00:00',
          'end_time': '12:00:00',
        },
      ];

      final rows = buildTeacherWorkloadRows(
        teachers: teachers,
        assignmentById: assignmentById,
        scheduleSlots: slots,
        classroomFilter: 101,
      );

      expect(rows, hasLength(1));
      expect(rows.first.totalMinutes, 120);
      expect(rows.first.classCount, 1);
    });

    test('returns overload level based on thresholds', () {
      expect(teacherLoadLevelFromMinutes(26 * 60), 'Surcharge');
      expect(teacherLoadLevelFromMinutes(20 * 60), 'A surveiller');
      expect(teacherLoadLevelFromMinutes(19 * 60 + 59), 'Equilibre');
    });
  });
}
