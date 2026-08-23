/// L'en-tete extrait de la page, verifiable sans monter ses trente controleurs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/students/domain/students_stats.dart';
import 'package:gestion_school_app/features/students/presentation/widgets/students_dashboard_card.dart';

Future<void> _pump(
  WidgetTester tester, {
  StudentsStats stats = const StudentsStats(
    total: 40,
    active: 37,
    archived: 3,
    newThisYear: 12,
    genderMissing: 0,
    academicYear: '2025-2026',
  ),
  bool saving = false,
  bool readOnly = false,
  VoidCallback? onAddStudent,
}) async {
  tester.view.physicalSize = const Size(1400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StudentsDashboardCard(
          stats: stats,
          activeYearLabel: '2025-2026',
          classCount: 5,
          scopeLabel: 'LTOB',
          refreshLabel: 'Maj: 23:53',
          isCompactLayout: false,
          saving: saving,
          readOnly: readOnly,
          onRefresh: () {},
          onAddStudent: onAddStudent ?? () {},
          onOpenByClass: () {},
          onOpenClassCards: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _actif(WidgetTester tester, String label) {
  final bouton = tester.widget<ButtonStyleButton>(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
  return bouton.onPressed != null;
}

void main() {
  testWidgets('l_en-tete resume l_etablissement', (tester) async {
    await _pump(tester);

    expect(find.text('Tableau de bord élèves'), findsOneWidget);
    expect(find.text('Année: 2025-2026'), findsOneWidget);
    expect(find.text('5 classes'), findsOneWidget);
    expect(
      find.text('37 actifs · 3 archivés · 12 nouveaux'),
      findsOneWidget,
    );
    expect(find.text('LTOB'), findsOneWidget);
  });

  testWidgets('des effectifs absents se disent, ils ne s_affichent pas a zero', (
    tester,
  ) async {
    await _pump(tester, stats: const StudentsStats.empty());

    // « 0 actifs » se lirait comme une ecole vide, pas comme une reponse
    // qui n'est pas encore arrivee.
    expect(find.text('Effectifs indisponibles'), findsOneWidget);
    expect(find.textContaining('0 actifs'), findsNothing);
  });

  testWidgets('en lecture seule, Ajouter eleve est grise et porte son motif', (
    tester,
  ) async {
    await _pump(tester, readOnly: true);

    expect(_actif(tester, 'Ajouter élève'), isFalse);

    final infobulle = tester.widget<Tooltip>(
      find.ancestor(
        of: find.text('Ajouter élève'),
        matching: find.byType(Tooltip),
      ),
    );
    expect(infobulle.message, contains('sans les modifier'));
  });

  testWidgets('en ecriture, Ajouter eleve est actif', (tester) async {
    await _pump(tester);

    expect(_actif(tester, 'Ajouter élève'), isTrue);
  });

  testWidgets('un enregistrement en cours neutralise les actions', (
    tester,
  ) async {
    await _pump(tester, saving: true);

    expect(_actif(tester, 'Ajouter élève'), isFalse);
    expect(_actif(tester, 'Actualiser'), isFalse);
  });

  testWidgets('le rappel Ajouter eleve est bien transmis', (tester) async {
    var appele = false;
    await _pump(tester, onAddStudent: () => appele = true);

    await tester.tap(find.text('Ajouter élève'));
    await tester.pump();

    expect(appele, isTrue);
  });

  testWidgets('l_en-tete ne porte plus les actions visant un eleve', (
    tester,
  ) async {
    await _pump(tester);

    // Elles ont rejoint la palette: les laisser ici obligeait a remonter en
    // haut de page pour agir sur l'eleve qu'on avait sous les yeux.
    for (final parti in ['Historique', 'Incident', 'Absence', 'Frais', 'Paiement']) {
      expect(find.text(parti), findsNothing, reason: parti);
    }
  });
}
