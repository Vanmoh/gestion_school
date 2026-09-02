import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/discipline/domain/discipline_incident.dart';
import 'package:gestion_school_app/features/discipline/domain/parent_discipline_grouping.dart';

DisciplineIncident incident({
  required int student,
  String name = '',
  String matricule = '',
  String date = '2026-01-10',
  String status = 'open',
}) {
  return DisciplineIncident(
    id: 0,
    studentId: student,
    studentFullName: name,
    studentMatricule: matricule,
    incidentDate: date,
    category: 'indiscipline',
    description: '',
    status: status,
  );
}

void main() {
  group('groupIncidentsByChild', () {
    test('groups incidents per child and sorts groups by child name', () {
      final groups = groupIncidentsByChild([
        incident(student: 2, name: 'Zara Diallo', matricule: 'M002'),
        incident(student: 1, name: 'Ali Traore', matricule: 'M001'),
        incident(student: 1, name: 'Ali Traore', matricule: 'M001'),
      ]);

      expect(groups.map((g) => g.childName), ['Ali Traore', 'Zara Diallo']);
      expect(groups.first.incidents.length, 2);
      expect(groups.first.matricule, 'M001');
      expect(groups.last.incidents.length, 1);
    });

    test('sorts each child incidents from most recent to oldest', () {
      final groups = groupIncidentsByChild([
        incident(student: 1, name: 'Ali', date: '2026-01-05'),
        incident(student: 1, name: 'Ali', date: '2026-03-20'),
        incident(student: 1, name: 'Ali', date: '2026-02-11'),
      ]);

      expect(
        groups.single.incidents.map((row) => row.incidentDate),
        ['2026-03-20', '2026-02-11', '2026-01-05'],
      );
    });

    test('keeps the first non-empty name and matricule of a child', () {
      final groups = groupIncidentsByChild([
        incident(student: 1, name: '', matricule: ''),
        incident(student: 1, name: 'Ali Traore', matricule: 'M001'),
      ]);

      expect(groups.single.childName, 'Ali Traore');
      expect(groups.single.matricule, 'M001');
    });

    test('falls back to a generic label when no name is available', () {
      final groups = groupIncidentsByChild([incident(student: 7)]);

      expect(groups.single.childName, 'Élève');
      expect(groups.single.matricule, '');
    });

    test('pushes incidents with an invalid date to the end without throwing', () {
      final groups = groupIncidentsByChild([
        incident(student: 1, name: 'Ali', date: 'pas-une-date'),
        incident(student: 1, name: 'Ali', date: '2026-02-11'),
      ]);

      expect(
        groups.single.incidents.map((row) => row.incidentDate),
        ['2026-02-11', 'pas-une-date'],
      );
    });

    test('openCount ignores resolved incidents', () {
      final groups = groupIncidentsByChild([
        incident(student: 1, name: 'Ali', status: 'resolved'),
        incident(student: 1, name: 'Ali', status: 'open'),
        incident(student: 1, name: 'Ali', status: ''),
      ]);

      expect(groups.single.incidents.length, 3);
      expect(groups.single.openCount, 2);
    });

    test('returns an empty list when there is no incident', () {
      expect(groupIncidentsByChild(const []), isEmpty);
    });
  });

  group('DisciplineIncident', () {
    test('un statut absent ou vide vaut ouvert', () {
      expect(DisciplineIncident.fromJson(const {}).estOuvert, isTrue);
      expect(
        DisciplineIncident.fromJson(const {'status': ''}).estOuvert,
        isTrue,
      );
      expect(
        DisciplineIncident.fromJson(const {'status': 'resolved'}).estOuvert,
        isFalse,
      );
    });

    test('le libelle du motif vient du serveur, avec repli sur le code', () {
      const servi = DisciplineIncident(
        id: 1,
        studentId: 1,
        incidentDate: '2026-01-10',
        category: 'absence_injustifiee',
        categoryLabel: 'Absence injustifiee',
        description: '',
      );
      expect(servi.libelleMotif, 'Absence injustifiee');

      const sansLibelle = DisciplineIncident(
        id: 1,
        studentId: 1,
        incidentDate: '2026-01-10',
        category: 'retard',
        description: '',
      );
      expect(sansLibelle.libelleMotif, 'retard');
    });

    test('la date de cloture se lit au jour, et reste vide sans cloture', () {
      const clos = DisciplineIncident(
        id: 1,
        studentId: 1,
        incidentDate: '2026-01-10',
        category: 'retard',
        description: '',
        status: 'resolved',
        resolvedAt: '2026-01-12T09:31:00Z',
      );
      expect(clos.jourDeCloture, '2026-01-12');

      const ouvert = DisciplineIncident(
        id: 1,
        studentId: 1,
        incidentDate: '2026-01-10',
        category: 'retard',
        description: '',
      );
      expect(ouvert.jourDeCloture, '');
    });
  });
}
