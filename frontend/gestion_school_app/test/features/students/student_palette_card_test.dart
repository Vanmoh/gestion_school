import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/students/domain/student.dart';
import 'package:gestion_school_app/features/students/presentation/widgets/student_palette_card.dart';

Student _eleve({
  String nom = 'ALI DOUMBIA',
  String genre = 'M',
  bool archive = false,
  String photo = '',
}) {
  return Student.fromJson({
    'id': 1,
    'user': 10,
    'user_full_name': nom,
    'user_username': 'ali_ltob',
    'matricule': 'GS-2026-114311',
    'classroom_name': '10ème CT',
    'birth_date': '2004-01-01',
    'enrollment_date': '2026-05-11',
    'user_phone': '7777777',
    'user_email': 'test@gmail.com',
    'gender': genre,
    'is_archived': archive,
    'photo': photo,
  });
}

Future<void> _pump(
  WidgetTester tester, {
  Student? student,
  List<Map<String, dynamic>> fees = const [],
  List<Map<String, dynamic>> attendances = const [],
  List<Map<String, dynamic>> incidents = const [],
  List<Map<String, dynamic>> history = const [],
  List<Widget> actions = const [],
  String photoUrl = '',
  VoidCallback? onClear,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StudentPaletteCard(
            student: student ?? _eleve(),
            fees: fees,
            payments: const [],
            attendances: attendances,
            incidents: incidents,
            history: history,
            actions: actions,
            photoUrl: photoUrl,
            onClear: onClear,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('les trois blocs portent l_identite, la scolarite et les contacts', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('IDENTITÉ'), findsOneWidget);
    expect(find.text('SCOLARITÉ'), findsOneWidget);
    expect(find.text('CONTACTS'), findsOneWidget);
    expect(find.text('GS-2026-114311'), findsNWidgets(2)); // pastille + champ
    expect(find.text('10ème CT'), findsNWidgets(2));
    expect(find.text('Masculin'), findsOneWidget);
    expect(find.text('01/01/2004'), findsOneWidget);
  });

  testWidgets('un champ absent affiche le motif, pas un blanc', (tester) async {
    await _pump(tester, student: _eleve(genre: ''));

    // Un blanc se lit comme un defaut d'affichage; le motif dit que la
    // donnee reste a saisir.
    expect(
      find.text(StudentPaletteCard.nonRenseigne),
      findsWidgets,
    );
  });

  testWidgets('sans rien a signaler, une phrase remplace les quatre tuiles', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Rien à signaler'), findsOneWidget);
    for (final titre in ['FRAIS', 'ASSIDUITÉ', 'DISCIPLINE', 'HISTORIQUE']) {
      expect(find.text(titre), findsNothing, reason: titre);
    }
  });

  testWidgets('des qu_il y a du contenu, les tuiles reviennent', (tester) async {
    await _pump(
      tester,
      fees: const [
        {'amount_due': '85000', 'amount_paid': '50000'},
      ],
      attendances: const [
        {'is_absent': true},
        {'is_late': true},
      ],
      incidents: const [
        {'status': 'open'},
      ],
    );

    expect(find.textContaining('Rien à signaler'), findsNothing);
    expect(find.text('FRAIS'), findsOneWidget);
    // 85 000 du - 50 000 paye : le reste est ce qui interesse au guichet.
    expect(find.text('35 000 F restant'), findsOneWidget);
    expect(find.text('1 absence'), findsOneWidget);
    expect(find.text('1 incident'), findsOneWidget);
  });

  testWidgets('les actions se placent sous le nom', (tester) async {
    await _pump(
      tester,
      actions: [
        FilledButton(onPressed: () {}, child: const Text('Incident')),
      ],
    );

    // Le nom figure deux fois: en titre, puis dans le bloc Identite. C'est le
    // titre qui compte ici, donc la premiere occurrence de l'arbre.
    final nom = tester.getTopLeft(find.text('ALI DOUMBIA').first).dy;
    final action = tester.getTopLeft(find.text('Incident')).dy;
    expect(action, greaterThan(nom));
  });

  testWidgets('sans photo, les initiales tiennent la place', (tester) async {
    await _pump(tester);

    expect(find.text('AD'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('avec une photo, l_image remplace les initiales', (tester) async {
    await _pump(tester, photoUrl: 'https://exemple.invalid/photo.jpg');

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('un eleve archive porte sa mention', (tester) async {
    await _pump(tester, student: _eleve(archive: true));

    expect(find.text('Archivé'), findsNWidgets(2)); // pastille + statut
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
