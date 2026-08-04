import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/student_lookup/data/student_lookup_repository.dart';
import 'package:gestion_school_app/features/student_lookup/domain/student_dossier.dart';
import 'package:gestion_school_app/features/student_lookup/presentation/student_lookup_page.dart';
import 'package:gestion_school_app/features/student_lookup/presentation/widgets/dossier_identity_card.dart';
import 'package:gestion_school_app/features/student_lookup/presentation/widgets/dossier_sections_panel.dart';
import 'package:gestion_school_app/features/students/domain/student.dart';

Map<String, dynamic> _studentJson({
  required int id,
  required String nom,
  String matricule = 'M001',
  String classe = '6eme A',
  String naissance = '2010-05-12',
  String parent = 'DIARRA Moussa',
}) {
  return {
    'id': id,
    'user': id * 10,
    'user_full_name': nom,
    'matricule': matricule,
    'classroom_name': classe,
    'birth_date': naissance,
    'parent_name': parent,
    'gender': 'M',
    'is_archived': false,
  };
}

Map<String, dynamic> _dossierJson({
  Map<String, dynamic>? student,
  List<Map<String, dynamic>>? sections,
}) {
  return {
    'student': student ?? _studentJson(id: 1, nom: 'DIARRA Sery'),
    'sections':
        sections ??
        [
          {
            'key': 'grades',
            'label': 'Notes',
            'module': 'grades',
            'granted': true,
            'count': 2,
            'summary': {'moyenne': 14.5},
            'items': [
              {
                'id': 1,
                'value': '15.00',
                'term': 'T1',
                'labels': {'matiere': 'Mathematiques', 'annee': '2025-2026'},
              },
              {
                'id': 2,
                'value': '14.00',
                'term': 'T2',
                'labels': {'matiere': 'Francais', 'annee': '2025-2026'},
              },
            ],
            'has_more': false,
          },
          {
            'key': 'library',
            'label': 'Bibliotheque',
            'module': 'library',
            'granted': false,
          },
        ],
  };
}

class _FakeRepository extends StudentLookupRepository {
  final List<Student> results;
  final Map<String, dynamic> dossier;
  int dossierCalls = 0;

  _FakeRepository({required this.results, Map<String, dynamic>? dossier})
    : dossier = dossier ?? _dossierJson(),
      super(Dio());

  @override
  Future<List<Student>> search(String query, {int limit = 25}) async => results;

  @override
  Future<StudentDossier> fetchDossier(int studentId) async {
    dossierCalls += 1;
    return StudentDossier.fromJson(dossier);
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeRepository repository, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentLookupRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: StudentLookupPage()),
    ),
  );
  await tester.pump();
}

/// La recherche est debouncee: sans avancer au-dela, rien ne part.
Future<void> _typeAndSettle(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sans saisie, l_ecran invite a chercher', (tester) async {
    await _pump(tester, _FakeRepository(results: const []));

    expect(find.textContaining('Saisissez un nom ou un matricule'), findsOneWidget);
    expect(find.byType(DossierIdentityCard), findsNothing);
  });

  testWidgets('plusieurs correspondances affichent la liste, pas un dossier', (
    tester,
  ) async {
    final repository = _FakeRepository(
      results: [
        Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery')),
        Student.fromJson(
          _studentJson(id: 2, nom: 'DIARRA Fatoumata', matricule: 'M002'),
        ),
      ],
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'Diarra');

    expect(find.text('2 élèves trouvés'), findsOneWidget);
    expect(find.text('DIARRA Sery'), findsOneWidget);
    expect(find.text('DIARRA Fatoumata'), findsOneWidget);
    // Tant qu'on n'a pas choisi, aucun dossier n'est ouvert: deux homonymes
    // ne doivent pas pouvoir etre confondus.
    expect(find.byType(DossierIdentityCard), findsNothing);
    expect(repository.dossierCalls, 0);
  });

  testWidgets('choisir un resultat ouvre son dossier', (tester) async {
    final repository = _FakeRepository(
      results: [
        Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery')),
        Student.fromJson(
          _studentJson(id: 2, nom: 'DIARRA Fatoumata', matricule: 'M002'),
        ),
      ],
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'Diarra');

    await tester.tap(find.text('DIARRA Fatoumata'));
    await tester.pumpAndSettle();

    expect(repository.dossierCalls, 1);
    expect(find.byType(DossierIdentityCard), findsOneWidget);
    expect(find.text('INFORMATIONS ÉLÈVE'), findsOneWidget);
    expect(find.text('CONSULTATION'), findsOneWidget);
  });

  testWidgets('une correspondance unique ouvre directement le dossier', (
    tester,
  ) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'M001');

    expect(repository.dossierCalls, 1);
    expect(find.byType(DossierIdentityCard), findsOneWidget);
  });

  testWidgets('une rubrique interdite reste visible et porte son motif', (
    tester,
  ) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'M001');

    // Masquer la rubrique ferait lire "aucun emprunt" au lieu de "pas d'acces".
    expect(find.text('Bibliotheque'), findsOneWidget);
    expect(find.text(DossierSectionsPanel.accesRefuse), findsOneWidget);
  });

  testWidgets('deplier une rubrique montre ses elements formates', (
    tester,
  ) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'M001');

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    // Le libelle vient du serveur: sans lui l'ecran afficherait "Matiere 7".
    expect(find.text('Mathematiques'), findsOneWidget);
    expect(find.text('15/20'), findsOneWidget);
    expect(find.text('Francais'), findsOneWidget);
  });

  testWidgets('un champ absent affiche Non renseigne', (tester) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
      dossier: _dossierJson(
        student: _studentJson(id: 1, nom: 'DIARRA Sery', parent: ''),
      ),
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'M001');

    // Un blanc se lit comme un bug d'affichage; le texte dit que la donnee
    // manque et reste a saisir.
    expect(find.text(DossierIdentityCard.nonRenseigne), findsWidgets);
  });

  testWidgets('une rubrique tronquee annonce le total reel', (tester) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
      dossier: _dossierJson(
        sections: [
          {
            'key': 'grades',
            'label': 'Notes',
            'module': 'grades',
            'granted': true,
            'count': 200,
            'summary': const <String, dynamic>{},
            'items': [
              {
                'id': 1,
                'value': '15.00',
                'term': 'T1',
                'labels': {'matiere': 'Mathematiques'},
              },
            ],
            'has_more': true,
          },
        ],
      ),
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'M001');

    expect(find.text('200'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sur 200'), findsOneWidget);
  });

  testWidgets('le resume d_argent suit le format des lignes depliees', (
    tester,
  ) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
      dossier: _dossierJson(
        sections: [
          {
            'key': 'fees',
            'label': 'Frais',
            'module': 'finance',
            'granted': true,
            'count': 1,
            'summary': {'total_du': 85000},
            'items': [
              {
                'id': 1,
                'amount_due': '85000.00',
                'balance': '35000.00',
                'labels': {'type': 'Frais mensuels'},
              },
            ],
            'has_more': false,
          },
        ],
      ),
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'M001');

    // « Total dû : 85000 » a cote de « Reste 35 000 F » se lisait comme deux
    // unites differentes.
    expect(find.textContaining('Total dû : 85 000 F'), findsOneWidget);
  });

  testWidgets('une rubrique autorisee mais vide le dit', (tester) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
      dossier: _dossierJson(
        sections: [
          {
            'key': 'discipline',
            'label': 'Discipline',
            'module': 'discipline',
            'granted': true,
            'count': 0,
            'summary': const <String, dynamic>{},
            'items': const <Map<String, dynamic>>[],
            'has_more': false,
          },
        ],
      ),
    );
    await _pump(tester, repository);
    await _typeAndSettle(tester, 'M001');

    await tester.tap(find.text('Discipline'));
    await tester.pumpAndSettle();

    expect(find.text(DossierSectionsPanel.aucunElement), findsOneWidget);
  });

  testWidgets('une recherche sans resultat affiche l_etat vide', (
    tester,
  ) async {
    await _pump(tester, _FakeRepository(results: const []));
    await _typeAndSettle(tester, 'zzzz');

    expect(find.text('Aucun élève pour « zzzz »'), findsOneWidget);
  });

  testWidgets('sur ecran etroit les deux colonnes s_empilent', (tester) async {
    final repository = _FakeRepository(
      results: [Student.fromJson(_studentJson(id: 1, nom: 'DIARRA Sery'))],
    );
    await _pump(tester, repository, size: const Size(700, 1000));
    await _typeAndSettle(tester, 'M001');

    final identite = tester.getRect(find.byType(DossierIdentityCard));
    final sections = tester.getRect(find.byType(DossierSectionsPanel));
    expect(sections.top, greaterThanOrEqualTo(identite.bottom));
  });
}
