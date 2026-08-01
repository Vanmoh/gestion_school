import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/widgets/frozen_column_table.dart';

Widget _harness({double viewportWidth = 300}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: viewportWidth,
          child: FrozenColumnTable(
            frozenColumnWidth: 100,
            columnWidth: 150,
            frozenHeader: const Text('Horaire'),
            headers: const [
              Text('Lundi'),
              Text('Mardi'),
              Text('Mercredi'),
              Text('Jeudi'),
            ],
            frozenCells: const [Text('08:00-09:00'), Text('09:00-10:00')],
            rows: const [
              [Text('L1'), Text('M1'), Text('W1'), Text('J1')],
              [Text('L2'), Text('M2'), Text('W2'), Text('J2')],
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the frozen column and every scrollable column', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    expect(find.text('Horaire'), findsOneWidget);
    expect(find.text('08:00-09:00'), findsOneWidget);
    expect(find.text('09:00-10:00'), findsOneWidget);
    expect(find.text('Jeudi'), findsOneWidget);
    expect(find.text('J2'), findsOneWidget);
  });

  testWidgets('keeps the frozen column pinned to the left while scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final tableLeft = tester.getTopLeft(find.byType(FrozenColumnTable)).dx;
    final beforeScroll = tester.getTopLeft(find.text('08:00-09:00')).dx;

    // Le contenu total (100 + 4 * 150 = 700) depasse largement le viewport.
    await tester.drag(find.text('Lundi'), const Offset(-250, 0));
    await tester.pumpAndSettle();

    final scrollable = tester.widget<Scrollable>(
      find.descendant(
        of: find.byType(FrozenColumnTable),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.controller!.offset, greaterThan(0));

    final afterScroll = tester.getTopLeft(find.text('08:00-09:00')).dx;
    expect(afterScroll, closeTo(beforeScroll, 0.5));
    // Bord gauche du tableau + bordure (1) + padding horizontal de cellule (10).
    expect(afterScroll, closeTo(tableLeft + 11, 0.5));
  });

  testWidgets('scrollable cells do move while the frozen column stays put', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final before = tester.getTopLeft(find.text('L1')).dx;
    await tester.drag(find.text('Lundi'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('L1')).dx;

    expect(after, lessThan(before));
  });

  testWidgets('asserts when frozen cells and rows have different lengths', (
    tester,
  ) async {
    expect(
      () => FrozenColumnTable(
        frozenHeader: const Text('Horaire'),
        headers: const [Text('Lundi')],
        frozenCells: const [Text('08:00')],
        rows: const [
          [Text('L1')],
          [Text('L2')],
        ],
      ),
      throwsAssertionError,
    );
  });
}
