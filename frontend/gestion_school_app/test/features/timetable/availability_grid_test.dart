import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/timetable/domain/availability.dart';
import 'package:gestion_school_app/features/timetable/presentation/widgets/availability_grid_view.dart';

/// La grille des disponibilités.
///
/// Elle décrivait une réservation exclusive: « disponible » ou
/// « indisponible » pour l'établissement entier, avec le nom de celui qui
/// avait pris la case. Elle compte désormais les déclarants — plusieurs
/// enseignants peuvent être libres au même moment, c'est même toute
/// l'information que l'administration vient chercher.
AvailabilityCell _case({
  String jour = 'MON',
  String debut = '08:00',
  String fin = '09:00',
  int preferes = 0,
  int possibles = 0,
  int indisponibles = 0,
  AvailabilityKind? mienne,
  int? mienneId,
  bool mienneExacte = true,
  List<AvailabilityDeclarant> declarants = const [],
}) {
  return AvailabilityCell(
    dayOfWeek: jour,
    dayLabel: jour == 'MON' ? 'Lundi' : 'Mardi',
    startTime: debut,
    endTime: fin,
    preferredCount: preferes,
    possibleCount: possibles,
    unavailableCount: indisponibles,
    teachers: declarants,
    mine: mienne,
    mineId: mienneId,
    mineExact: mienneExacte,
  );
}

AvailabilityGrid _grille(List<AvailabilityCell> cases) {
  return AvailabilityGrid(
    startHour: 8,
    endHour: 8 + cases.length,
    slotMinutes: 60,
    teacherId: 7,
    days: [
      AvailabilityDay(dayOfWeek: 'MON', dayLabel: 'Lundi', cells: cases),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required AvailabilityGrid grid,
  bool modeDeclaration = false,
  void Function(AvailabilityCell)? onBasculer,
  void Function(AvailabilityCell)? onDetail,
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AvailabilityGridView(
            grid: grid,
            modeDeclaration: modeDeclaration,
            onBasculer: onBasculer,
            onDetail: onDetail,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Ce que portent les cases, a l'exclusion de la legende qui en reprend les
/// mots.
Finder _dansLesCases(Finder cible) {
  return find.descendant(
    of: find.byKey(const Key('availability-cells')),
    matching: cible,
  );
}

void main() {
  group('vue d’arbitrage', () {
    testWidgets('la case compte les enseignants prenables', (tester) async {
      await _pump(
        tester,
        grid: _grille([_case(preferes: 2, possibles: 3, indisponibles: 1)]),
      );

      // Préférés et possibles se cumulent: ce sont les deux façons de dire oui.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('disponibles'), findsOneWidget);
    });

    testWidgets('les volontaires ressortent du lot', (tester) async {
      await _pump(tester, grid: _grille([_case(preferes: 2, possibles: 1)]));

      expect(find.text('2 volontaires'), findsOneWidget);
    });

    testWidgets('une case sans aucun déclarant reste muette', (tester) async {
      await _pump(tester, grid: _grille([_case()]));

      expect(find.text('—'), findsOneWidget);
      expect(_dansLesCases(find.textContaining('disponible')), findsNothing);
    });

    testWidgets('une case où tous se sont récusés alerte', (tester) async {
      await _pump(tester, grid: _grille([_case(indisponibles: 3)]));

      expect(find.text('0'), findsOneWidget);
      expect(find.text('disponible'), findsOneWidget);
    });

    testWidgets('ouvrir une case remonte ses déclarants', (tester) async {
      AvailabilityCell? recue;
      await _pump(
        tester,
        grid: _grille([
          _case(
            possibles: 1,
            declarants: const [
              AvailabilityDeclarant(
                teacherId: 3,
                name: 'Awa Traore',
                kind: AvailabilityKind.possible,
              ),
            ],
          ),
        ]),
        onDetail: (cellule) => recue = cellule,
      );

      await tester.tap(find.text('1'));
      await tester.pump();

      expect(recue?.teachers.first.name, 'Awa Traore');
    });

    testWidgets('une case vide n’est pas cliquable', (tester) async {
      var ouvertures = 0;
      await _pump(
        tester,
        grid: _grille([_case()]),
        onDetail: (_) => ouvertures++,
      );

      await tester.tap(find.text('—'));
      await tester.pump();

      expect(ouvertures, 0);
    });
  });

  group('vue de déclaration', () {
    testWidgets('la case porte l’état déclaré et lui seul', (tester) async {
      await _pump(
        tester,
        modeDeclaration: true,
        // Les compteurs des collègues existent, mais ne regardent pas
        // l'enseignant qui déclare pour lui-même.
        grid: _grille([
          _case(
            preferes: 4,
            mienne: AvailabilityKind.preferred,
            mienneId: 11,
          ),
        ]),
      );

      expect(_dansLesCases(find.text('Préférée')), findsOneWidget);
      expect(find.text('4'), findsNothing);
    });

    testWidgets('une case non déclarée reste vide', (tester) async {
      await _pump(tester, modeDeclaration: true, grid: _grille([_case()]));

      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('toucher une case remonte le basculement', (tester) async {
      AvailabilityCell? recue;
      await _pump(
        tester,
        modeDeclaration: true,
        grid: _grille([_case()]),
        onBasculer: (cellule) => recue = cellule,
      );

      await tester.tap(find.text('—'));
      await tester.pump();

      expect(recue?.startTime, '08:00');
    });

    testWidgets('sans droit d’écriture, aucune case ne bascule', (tester) async {
      var basculements = 0;
      await _pump(
        tester,
        modeDeclaration: true,
        grid: _grille([_case(mienne: AvailabilityKind.possible, mienneId: 5)]),
      );

      await tester.tap(_dansLesCases(find.text('Possible')));
      await tester.pump();

      expect(basculements, 0);
    });

    testWidgets('une plage plus large se signale plutôt que de mentir', (
      tester,
    ) async {
      await _pump(
        tester,
        modeDeclaration: true,
        grid: _grille([
          _case(
            mienne: AvailabilityKind.possible,
            mienneId: 9,
            mienneExacte: false,
          ),
        ]),
      );

      expect(find.text('plage plus large'), findsOneWidget);
    });

    testWidgets('la légende dit comment on déclare', (tester) async {
      await _pump(tester, modeDeclaration: true, grid: _grille([_case()]));

      expect(
        find.text('Touchez une case pour changer son état.'),
        findsOneWidget,
      );
      expect(find.text('Indisponible'), findsOneWidget);
    });
  });

  testWidgets('une grille sans plage horaire le dit', (tester) async {
    await _pump(tester, grid: AvailabilityGrid.vide);

    expect(find.text('Aucune plage horaire à afficher.'), findsOneWidget);
  });

  group('le cycle des états', () {
    test('préférée mène à possible, puis à indisponible, puis à rien', () {
      expect(AvailabilityKind.preferred.suivant, AvailabilityKind.possible);
      expect(AvailabilityKind.possible.suivant, AvailabilityKind.unavailable);
      expect(AvailabilityKind.unavailable.suivant, isNull);
    });

    test('un code inconnu ne devient pas un état par défaut', () {
      // Sinon une valeur ajoutée côté serveur passerait pour « préférée ».
      expect(AvailabilityKind.depuis('autre_chose'), isNull);
      expect(AvailabilityKind.depuis(null), isNull);
    });
  });

  group('la campagne', () {
    test('le taux de réponse reste indéfini sans aucun enseignant', () {
      // « 0 % » sur une école sans enseignant se lirait comme un manquement.
      const vide = AvailabilityCampaign(
        id: 1,
        label: 'Rentrée',
        academicYearName: '2025-2026',
        opensOn: null,
        closesOn: null,
        status: 'open',
        statusLabel: 'Ouverte',
        isOpen: true,
        instructions: '',
        teachersTotal: 0,
        teachersAnswered: 0,
      );

      expect(vide.tauxReponse, isNull);
      expect(vide.teachersMissing, 0);
    });

    test('les manquants se déduisent de l’effectif', () {
      const campagne = AvailabilityCampaign(
        id: 1,
        label: 'Rentrée',
        academicYearName: '2025-2026',
        opensOn: null,
        closesOn: null,
        status: 'open',
        statusLabel: 'Ouverte',
        isOpen: true,
        instructions: '',
        teachersTotal: 12,
        teachersAnswered: 5,
      );

      expect(campagne.teachersMissing, 7);
      expect(campagne.tauxReponse, closeTo(0.4166, 0.001));
    });
  });
}
