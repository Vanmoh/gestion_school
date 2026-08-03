import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/students/domain/students_sort.dart';

void main() {
  group('studentSortKeyForColumn', () {
    test('maps sortable columns to their sort key', () {
      expect(studentSortKeyForColumn(2), 'matricule');
      expect(studentSortKeyForColumn(3), 'name');
      expect(studentSortKeyForColumn(4), 'gender');
      expect(studentSortKeyForColumn(5), 'classroom');
      expect(studentSortKeyForColumn(6), 'birth');
      expect(studentSortKeyForColumn(8), 'status');
    });

    test('returns null for columns without a server ordering', () {
      // 0 = cases a cocher, 1 = numero de ligne, 7 = telephone, 9 = acces.
      for (final index in [0, 1, 7, 9]) {
        expect(
          studentSortKeyForColumn(index),
          isNull,
          reason: 'la colonne $index ne doit pas etre triable',
        );
      }
    });
  });

  group('studentSortColumnIndex', () {
    test('is the inverse of studentSortKeyForColumn', () {
      for (final entry in studentSortKeyByColumnIndex.entries) {
        expect(studentSortColumnIndex(entry.value), entry.key);
      }
    });

    test('points at the full-name column for the default sort key', () {
      expect(studentSortColumnIndex(defaultStudentSortKey), 3);
    });

    test('returns null for an unknown sort key', () {
      expect(studentSortColumnIndex('inconnu'), isNull);
    });
  });

  group('studentsOrdering', () {
    test('maps each sort key to its API field', () {
      expect(
        studentsOrdering(sortKey: 'matricule', ascending: true),
        'matricule',
      );
      expect(
        studentsOrdering(sortKey: 'classroom', ascending: true),
        'classroom__name',
      );
      expect(studentsOrdering(sortKey: 'status', ascending: true), 'is_archived');
      expect(
        studentsOrdering(sortKey: 'name', ascending: true),
        'user__last_name',
      );
      expect(studentsOrdering(sortKey: 'gender', ascending: true), 'gender');
      expect(studentsOrdering(sortKey: 'birth', ascending: true), 'birth_date');
    });

    test('falls back to the name ordering for an unknown key', () {
      expect(
        studentsOrdering(sortKey: 'inconnu', ascending: true),
        'user__last_name',
      );
    });

    test('prefixes the field with a dash when descending', () {
      expect(
        studentsOrdering(sortKey: 'matricule', ascending: false),
        '-matricule',
      );
      expect(
        studentsOrdering(sortKey: 'classroom', ascending: false),
        '-classroom__name',
      );
    });
  });
}
