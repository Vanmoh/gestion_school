/// Le parcours complet de « Gestion des eleves »: chercher, choisir, agir.
///
/// Les tests existants couvrent la palette et la regle de grisage isolement.
/// Aucun ne montait la page: le cablage entre la barre de recherche, la liste
/// des correspondances et la palette n'etait verifie nulle part, alors que
/// c'est precisement ce que la refonte a change.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/models/paginated_result.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/features/auth/data/auth_repository.dart';
import 'package:gestion_school_app/features/auth/domain/auth_user.dart';
import 'package:gestion_school_app/features/auth/presentation/auth_controller.dart';
import 'package:gestion_school_app/features/students/data/students_repository.dart';
import 'package:gestion_school_app/features/students/domain/student.dart';
import 'package:gestion_school_app/features/students/domain/students_stats.dart';
import 'package:gestion_school_app/features/students/presentation/students_controller.dart';
import 'package:gestion_school_app/features/students/presentation/students_page.dart';
import 'package:gestion_school_app/features/students/presentation/widgets/student_palette_card.dart';

class _FakeRepository extends StudentsRepository {
  final List<Student> annuaire;

  String derniereRecherche = '';
  bool? dernierArchive = false;
  int chargements = 0;

  _FakeRepository(this.annuaire) : super(Dio());

  @override
  Future<PaginatedResult<Student>> fetchStudentsPage({
    String search = '',
    int? classroomId,
    bool? isArchived,
    String ordering = '-created_at',
    int page = 1,
    int pageSize = 25,
  }) async {
    chargements++;
    derniereRecherche = search;
    dernierArchive = isArchived;

    final besoin = search.trim().toLowerCase();
    final trouves = besoin.isEmpty
        ? annuaire
        : annuaire
              .where(
                (eleve) =>
                    eleve.fullName.toLowerCase().contains(besoin) ||
                    eleve.matricule.toLowerCase().contains(besoin),
              )
              .toList();

    return PaginatedResult<Student>(
      count: trouves.length,
      next: null,
      previous: null,
      results: trouves,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchClassrooms() async => [
    {'id': 7, 'name': '6A'},
  ];

  @override
  Future<List<Map<String, dynamic>>> fetchParents() async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchAcademicYears() async => const [];

  @override
  Future<StudentsStats> fetchStats() async => const StudentsStats(
    total: 3,
    active: 3,
    archived: 0,
    newThisYear: 1,
    genderMissing: 0,
    academicYear: '2025-2026',
  );

  @override
  Future<List<Map<String, dynamic>>> fetchStudentHistory(int id) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchStudentDiscipline(int id) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchStudentAttendances(int id) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchStudentFees(int id) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchStudentPayments(int id) async =>
      const [];
}

Student _eleve(int id, String nom, String matricule, {bool archive = false}) {
  return Student.fromJson({
    'id': id,
    'user': id * 10,
    'user_full_name': nom,
    'matricule': matricule,
    'classroom_name': '6A',
    'birth_date': '2012-03-14',
    'gender': 'F',
    'is_archived': archive,
  });
}

final _annuaire = [
  _eleve(1, 'Aminata Coulibaly', 'M001'),
  _eleve(2, 'Boubacar Diallo', 'M002'),
  _eleve(3, 'Fatou Diallo', 'M003'),
  _eleve(4, 'Salif Ancien', 'M004', archive: true),
];

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'director',
    modules: {
      'students': ModulePermission(
        key: 'students',
        label: 'Gestion des eleves',
        group: 'pedagogie',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<_FakeRepository> _pumpPage(
  WidgetTester tester, {
  AccessLevel niveau = AccessLevel.write,
  List<Student>? annuaire,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final repository = _FakeRepository(annuaire ?? _annuaire);

  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentsRepositoryProvider.overrideWithValue(repository),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
        authControllerProvider.overrideWith(
          // AuthRepository est concret et n'est jamais sollicite ici: seul
          // l'etat du controleur est lu par la page.
          (ref) => AuthController(AuthRepository(dio: Dio(), tokenStorage: TokenStorage()))
            ..state = const AsyncValue.data(
              AuthUser(
                id: 1,
                username: 'directeur',
                fullName: 'Le Directeur',
                role: 'director',
                etablissementId: 5,
              ),
            ),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: StudentsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return repository;
}

Future<void> _chercher(WidgetTester tester, String texte) async {
  await tester.enterText(find.byType(TextField).first, texte);
  // Le champ est debounce a 250 ms; en dessous la requete ne part pas.
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('au chargement, l_ecran invite a chercher sans ouvrir personne', (
    tester,
  ) async {
    await _pumpPage(tester);

    // Regression: la page ouvrait la palette du premier eleve venu, et les
    // boutons d'ecriture visaient quelqu'un que personne n'avait choisi.
    expect(find.byType(StudentPaletteCard), findsNothing);
    expect(
      find.textContaining('Recherchez un élève'),
      findsOneWidget,
    );
  });

  testWidgets('la recherche remonte au serveur, archives compris', (
    tester,
  ) async {
    final repository = await _pumpPage(tester);

    await _chercher(tester, 'diallo');

    expect(repository.derniereRecherche, 'diallo');
    // Sans filtre de statut sur la page, un archive doit rester trouvable.
    expect(repository.dernierArchive, isNull);
  });

  testWidgets('plusieurs correspondances demandent lequel ouvrir', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _chercher(tester, 'diallo');

    expect(find.textContaining('2 élèves correspondent'), findsOneWidget);
    expect(find.byType(StudentPaletteCard), findsNothing);
    expect(find.text('Boubacar Diallo'), findsOneWidget);
    expect(find.text('Fatou Diallo'), findsOneWidget);
  });

  testWidgets('choisir un resultat ouvre sa palette', (tester) async {
    await _pumpPage(tester);
    await _chercher(tester, 'diallo');

    await tester.tap(find.text('Fatou Diallo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(StudentPaletteCard), findsOneWidget);
    expect(find.text('IDENTITÉ'), findsOneWidget);
  });

  testWidgets('une recherche sans reponse le dit avec les mots saisis', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _chercher(tester, 'zzzz');

    expect(find.textContaining('Aucun élève ne correspond'), findsOneWidget);
    expect(find.textContaining('zzzz'), findsWidgets);
  });

  testWidgets('un eleve archive reste trouvable et porte sa mention', (
    tester,
  ) async {
    await _pumpPage(tester);

    await _chercher(tester, 'ancien');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(StudentPaletteCard), findsOneWidget);
    expect(find.text('Archivé'), findsWidgets);
  });

  testWidgets('en ecriture, les actions de la palette sont actives', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _chercher(tester, 'coulibaly');
    await tester.pump(const Duration(milliseconds: 400));

    final editer = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Éditer'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(editer.onPressed, isNotNull);
  });

  testWidgets('en lecture seule, les actions sont grisees', (tester) async {
    await _pumpPage(tester, niveau: AccessLevel.read);
    await _chercher(tester, 'coulibaly');
    await tester.pump(const Duration(milliseconds: 400));

    for (final label in ['Éditer', 'Incident', 'Frais']) {
      final bouton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(bouton.onPressed, isNull, reason: label);
    }
  });

  testWidgets('la page ne porte plus ni tableau ni filtres', (tester) async {
    await _pumpPage(tester);

    // Le registre et ses filtres ont laisse place a la barre unique; leur
    // retour signalerait une regression de la refonte.
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Filtrer'), findsNothing);
    expect(find.text('Réinitialiser'), findsNothing);
    expect(find.text('Copier CSV'), findsNothing);
    expect(find.text('Liste des élèves'), findsOneWidget);
  });

  testWidgets('effacer la recherche referme la palette', (tester) async {
    await _pumpPage(tester);
    await _chercher(tester, 'coulibaly');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StudentPaletteCard), findsOneWidget);

    await tester.tap(find.byTooltip('Effacer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(StudentPaletteCard), findsNothing);
    expect(find.textContaining('Recherchez un élève'), findsOneWidget);
  });
}
