import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/teachers/presentation/widgets/teacher_palette_card.dart';

const _user = {
  'id': 10,
  'username': 'ens_amadou',
  'first_name': 'Amadou',
  'last_name': 'DIALLO',
  'full_name': 'Amadou DIALLO',
  'email': 'amadou.diallo@ltob.ml',
  'phone': '76123456',
  'etablissement_name': 'LTOB',
};

const _profile = {
  'id': 3,
  'employee_code': 'ENS-001',
  'hire_date': '2020-09-01',
};

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic> user = _user,
  Map<String, dynamic>? profile = _profile,
  List<Map<String, dynamic>> assignments = const [],
  List<Map<String, dynamic>> scheduleSlots = const [],
  List<Map<String, dynamic>> timeEntries = const [],
  List<Widget> actions = const [],
  VoidCallback? onClear,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TeacherPaletteCard(
            user: user,
            profile: profile,
            assignments: assignments,
            scheduleSlots: scheduleSlots,
            timeEntries: timeEntries,
            actions: actions,
            onClear: onClear,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('photo', () {
    testWidgets('sans photo, les initiales tiennent la place', (tester) async {
      await _pump(tester);

      expect(find.byType(Image), findsNothing);
      expect(find.text('AD'), findsOneWidget);
    });

    testWidgets('avec une photo, l_image remplace les initiales', (
      tester,
    ) async {
      await _pump(
        tester,
        user: {
          ..._user,
          'profile_photo': 'https://exemple.invalid/prof.jpg',
        },
      );

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('une adresse absente ne casse pas l_en-tete', (tester) async {
      // L'annuaire ne fournit la photo qu'aux profils autorises: pour les
      // autres, la cle n'existe pas du tout.
      await _pump(tester, user: {..._user}..remove('profile_photo'));

      expect(find.text('AD'), findsOneWidget);
    });
  });

  testWidgets('les trois blocs portent l_identite, le poste et les contacts', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('IDENTITÉ'), findsOneWidget);
    expect(find.text('POSTE'), findsOneWidget);
    expect(find.text('CONTACTS'), findsOneWidget);
    expect(find.text('ENS-001'), findsNWidgets(2)); // pastille + champ
    expect(find.text('01/09/2020'), findsOneWidget);
    expect(find.text('amadou.diallo@ltob.ml'), findsOneWidget);
  });

  testWidgets('la remuneration n_apparait nulle part', (tester) async {
    await _pump(
      tester,
      // Meme si l'appelant les passait par erreur, la palette ne les lit pas.
      profile: const {
        ..._profile,
        'salary_base': '150000',
        'hourly_rate': '2500',
      },
    );

    // Le salaire reste dans le module Paie: un censeur ou un surveillant a
    // acces en lecture aux enseignants, pas a leur remuneration.
    expect(find.textContaining('150000'), findsNothing);
    expect(find.textContaining('2500'), findsNothing);
    expect(find.textContaining('RÉMUNÉRATION'), findsNothing);
    expect(find.textContaining('Salaire'), findsNothing);
  });

  testWidgets('un compte sans profil enseignant le dit', (tester) async {
    await _pump(tester, profile: null);

    // Sans profil, ni affectation ni emargement ne sont possibles: le motif
    // evite de chercher pourquoi les indicateurs restent vides.
    expect(find.text(TeacherPaletteCard.sansProfil), findsOneWidget);
    expect(find.textContaining('Créez le profil enseignant'), findsOneWidget);
  });

  testWidgets('sans rien a montrer, une phrase remplace les indicateurs', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Aucune affectation, aucun créneau'), findsOneWidget);
    expect(find.text('AFFECTATIONS'), findsNothing);
  });

  testWidgets('les affectations comptent les matieres et classes distinctes', (
    tester,
  ) async {
    await _pump(
      tester,
      assignments: const [
        {'subject_name': 'Mathematiques', 'classroom_name': '6A'},
        {'subject_name': 'Mathematiques', 'classroom_name': '5B'},
        {'subject_name': 'Physique', 'classroom_name': '6A'},
      ],
    );

    // Trois affectations, mais deux matieres et deux classes: compter les
    // lignes annoncerait un service plus large qu'il ne l'est.
    expect(find.text('2 matières'), findsOneWidget);
    expect(find.text('2 classes'), findsOneWidget);
  });

  testWidgets('l_emploi du temps totalise les heures hebdomadaires', (
    tester,
  ) async {
    await _pump(
      tester,
      scheduleSlots: const [
        {'start_time': '08:00', 'end_time': '10:00'},
        {'start_time': '10:15', 'end_time': '12:15'},
        {'start_time': '14:00', 'end_time': '14:30'},
      ],
    );

    expect(find.text('3 créneaux'), findsOneWidget);
    expect(find.text('4h30 par semaine'), findsOneWidget);
  });

  testWidgets('un creneau incoherent ne fausse pas le total', (tester) async {
    await _pump(
      tester,
      scheduleSlots: const [
        {'start_time': '08:00', 'end_time': '10:00'},
        {'start_time': '15:00', 'end_time': '14:00'}, // fin avant debut
        {'start_time': '', 'end_time': '12:00'},
      ],
    );

    // Seul le creneau valide compte: additionner une duree negative
    // reduirait un total qui doit rester une borne basse honnete.
    expect(find.text('2h par semaine'), findsOneWidget);
  });

  testWidgets('l_emargement signale les retards', (tester) async {
    await _pump(
      tester,
      timeEntries: const [
        {'late_minutes': 0},
        {'late_minutes': 12},
        {'late_minutes': 5},
      ],
    );

    expect(find.text('3 pointages'), findsOneWidget);
    expect(find.text('2 retards'), findsOneWidget);
  });

  testWidgets('l_anciennete se deduit de la date d_embauche', (tester) async {
    await _pump(tester);

    // Embauche en 2020: au moins quelques annees, jamais un nombre negatif.
    final anciennete = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .firstWhere((texte) => texte.endsWith(' ans'), orElse: () => '');
    expect(anciennete, isNotEmpty);
    expect(anciennete, isNot(startsWith('-')));
  });

  testWidgets('un champ absent affiche le motif, pas un blanc', (tester) async {
    await _pump(
      tester,
      user: const {'id': 10, 'username': 'ens_x', 'full_name': 'X Y'},
      profile: null,
    );

    expect(find.text(TeacherPaletteCard.nonRenseigne), findsWidgets);
  });

  testWidgets('les actions se placent sous le nom', (tester) async {
    await _pump(
      tester,
      actions: [
        FilledButton(onPressed: () {}, child: const Text('Affecter')),
      ],
    );

    final nom = tester.getTopLeft(find.text('Amadou DIALLO').first).dy;
    final action = tester.getTopLeft(find.text('Affecter')).dy;
    expect(action, greaterThan(nom));
  });

  testWidgets('le retour aux resultats n_apparait que s_il y en a', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Résultats'), findsNothing);

    await _pump(tester, onClear: () {});
    expect(find.text('Résultats'), findsOneWidget);
  });
}
