/// Le journal des fiches d'appel deja enregistrees.
///
/// Une fois la fiche enregistree, rien ne permettait de la revoir: il fallait
/// resaisir sa classe et sa date de memoire. Le widget backend etait couvert,
/// pas lui -- alors que c'est ici que se decide ce que le surveillant lit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/attendance/presentation/widgets/attendance_sheet_journal.dart';

/// Deux fiches: une validee, une brouillon. C'est la distinction que l'ecran
/// doit rendre lisible d'un coup d'oeil.
List<Map<String, dynamic>> _fiches() => [
  {
    'classroom': 7,
    'classroom_name': '6e A',
    'date': '2026-03-12',
    'effectif': 30,
    'absents': 3,
    'retards': 1,
    'is_locked': true,
    'validated_by_name': 'TRAORE Fatoumata',
    'validated_at': '2026-03-12T09:15:00Z',
  },
  {
    'classroom': 8,
    'classroom_name': '5e B',
    'date': '2026-03-11',
    'effectif': 28,
    'absents': 0,
    'retards': 2,
    'is_locked': false,
    'validated_by_name': '',
    'validated_at': null,
  },
];

/// Journal de bord des appels: chaque rappel note (classe, date) pour qu'un
/// test verifie non seulement qu'on a clique, mais sur quelle ligne.
class _Appels {
  final List<String> voir = [];
  final List<String> pdf = [];
  final List<String> excel = [];
}

Future<_Appels> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>>? fiches,
  bool loading = false,
  Size taille = const Size(1280, 900),
}) async {
  final appels = _Appels();

  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AttendanceSheetJournal(
            fiches: fiches ?? _fiches(),
            loading: loading,
            onVoir: (c, d) => appels.voir.add('$c|$d'),
            onExporterPdf: (c, d) => appels.pdf.add('$c|$d'),
            onExporterExcel: (c, d) => appels.excel.add('$c|$d'),
          ),
        ),
      ),
    ),
  );
  if (loading) {
    // Le rond de chargement tourne sans fin: `pumpAndSettle` attend une
    // stabilisation qui ne vient jamais et finit en timeout. Une seule
    // image suffit pour observer l'etat de chargement.
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return appels;
}

void main() {
  group('AttendanceSheetJournal', () {
    testWidgets('sans fiche, il le dit au lieu de laisser un blanc', (
      tester,
    ) async {
      await _pump(tester, fiches: const []);

      expect(
        find.text('Aucune fiche enregistrée sur cette période.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Voir la fiche'), findsNothing);
    });

    testWidgets('pendant le chargement, il montre le rond et rien d\'autre', (
      tester,
    ) async {
      await _pump(tester, loading: true);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Le vide et le chargement se ressemblent a l'ecran; les confondre
      // ferait croire a l'absence de fiche alors qu'elles arrivent.
      expect(
        find.text('Aucune fiche enregistrée sur cette période.'),
        findsNothing,
      );
    });

    testWidgets('la date ISO devient une date lisible', (tester) async {
      await _pump(tester);

      // L'API parle ISO, le surveillant lit le format d'ici.
      expect(find.text('12/03/2026'), findsOneWidget);
      expect(find.text('11/03/2026'), findsOneWidget);
      expect(find.text('2026-03-12'), findsNothing);
    });

    testWidgets('une date illisible s\'affiche telle quelle, sans planter', (
      tester,
    ) async {
      await _pump(
        tester,
        fiches: [
          {..._fiches().first, 'date': 'pas-une-date'},
        ],
      );

      expect(find.text('pas-une-date'), findsOneWidget);
    });

    testWidgets('chaque fiche montre sa classe et ses comptes', (tester) async {
      await _pump(tester);

      expect(find.text('6e A'), findsOneWidget);
      expect(find.text('5e B'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('28'), findsOneWidget);
    });

    testWidgets('validee et brouillon se distinguent', (tester) async {
      await _pump(tester);

      // Une fiche non validee reste modifiable: le dire evite de croire que
      // l'appel du jour est clos.
      expect(find.text('Validée'), findsOneWidget);
      expect(find.text('Brouillon'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);
    });

    testWidgets('la fiche validee nomme son valideur en infobulle', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byTooltip('Validée par TRAORE Fatoumata'), findsOneWidget);
    });

    testWidgets('« Voir » renvoie la classe et la date de sa ligne', (
      tester,
    ) async {
      final appels = await _pump(tester);

      await tester.tap(find.byTooltip('Voir la fiche').first);
      await tester.pump();

      // La ligne du haut est la plus recente: 6e A du 12 mars.
      expect(appels.voir, ['7|2026-03-12']);
      expect(appels.pdf, isEmpty);
      expect(appels.excel, isEmpty);
    });

    testWidgets('les exports visent la bonne ligne, pas la premiere', (
      tester,
    ) async {
      final appels = await _pump(tester);

      await tester.tap(find.byTooltip('Export PDF').last);
      await tester.pump();
      await tester.tap(find.byTooltip('Export Excel').last);
      await tester.pump();

      expect(appels.pdf, ['8|2026-03-11']);
      expect(appels.excel, ['8|2026-03-11']);
    });

    testWidgets('des comptes en chaine restent des nombres', (tester) async {
      // JSON n'a qu'un type numerique, mais un agregat peut revenir en chaine
      // selon le pilote: la ligne doit s'afficher, pas tomber a zero.
      final appels = await _pump(
        tester,
        fiches: [
          {
            ..._fiches().first,
            'classroom': '7',
            'absents': '3',
          },
        ],
      );

      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byTooltip('Voir la fiche').first);
      await tester.pump();
      expect(appels.voir, ['7|2026-03-12']);
    });

    testWidgets('en large, l\'en-tete de colonnes est la', (tester) async {
      await _pump(tester);

      expect(find.text('EFFECTIF'), findsOneWidget);
      expect(find.text('ABSENTS'), findsOneWidget);
    });

    testWidgets('en etroit, l\'en-tete disparait mais les actions restent', (
      tester,
    ) async {
      await _pump(tester, taille: const Size(500, 900));

      // Sept colonnes ne tiennent pas sur un telephone: la ligne se replie.
      expect(find.text('EFFECTIF'), findsNothing);
      expect(find.byTooltip('Voir la fiche'), findsNWidgets(2));
      expect(find.textContaining('30 élèves'), findsOneWidget);
    });
  });
}
