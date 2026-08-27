import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/attendance/domain/timesheet_concordance.dart';
import 'package:gestion_school_app/features/attendance/presentation/widgets/concordance_panel.dart';

/// Le rapprochement entre l'emploi du temps et l'emargement.
///
/// L'onglet « Enseignants » affichait des heures pointees sans dire a quels
/// cours elles correspondaient, ni lesquels n'avaient ete assures par
/// personne. Ces tests retiennent ce que l'ecran raconte desormais.
TimesheetConcordance _concordance({
  int assurees = 1,
  int partielles = 0,
  int manquees = 1,
  int horsPlanning = 0,
}) {
  final seances = <ConcordanceSession>[
    for (var i = 0; i < assurees; i++)
      ConcordanceSession(
        slotId: 100 + i,
        subjectName: 'Mathematiques',
        classroomName: '6A',
        room: 'B12',
        startTime: '08:00',
        endTime: '10:00',
        plannedMinutes: 120,
        coveredMinutes: 120,
        lateMinutes: 0,
        status: ConcordanceStatus.assured,
      ),
    for (var i = 0; i < partielles; i++)
      ConcordanceSession(
        slotId: 200 + i,
        subjectName: 'Physique',
        classroomName: '6A',
        room: '',
        startTime: '10:00',
        endTime: '12:00',
        plannedMinutes: 120,
        coveredMinutes: 45,
        lateMinutes: 20,
        status: ConcordanceStatus.partial,
      ),
    for (var i = 0; i < manquees; i++)
      ConcordanceSession(
        slotId: 300 + i,
        subjectName: 'Histoire',
        classroomName: '5B',
        room: '',
        startTime: '14:00',
        endTime: '16:00',
        plannedMinutes: 120,
        coveredMinutes: 0,
        lateMinutes: 0,
        status: ConcordanceStatus.missed,
      ),
  ];

  final entrees = <ConcordanceEntry>[
    for (var i = 0; i < horsPlanning; i++)
      ConcordanceEntry(
        id: 900 + i,
        checkInTime: '17:00',
        checkOutTime: '19:00',
        isAutoClosed: false,
        isOffSchedule: true,
        offScheduleReason: 'Conseil de classe',
        workedHours: '2.00',
      ),
  ];

  final totaux = ConcordanceTotals(
    plannedMinutes: seances.length * 120,
    coveredMinutes: seances.fold(0, (s, e) => s + e.coveredMinutes),
    gapMinutes:
        seances.length * 120 - seances.fold(0, (s, e) => s + e.coveredMinutes),
    sessionsPlanned: seances.length,
    sessionsAssured: assurees,
    sessionsPartial: partielles,
    sessionsMissed: manquees,
    offScheduleEntries: horsPlanning,
  );

  return TimesheetConcordance(
    from: DateTime(2026, 3, 9),
    to: DateTime(2026, 3, 9),
    totals: totaux,
    teachers: [
      ConcordanceTeacher(
        teacherId: 7,
        fullName: 'Awa Traore',
        employeeCode: 'ENS-07',
        totals: totaux,
        days: [
          ConcordanceDay(
            date: DateTime(2026, 3, 9),
            weekday: 'MON',
            sessions: seances,
            entries: entrees,
            totals: totaux,
          ),
        ],
      ),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  TimesheetConcordance? concordance,
  bool chargement = false,
  bool masquerEnseignant = false,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConcordancePanel(
            concordance: concordance ?? _concordance(),
            chargement: chargement,
            masquerEnseignant: masquerEnseignant,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('le bandeau chiffre le planifie, l_assure et l_ecart', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Planifié'), findsOneWidget);
    // Deux seances de deux heures, une seule assuree.
    expect(find.text('4 h'), findsOneWidget);
    expect(find.text('2 h'), findsNWidgets(2));
  });

  testWidgets('les seances non assurees sont comptees a part', (tester) async {
    await _pump(tester, concordance: _concordance(assurees: 2, manquees: 3));

    expect(find.text('Séances non assurées'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('une journee sans manquement s_ouvre repliee', (tester) async {
    await _pump(tester, concordance: _concordance(assurees: 2, manquees: 0));

    // Le detail des seances reste cache tant qu'il n'y a rien a corriger.
    expect(find.text('Mathematiques • 6A'), findsNothing);
  });

  testWidgets('un manquement ouvre le detail d_office', (tester) async {
    await _pump(tester);

    expect(find.text('Histoire • 5B'), findsOneWidget);
    expect(find.text('Non assurée'), findsOneWidget);
  });

  testWidgets('une seance partielle dit ce qui a ete fait', (tester) async {
    await _pump(
      tester,
      concordance: _concordance(assurees: 0, partielles: 1, manquees: 1),
    );

    expect(find.text('Partielle'), findsOneWidget);
    expect(find.textContaining('45 min sur 120'), findsOneWidget);
    expect(find.textContaining('20 min de retard'), findsOneWidget);
  });

  testWidgets('un pointage hors planning porte son motif', (tester) async {
    await _pump(tester, concordance: _concordance(horsPlanning: 1));

    expect(find.textContaining('Hors planning : 17:00 – 19:00'), findsOneWidget);
    expect(find.text('Conseil de classe'), findsOneWidget);
  });

  testWidgets('la date du jour est lisible, pas au format ISO', (tester) async {
    await _pump(tester);

    expect(find.text('Lundi 09/03/2026'), findsOneWidget);
  });

  testWidgets('l_enseignant qui consulte son suivi ne relit pas son nom', (
    tester,
  ) async {
    await _pump(tester, masquerEnseignant: true);

    expect(find.text('Awa Traore'), findsNothing);
    // Le detail, lui, reste affiche.
    expect(find.text('Histoire • 5B'), findsOneWidget);
  });

  testWidgets('une periode vide le dit plutot que de rester blanche', (
    tester,
  ) async {
    await _pump(tester, concordance: TimesheetConcordance.vide);

    expect(
      find.text('Aucun cours planifié ni pointage sur cette période.'),
      findsOneWidget,
    );
  });

  testWidgets('le chargement montre son attente', (tester) async {
    await _pump(tester, chargement: true);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('sans rien de planifie, la jauge ne dit pas zero pour cent', (
    tester,
  ) async {
    // « 0 % » sur une journee sans cours se lirait comme un manquement.
    const vide = ConcordanceTotals();

    expect(vide.tauxAssure, isNull);
  });
}
