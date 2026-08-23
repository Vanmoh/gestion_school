/// La feuille d'appel, une ligne par eleve.
///
/// Chaque eleve occupait une carte entiere: nom, interrupteur « Absent »
/// pleine largeur, interrupteur « Retard », champ « Motif ». Faire l'appel
/// dans une classe de trente demandait de parcourir six ecrans.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/attendance/presentation/widgets/attendance_sheet_list.dart';

List<Map<String, dynamic>> _classe() => [
  {
    'student': 1,
    'student_full_name': 'COULIBALY Aminata',
    'student_matricule': 'GS-0001',
    'is_absent': false,
    'is_late': false,
    'reason': '',
  },
  {
    'student': 2,
    'student_full_name': 'DIALLO Boubacar',
    'student_matricule': 'GS-0002',
    'is_absent': true,
    'is_late': false,
    'reason': 'Maladie',
  },
  {
    'student': 3,
    'student_full_name': 'KEITA Fatou',
    'student_matricule': 'GS-0003',
    'is_absent': false,
    'is_late': true,
    'reason': '',
  },
];

Future<List<Map<String, dynamic>>> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>>? items,
  bool editable = true,
  Size taille = const Size(1280, 900),
}) async {
  final lignes = items ?? _classe();

  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: AttendanceSheetList(
              items: lignes,
              editable: editable,
              onPresenceChanged: (row, etat) => setState(() {
                final absent = etat == PresenceEleve.absent;
                row['is_absent'] = absent;
                if (!absent) row['reason'] = '';
              }),
              onRetardChanged: (row, r) => setState(() => row['is_late'] = r),
              onMotifChanged: (row, m) => row['reason'] = m,
              onToutPresent: () => setState(() {
                for (final row in lignes) {
                  row['is_absent'] = false;
                  row['reason'] = '';
                }
              }),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return lignes;
}

void main() {
  testWidgets('chaque eleve tient sur une ligne', (tester) async {
    await _pump(tester);

    expect(find.text('COULIBALY Aminata'), findsOneWidget);
    expect(find.text('DIALLO Boubacar'), findsOneWidget);
    expect(find.text('KEITA Fatou'), findsOneWidget);
    expect(find.text('GS-0001'), findsOneWidget);
  });

  testWidgets('le compte se lit sans attendre l_enregistrement', (
    tester,
  ) async {
    await _pump(tester);

    // Un absent, un retard: le retard reste present.
    expect(
      find.textContaining('2 présents  ·  1 absent  ·  1 retard'),
      findsOneWidget,
    );
  });

  testWidgets('« Tout présent » remet toute la classe presente', (
    tester,
  ) async {
    final lignes = await _pump(tester);

    await tester.tap(find.text('Tout présent'));
    await tester.pump();

    expect(lignes.every((l) => l['is_absent'] == false), isTrue);
    expect(find.textContaining('3 présents'), findsOneWidget);
  });

  testWidgets('repasser present efface le motif de l_absence', (tester) async {
    final lignes = await _pump(tester);
    expect(lignes[1]['reason'], 'Maladie');

    await tester.tap(find.text('Tout présent'));
    await tester.pump();

    // Le motif decrivait une absence qui n'existe plus; le garder
    // l'enregistrerait tel quel.
    expect(lignes[1]['reason'], '');
  });

  testWidgets('le motif n_apparait que pour les absents', (tester) async {
    await _pump(tester);

    // Une colonne motif vide sur vingt-huit lignes n'apprend rien.
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.tap(find.text('Tout présent'));
    await tester.pump();

    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('le retard reste independant de la presence', (tester) async {
    final lignes = await _pump(tester);

    // KEITA Fatou est presente ET en retard: fondre les deux en trois etats
    // exclusifs aurait change le sens des statistiques.
    expect(lignes[2]['is_absent'], isFalse);
    expect(lignes[2]['is_late'], isTrue);
  });

  testWidgets('une fiche verrouillee neutralise toute la liste', (
    tester,
  ) async {
    await _pump(tester, editable: false);

    final bouton = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Tout présent'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(bouton.onPressed, isNull);

    for (final caseACocher in tester.widgetList<Checkbox>(
      find.byType(Checkbox),
    )) {
      expect(caseACocher.onChanged, isNull);
    }
  });

  testWidgets('une classe vide n_offre pas « Tout présent »', (tester) async {
    await _pump(tester, items: []);

    final bouton = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Tout présent'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('sur ecran etroit, la liste s_empile sans colonnes', (
    tester,
  ) async {
    await _pump(tester, taille: const Size(500, 900));

    // Pas d'en-tete de colonnes: une ligne de tableau ne tiendrait pas, et on
    // ne veut pas d'un defilement lateral.
    expect(find.text('PRÉSENT'), findsNothing);
    expect(find.text('COULIBALY Aminata'), findsOneWidget);
  });

  testWidgets('sur grand ecran, les colonnes sont titrees', (tester) async {
    await _pump(tester);

    for (final titre in ['N°', 'ÉLÈVE', 'PRÉSENT', 'ABSENT', 'RETARD']) {
      expect(find.text(titre), findsOneWidget, reason: titre);
    }
  });
}
