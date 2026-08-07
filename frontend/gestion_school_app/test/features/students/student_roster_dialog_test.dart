import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/students/data/students_repository.dart';
import 'package:gestion_school_app/features/students/domain/student.dart';
import 'package:gestion_school_app/features/students/presentation/students_controller.dart';
import 'package:gestion_school_app/features/students/presentation/widgets/roster_pdf_preview_dialog.dart';
import 'package:gestion_school_app/features/students/presentation/widgets/student_roster_dialog.dart';

class _FakeRepository extends StudentsRepository {
  final List<Student> eleves;

  int? classroomDemande;
  bool? archiveDemande;
  int? rosterClassroom;
  String? rosterStatus;
  int appelsPdf = 0;

  _FakeRepository(this.eleves) : super(Dio());

  @override
  Future<List<Student>> fetchStudents({
    String search = '',
    int? classroomId,
    bool? isArchived,
    String ordering = '-created_at',
  }) async {
    classroomDemande = classroomId;
    archiveDemande = isArchived;
    return eleves;
  }

  @override
  Future<Uint8List> fetchClassRosterPdf({
    int? classroomId,
    String status = 'active',
  }) async {
    appelsPdf++;
    rosterClassroom = classroomId;
    rosterStatus = status;
    return Uint8List.fromList([37, 80, 68, 70]);
  }
}

Student _eleve(int id, String nom, String matricule, String genre) {
  return Student.fromJson({
    'id': id,
    'user': id * 10,
    'user_full_name': nom,
    'matricule': matricule,
    'gender': genre,
    'classroom_name': '6A',
    'birth_date': '2012-03-14',
    'is_archived': false,
  });
}

final _eleves = [
  _eleve(1, 'Aminata Coulibaly', 'M001', 'F'),
  _eleve(2, 'Boubacar Diallo', 'M002', 'M'),
  _eleve(3, 'Fatou Diallo', 'M003', 'F'),
];

Future<_FakeRepository> _pump(
  WidgetTester tester, {
  int? classroomId = 7,
  String status = 'active',
  List<Student>? eleves,
}) async {
  final repository = _FakeRepository(eleves ?? _eleves);

  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentsRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: StudentRosterDialog(
            classroomId: classroomId,
            status: status,
            classrooms: const [
              {'id': 7, 'name': '6A'},
              {'id': 8, 'name': '5B'},
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('la fenetre part des filtres de la page', (tester) async {
    final repository = await _pump(tester, classroomId: 7, status: 'archived');

    expect(repository.classroomDemande, 7);
    expect(repository.archiveDemande, isTrue);
  });

  testWidgets('l_effectif compte les genres sur la liste entiere', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Effectif : 3'), findsOneWidget);
    expect(find.textContaining('1 G / 2 F'), findsOneWidget);
  });

  testWidgets('la liste s_affiche avec ses colonnes', (tester) async {
    await _pump(tester);

    for (final nom in ['Aminata Coulibaly', 'Boubacar Diallo', 'Fatou Diallo']) {
      expect(find.text(nom), findsOneWidget);
    }
    expect(find.text('Nom et prénoms'), findsOneWidget);
    expect(find.text('14/03/2012'), findsNWidgets(3));
  });

  testWidgets('la recherche filtre l_affichage sans amputer l_impression', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'diallo');
    await tester.pumpAndSettle();

    expect(find.text('Aminata Coulibaly'), findsNothing);
    expect(find.text('Boubacar Diallo'), findsOneWidget);

    // Le piege a eviter: chercher, imprimer, et recevoir plus de lignes que
    // ce qu'on avait sous les yeux sans l'avoir compris.
    expect(find.textContaining('ne change que l’affichage'), findsOneWidget);
    expect(find.text('Imprimer (3)'), findsOneWidget);
    expect(find.text('Copier CSV (3)'), findsOneWidget);
  });

  testWidgets('le numero d_ordre reste celui de la liste complete', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'fatou');
    await tester.pumpAndSettle();

    // Fatou est 3e de la classe: renumeroter la vue filtree ferait diverger
    // l'ecran du papier.
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('imprimer demande le PDF de la classe et du statut courants', (
    tester,
  ) async {
    final repository = await _pump(tester, classroomId: 7, status: 'all');

    await tester.tap(find.text('Imprimer (3)'));
    // pumpAndSettle est inutilisable ici: Printing.layoutPdf n'a pas de canal
    // de plateforme en test, la fenetre reste occupee et son indicateur tourne
    // indefiniment. On avance donc un nombre fixe de frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.appelsPdf, 1);
    expect(repository.rosterClassroom, 7);
    expect(repository.rosterStatus, 'all');
    tester.takeException();
  });

  testWidgets('afficher la liste ouvre l_apercu du document', (tester) async {
    final repository = await _pump(tester, classroomId: 7, status: 'active');

    await tester.tap(find.text('Afficher la liste'));
    // L'apercu rasterise le PDF via un canal de plateforme absent en test:
    // l'arbre ne se stabilise jamais, on avance donc un nombre fixe de frames.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(RosterPdfPreviewDialog), findsOneWidget);
    expect(find.text('Liste des élèves — 6A'), findsOneWidget);
    // Le telechargement se fait depuis l'apercu, plus depuis la liste.
    expect(find.text('Télécharger en PDF'), findsOneWidget);
    expect(repository.rosterClassroom, 7);
    expect(repository.rosterStatus, 'active');
    tester.takeException();
  });

  testWidgets('la liste ne porte plus de bouton d_enregistrement direct', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Enregistrer le PDF'), findsNothing);
    expect(find.text('Afficher la liste'), findsOneWidget);
  });

  testWidgets('changer de classe recharge la liste', (tester) async {
    final repository = await _pump(tester, classroomId: 7);

    await tester.tap(find.text('6A').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('5B').last);
    await tester.pumpAndSettle();

    expect(repository.classroomDemande, 8);
  });

  testWidgets('une selection vide le dit et desactive les actions', (
    tester,
  ) async {
    await _pump(tester, eleves: const []);

    expect(find.text('Aucun élève dans cette sélection.'), findsOneWidget);
    expect(find.text('Imprimer (0)'), findsOneWidget);

    // find.byType exige le type exact: FilledButton.icon construit une
    // sous-classe, que seul un predicat rattrape.
    final imprimer = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Imprimer (0)'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(imprimer.onPressed, isNull);
  });

  testWidgets('une recherche sans resultat se distingue d_une classe vide', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('Aucun élève ne correspond à la recherche.'), findsOneWidget);
    expect(find.text('Aucun élève dans cette sélection.'), findsNothing);
  });
}
