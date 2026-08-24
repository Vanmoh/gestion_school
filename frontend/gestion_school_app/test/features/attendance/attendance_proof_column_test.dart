/// Le justificatif d'absence sur la feuille d'appel.
///
/// Le champ existait en base depuis l'origine et les statistiques mensuelles
/// comptaient deja les justificatifs, mais aucun ecran ne permettait d'en
/// deposer un: le compteur affichait zero en permanence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/attendance/presentation/widgets/attendance_sheet_list.dart';

List<Map<String, dynamic>> _classe() => [
  {
    'student': 1,
    'attendance_id': 11,
    'student_full_name': 'COULIBALY Aminata',
    'student_matricule': 'GS-0001',
    'is_absent': true,
    'is_late': false,
    'reason': 'Maladie',
    'has_proof': true,
    'proof_name': 'certificat.pdf',
  },
  {
    'student': 2,
    'attendance_id': 12,
    'student_full_name': 'DIALLO Boubacar',
    'student_matricule': 'GS-0002',
    'is_absent': true,
    'is_late': false,
    'reason': '',
    'has_proof': false,
  },
  {
    // Absence saisie mais fiche pas encore enregistree: rien a quoi
    // attacher un fichier.
    'student': 3,
    'attendance_id': null,
    'student_full_name': 'KEITA Fatou',
    'student_matricule': 'GS-0003',
    'is_absent': true,
    'is_late': false,
    'reason': '',
    'has_proof': false,
  },
  {
    'student': 4,
    'attendance_id': null,
    'student_full_name': 'TRAORE Salif',
    'student_matricule': 'GS-0004',
    'is_absent': false,
    'is_late': false,
    'reason': '',
    'has_proof': false,
  },
];

Future<List<Map<String, dynamic>>> _pump(
  WidgetTester tester, {
  bool editable = true,
  void Function(Map<String, dynamic>)? onJustificatif,
  Size taille = const Size(1280, 900),
}) async {
  final lignes = _classe();

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
                row['is_absent'] = etat == PresenceEleve.absent;
              }),
              onRetardChanged: (row, r) => setState(() => row['is_late'] = r),
              onMotifChanged: (row, m) => row['reason'] = m,
              onToutPresent: () {},
              onJustificatif: onJustificatif,
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
  testWidgets('une absence justifiee se distingue d_une absence nue', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byIcon(Icons.task_outlined), findsOneWidget);
    expect(find.byTooltip('Justificatif: certificat.pdf'), findsOneWidget);
    expect(find.byTooltip('Joindre un justificatif'), findsOneWidget);
  });

  testWidgets('un eleve present n_a rien a justifier', (tester) async {
    await _pump(tester);

    // Quatre eleves, trois absents: seuls ceux-la portent la colonne.
    expect(
      find.byTooltip('Enregistrez la fiche avant de joindre un justificatif'),
      findsOneWidget,
    );
    expect(
      find.byIcon(Icons.attach_file),
      findsNWidgets(2), // le non justifie, et celui sans identifiant
    );
  });

  testWidgets('le bandeau compte les absences justifiees', (tester) async {
    await _pump(tester);

    expect(find.textContaining('3 absents (dont 1 justifié)'), findsOneWidget);
  });

  testWidgets('un clic remonte la ligne a justifier', (tester) async {
    Map<String, dynamic>? demandee;
    await _pump(tester, onJustificatif: (ligne) => demandee = ligne);

    await tester.tap(find.byTooltip('Joindre un justificatif'));
    await tester.pump();

    expect(demandee?['student'], 2);
  });

  testWidgets('sans droit d_ecriture le depot n_est pas propose', (
    tester,
  ) async {
    await _pump(tester, editable: false, onJustificatif: null);

    final bouton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.task_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('en compact le justificatif suit le motif', (tester) async {
    await _pump(tester, taille: const Size(600, 1200));

    // La colonne disparait de l'en-tete mais le bouton reste accessible.
    expect(find.text('JUSTIF.'), findsNothing);
    expect(find.byIcon(Icons.task_outlined), findsOneWidget);
  });
}
