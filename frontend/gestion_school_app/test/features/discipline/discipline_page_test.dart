/// Ce que chaque profil peut faire sur l'ecran discipline.
///
/// La page melait deux sources de droits: une lecture de la matrice servie
/// par le backend, et une liste de roles recopiee dans le `build`. Elles
/// divergeaient sur le promoteur. Aucun test ne montait la page, la
/// divergence n'a ete vue qu'a la relecture.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/auth/data/auth_repository.dart';
import 'package:gestion_school_app/features/auth/domain/auth_user.dart';
import 'package:gestion_school_app/features/auth/presentation/auth_controller.dart';
import 'package:gestion_school_app/features/discipline/data/discipline_repository.dart';
import 'package:gestion_school_app/features/discipline/domain/discipline_incident.dart';
import 'package:gestion_school_app/features/discipline/presentation/discipline_controller.dart';
import 'package:gestion_school_app/features/discipline/presentation/discipline_page.dart';

const _incident = DisciplineIncident(
  id: 7,
  studentId: 3,
  studentFullName: 'Awa Traoré',
  studentMatricule: 'MAT-003',
  incidentDate: '2026-01-17',
  category: 'Indiscipline',
  description: 'Bavardage répété.',
  severity: 'medium',
  status: 'open',
  reportedByName: 'M. Diallo',
);

const _eleves = [
  DisciplineStudentOption(id: 3, fullName: 'Awa Traoré', matricule: 'MAT-003'),
];

class _FauxDepot extends DisciplineRepository {
  bool asTeacherDemande = false;
  int? updateId;
  String? updateStatut;
  int? deleteId;

  _FauxDepot() : super(Dio());

  @override
  Future<List<DisciplineIncident>> fetchIncidents({
    String search = '',
    String status = '',
    String severity = '',
  }) async {
    return const [_incident];
  }

  @override
  Future<List<DisciplineStudentOption>> fetchSelectableStudents({
    required bool asTeacher,
    int? currentUserId,
  }) async {
    asTeacherDemande = asTeacher;
    return _eleves;
  }

  @override
  Future<void> updateIncident({
    required int id,
    String? sanction,
    String? status,
    bool? parentNotified,
    String? severity,
  }) async {
    updateId = id;
    updateStatut = status;
  }

  @override
  Future<void> deleteIncident(int id) async {
    deleteId = id;
  }
}

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'discipline': ModulePermission(
        key: 'discipline',
        label: 'Discipline',
        group: 'pedagogie',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<_FauxDepot> _monter(
  WidgetTester tester, {
  required AccessLevel niveau,
  required String role,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final depot = _FauxDepot();

  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        disciplineRepositoryProvider.overrideWithValue(depot),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
        authControllerProvider.overrideWith(
          // AuthRepository est concret et n'est jamais sollicite ici: seul
          // l'etat du controleur est lu par la page.
          (ref) =>
              AuthController(
                AuthRepository(dio: Dio(), tokenStorage: TokenStorage()),
              )..state = AsyncValue.data(
                AuthUser(
                  id: 1,
                  username: role,
                  fullName: 'Profil $role',
                  role: role,
                  etablissementId: 5,
                ),
              ),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: DisciplinePage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return depot;
}

void main() {
  testWidgets('le promoteur, en lecture seule, n_obtient aucun formulaire', (
    tester,
  ) async {
    // Regression: la matrice lui accorde « L », mais la liste de roles
    // codee dans le build le rangeait avec les profils en ecriture. Il
    // remplissait la declaration entiere avant d'etre refuse a l_envoi.
    await _monter(tester, niveau: AccessLevel.read, role: 'promoter');

    expect(find.text('Déclarer un incident'), findsNothing);
    expect(find.byKey(const Key('declaration-student')), findsNothing);
    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('review-7')), findsNothing);
    expect(find.byKey(const Key('delete-7')), findsNothing);
  });

  testWidgets('l_enseignant declare sans sanction ni statut', (tester) async {
    final depot = await _monter(
      tester,
      niveau: AccessLevel.write,
      role: 'teacher',
    );

    expect(find.byKey(const Key('declaration-student')), findsOneWidget);
    // Champs d'arbitrage absents: le serveur les remet a zero de toute
    // facon, les afficher promettait une saisie qui n'aboutissait pas.
    expect(find.byKey(const Key('declaration-status')), findsNothing);
    expect(find.byKey(const Key('declaration-sanction')), findsNothing);
    expect(find.byKey(const Key('review-7')), findsNothing);
    expect(depot.asTeacherDemande, isTrue);
  });

  testWidgets('le censeur peut traiter un incident', (tester) async {
    final depot = await _monter(
      tester,
      niveau: AccessLevel.write,
      role: 'censor',
    );

    expect(find.byKey(const Key('declaration-sanction')), findsOneWidget);
    // La suppression demande le niveau administration: le censeur ne l_a pas.
    expect(find.byKey(const Key('delete-7')), findsNothing);

    await tester.tap(find.byKey(const Key('review-7')));
    await tester.pumpAndSettle();

    expect(find.text('Traiter l\'incident'), findsOneWidget);
    expect(find.text('Déclaré par M. Diallo'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('review-sanction')),
      'Avertissement écrit',
    );
    await tester.tap(find.byKey(const Key('review-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traité').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(depot.updateId, 7);
    expect(depot.updateStatut, 'resolved');
  });

  testWidgets('le directeur peut supprimer apres confirmation', (tester) async {
    final depot = await _monter(
      tester,
      niveau: AccessLevel.admin,
      role: 'director',
    );

    await tester.tap(find.byKey(const Key('delete-7')));
    await tester.pumpAndSettle();

    expect(find.text('Supprimer l\'incident'), findsOneWidget);
    await tester.tap(find.text('Supprimer').last);
    await tester.pumpAndSettle();

    expect(depot.deleteId, 7);
  });
}
