/// L'en-tete de l'emargement des eleves.
///
/// La rubrique ouvrait sur un ExpansionTile replie nomme « Statistiques
/// mensuelles » -- ni titre, ni bouton d'actualisation, ni indication de
/// perimetre ou de fraicheur, la ou « Gestion des eleves » et
/// « Enseignants » ouvrent tous deux sur un tableau de bord.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/attendance/domain/attendance_stats.dart';
import 'package:gestion_school_app/features/attendance/presentation/widgets/attendance_dashboard_card.dart';

AttendanceMonthlyStats _stats() => const AttendanceMonthlyStats(
  month: '2026-08',
  totalRecords: 142,
  absences: 9,
  lates: 4,
  justifications: 3,
  daily: [
    AttendanceDailyStat(date: '2026-08-03', absences: 2, lates: 1),
    AttendanceDailyStat(date: '2026-08-04', absences: 7, lates: 3),
  ],
);

/// Compteur partage: une valeur rendue au retour serait figee a zero, le
/// tap ayant lieu apres.
final List<int> _rechargements = [];

Future<void> _pump(
  WidgetTester tester, {
  AttendanceMonthlyStats? stats,
  String? statsError,
  bool loading = false,
  bool readOnly = false,
  Widget? courbe,
  Size taille = const Size(1280, 900),
}) async {
  _rechargements.clear();

  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AttendanceDashboardCard(
            stats: stats,
            statsError: statsError,
            classCount: 6,
            scopeLabel: 'Lycée Technique',
            refreshLabel: 'Maj: 08:42',
            isCompactLayout: false,
            loading: loading,
            readOnly: readOnly,
            onRefresh: () => _rechargements.add(1),
            courbe: courbe,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('la rubrique se nomme et se situe', (tester) async {
    await _pump(tester, stats: _stats());

    expect(find.text('Émargement élèves'), findsOneWidget);
    expect(find.text('Lycée Technique'), findsOneWidget);
    expect(find.text('6 classes'), findsOneWidget);
    expect(find.text('Mois: 2026-08'), findsOneWidget);
    expect(find.text('Maj: 08:42'), findsOneWidget);
  });

  testWidgets('les quatre compteurs du mois sont lisibles', (tester) async {
    await _pump(tester, stats: _stats());

    expect(find.text('142'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Justificatifs'), findsOneWidget);
  });

  testWidgets('sans reponse du serveur un tiret, pas un zero', (tester) async {
    await _pump(tester, stats: null, loading: true);

    // Un zero se lirait comme un mois sans absence.
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('0'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('une erreur de statistiques se dit', (tester) async {
    await _pump(tester, stats: null, statsError: 'Serveur injoignable');

    expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    expect(find.text('Enregistrements'), findsNothing);
  });

  testWidgets('actualiser recharge, sauf pendant un chargement', (
    tester,
  ) async {
    await _pump(tester, stats: _stats());
    await tester.tap(find.text('Actualiser'));
    await tester.pump();

    expect(_rechargements, hasLength(1));

    final bouton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Actualiser'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(bouton.onPressed, isNotNull);

    await _pump(tester, stats: _stats(), loading: true);
    final pendant = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Actualiser'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(pendant.onPressed, isNull);
  });

  testWidgets('la courbe reste repliee: l_appel du jour passe avant', (
    tester,
  ) async {
    await _pump(
      tester,
      stats: _stats(),
      courbe: const SizedBox(key: ValueKey('courbe'), height: 180),
    );

    expect(find.text('Courbe du mois'), findsOneWidget);
    expect(find.byKey(const ValueKey('courbe')), findsNothing);

    await tester.tap(find.text('Courbe du mois'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('courbe')), findsOneWidget);
  });

  testWidgets('un profil en lecture seule le sait', (tester) async {
    await _pump(tester, stats: _stats(), readOnly: true);

    expect(find.textContaining('lecture seule'), findsOneWidget);
  });
}
