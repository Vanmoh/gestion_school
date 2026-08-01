import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/discipline/domain/parent_discipline_grouping.dart';

Map<String, dynamic> incident({
  required String student,
  String name = '',
  String matricule = '',
  String date = '2026-01-10',
  String status = 'open',
}) {
  return <String, dynamic>{
    'student': student,
    'student_full_name': name,
    'student_matricule': matricule,
    'incident_date': date,
    'status': status,
  };
}

void main() {
  group('groupIncidentsByChild', () {
    test('groups incidents per child and sorts groups by child name', () {
      final groups = groupIncidentsByChild([
        incident(student: '2', name: 'Zara Diallo', matricule: 'M002'),
        incident(student: '1', name: 'Ali Traore', matricule: 'M001'),
        incident(student: '1', name: 'Ali Traore', matricule: 'M001'),
      ]);

      expect(groups.map((g) => g.childName), ['Ali Traore', 'Zara Diallo']);
      expect(groups.first.incidents.length, 2);
      expect(groups.first.matricule, 'M001');
      expect(groups.last.incidents.length, 1);
    });

    test('sorts each child incidents from most recent to oldest', () {
      final groups = groupIncidentsByChild([
        incident(student: '1', name: 'Ali', date: '2026-01-05'),
        incident(student: '1', name: 'Ali', date: '2026-03-20'),
        incident(student: '1', name: 'Ali', date: '2026-02-11'),
      ]);

      expect(
        groups.single.incidents.map((row) => row['incident_date']),
        ['2026-03-20', '2026-02-11', '2026-01-05'],
      );
    });

    test('keeps the first non-empty name and matricule of a child', () {
      final groups = groupIncidentsByChild([
        incident(student: '1', name: '', matricule: ''),
        incident(student: '1', name: 'Ali Traore', matricule: 'M001'),
      ]);

      expect(groups.single.childName, 'Ali Traore');
      expect(groups.single.matricule, 'M001');
    });

    test('falls back to a generic label when no name is available', () {
      final groups = groupIncidentsByChild([incident(student: '7')]);

      expect(groups.single.childName, 'Eleve');
      expect(groups.single.matricule, '');
    });

    test('pushes incidents with an invalid date to the end without throwing', () {
      final groups = groupIncidentsByChild([
        incident(student: '1', name: 'Ali', date: 'pas-une-date'),
        incident(student: '1', name: 'Ali', date: '2026-02-11'),
      ]);

      expect(
        groups.single.incidents.map((row) => row['incident_date']),
        ['2026-02-11', 'pas-une-date'],
      );
    });

    test('openCount ignores resolved incidents', () {
      final groups = groupIncidentsByChild([
        incident(student: '1', name: 'Ali', status: 'resolved'),
        incident(student: '1', name: 'Ali', status: 'open'),
        incident(student: '1', name: 'Ali', status: ''),
      ]);

      expect(groups.single.incidents.length, 3);
      expect(groups.single.openCount, 2);
    });

    test('returns an empty list when there is no incident', () {
      expect(groupIncidentsByChild(const []), isEmpty);
    });
  });

  group('incidentStatus', () {
    test('defaults to open when missing or blank', () {
      expect(incidentStatus(const {}), 'open');
      expect(incidentStatus(const {'status': '   '}), 'open');
      expect(incidentStatus(const {'status': 'resolved'}), 'resolved');
    });
  });
}
