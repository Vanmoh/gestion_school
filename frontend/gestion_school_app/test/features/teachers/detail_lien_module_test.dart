/// Le lien « Ouvrir le module » au pied du detail d'un indicateur.
///
/// Le detail sert a regarder; ecrire se fait dans le module concerne. Le lien
/// y mene en portant ce qu'il faut pour y arriver au bon endroit: sans cela,
/// le module des emargements s'ouvrait sur le premier enseignant de sa liste
/// et il fallait rechercher celui qu'on venait de quitter.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/providers/navigation_intents.dart';
import 'package:gestion_school_app/features/teachers/presentation/widgets/detail_indicateur_dialog.dart';

Future<ProviderContainer> _ouvrir(
  WidgetTester tester, {
  String? libelleModule,
  VoidCallback? onOuvrirModule,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => DetailIndicateurDialog.ouvrir(
                context,
                icone: Icons.how_to_reg_outlined,
                titre: 'Émargement · Amadou DIALLO',
                resume: '3 pointages',
                corps: const Text('corps'),
                libelleModule: libelleModule,
                onOuvrirModule: onOuvrirModule,
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('DetailIndicateurDialog', () {
    testWidgets('le titre et le rappel du nombre sont la', (tester) async {
      // On doit retrouver le nombre sur lequel on a clique.
      await _ouvrir(tester);

      expect(find.text('Émargement · Amadou DIALLO'), findsOneWidget);
      expect(find.text('3 pointages'), findsOneWidget);
    });

    testWidgets('sans module cible, aucun lien ne parait', (tester) async {
      await _ouvrir(tester);

      expect(find.textContaining('Ouvrir'), findsNothing);
      expect(find.text('Fermer'), findsOneWidget);
    });

    testWidgets('le lien referme le detail avant de naviguer', (tester) async {
      // Laisser le dialogue ouvert par-dessus le module d'arrivee masquerait
      // ce qu'on vient chercher.
      var navigations = 0;
      await _ouvrir(
        tester,
        libelleModule: 'Ouvrir les émargements',
        onOuvrirModule: () => navigations++,
      );

      await tester.tap(find.text('Ouvrir les émargements'));
      await tester.pumpAndSettle();

      expect(navigations, 1);
      expect(find.text('Émargement · Amadou DIALLO'), findsNothing);
    });

    testWidgets('fermer ne declenche aucune navigation', (tester) async {
      var navigations = 0;
      await _ouvrir(
        tester,
        libelleModule: 'Ouvrir les émargements',
        onOuvrirModule: () => navigations++,
      );

      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      expect(navigations, 0);
    });
  });

  group('intentions de navigation', () {
    test('elles partent vides et se laissent poser', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Vides au depart: une intention residuelle detournerait la premiere
      // visite du module.
      expect(container.read(teacherTimesheetFocusProvider), isNull);
      expect(container.read(timetableTeacherViewIntentProvider), isFalse);

      container.read(teacherTimesheetFocusProvider.notifier).state = 42;
      container.read(timetableTeacherViewIntentProvider.notifier).state = true;

      expect(container.read(teacherTimesheetFocusProvider), 42);
      expect(container.read(timetableTeacherViewIntentProvider), isTrue);
    });
  });
}
