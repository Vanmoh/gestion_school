/// Les filtres du journal des fiches d'appel.
///
/// Le serveur savait filtrer par classe et par periode depuis l'origine, mais
/// rien ne l'offrait a l'ecran: retrouver la fiche de mardi en fevrier
/// demandait de faire defiler des centaines de lignes, et le plafond du
/// serveur rendait les plus anciennes inatteignables.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/attendance/presentation/widgets/attendance_journal_filters.dart';

List<Map<String, dynamic>> _classes() => [
  {'id': 7, 'name': '6e A'},
  {'id': 8, 'name': '5e B'},
];

/// Ce que l'ecran a demande au serveur, pour verifier non seulement qu'on a
/// clique mais ce que le clic a change.
class _Appels {
  final List<int?> classes = [];
  final List<DateTime?> du = [];
  final List<DateTime?> au = [];
  int reinitialisations = 0;
}

Future<_Appels> _pump(
  WidgetTester tester, {
  int? classeSelectionnee,
  DateTime? du,
  DateTime? au,
  int nombreFiches = 12,
  bool listeTronquee = false,
  bool actif = true,
}) async {
  final appels = _Appels();

  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AttendanceJournalFilters(
            classes: _classes(),
            classeSelectionnee: classeSelectionnee,
            du: du,
            au: au,
            nombreFiches: nombreFiches,
            listeTronquee: listeTronquee,
            actif: actif,
            onClasseChangee: appels.classes.add,
            onDuChange: appels.du.add,
            onAuChange: appels.au.add,
            onReinitialiser: () => appels.reinitialisations++,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return appels;
}

void main() {
  group('AttendanceJournalFilters', () {
    testWidgets('sans filtre, il propose toutes les classes', (tester) async {
      await _pump(tester);

      expect(find.text('Toutes les classes'), findsOneWidget);
      // Rien a reinitialiser tant que rien n'est filtre.
      expect(find.text('Réinitialiser'), findsNothing);
    });

    testWidgets('choisir une classe la remonte a l\'ecran', (tester) async {
      final appels = await _pump(tester);

      await tester.tap(find.text('Toutes les classes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5e B').last);
      await tester.pumpAndSettle();

      expect(appels.classes, [8]);
    });

    testWidgets('un filtre pose ouvre le retour en arriere', (tester) async {
      final appels = await _pump(tester, classeSelectionnee: 7);

      expect(find.text('Réinitialiser'), findsOneWidget);

      await tester.tap(find.text('Réinitialiser'));
      await tester.pump();

      expect(appels.reinitialisations, 1);
    });

    testWidgets('les dates posees s\'affichent au format d\'ici', (
      tester,
    ) async {
      await _pump(
        tester,
        du: DateTime(2026, 3, 12),
        au: DateTime(2026, 3, 20),
      );

      // L'API parle ISO, le surveillant lit le format d'ici.
      expect(find.text('Du 12/03/2026'), findsOneWidget);
      expect(find.text('Au 20/03/2026'), findsOneWidget);
    });

    testWidgets('une date posee peut s\'effacer seule', (tester) async {
      final appels = await _pump(tester, du: DateTime(2026, 3, 12));

      // Effacer « Du » ne doit pas emporter « Au »: les deux bornes se
      // reglent separement.
      expect(find.byTooltip('Effacer Au'), findsNothing);
      await tester.tap(find.byTooltip('Effacer Du'));
      await tester.pump();

      expect(appels.du, [null]);
      expect(appels.au, isEmpty);
    });

    testWidgets('le nombre de fiches est annonce, et son filtrage aussi', (
      tester,
    ) async {
      await _pump(tester, nombreFiches: 12);
      expect(find.text('12 fiches'), findsOneWidget);

      await _pump(tester, nombreFiches: 12, classeSelectionnee: 7);
      expect(find.text('12 fiches (filtrées)'), findsOneWidget);
    });

    testWidgets('une fiche unique ne prend pas de pluriel', (tester) async {
      await _pump(tester, nombreFiches: 1);

      expect(find.text('1 fiche'), findsOneWidget);
    });

    testWidgets('une liste coupee le dit au lieu de paraitre complete', (
      tester,
    ) async {
      // Le serveur plafonne sa reponse: sans cet avertissement, une fiche
      // ancienne mais existante passerait pour absente.
      await _pump(tester, nombreFiches: 400, listeTronquee: true);

      expect(find.textContaining('Liste tronquée'), findsOneWidget);
    });

    testWidgets('une liste complete n\'affiche pas l\'avertissement', (
      tester,
    ) async {
      await _pump(tester, nombreFiches: 399);

      expect(find.textContaining('Liste tronquée'), findsNothing);
    });

    testWidgets('pendant un chargement, les filtres ne repondent plus', (
      tester,
    ) async {
      // Enchainer deux filtres sur une requete en vol ferait revenir les
      // reponses dans le desordre.
      final appels = await _pump(tester, classeSelectionnee: 7, actif: false);

      await tester.tap(find.text('Réinitialiser'));
      await tester.pump();

      expect(appels.reinitialisations, 0);
    });
  });
}
