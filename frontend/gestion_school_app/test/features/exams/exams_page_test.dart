/// L'ecran des examens: ce que chaque profil peut y faire.
///
/// Le module est le mieux structure de la section -- depot, modeles,
/// controleur, droits lus sur la matrice -- mais rien ne le verifiait: la
/// regle de lecture seule tenait sur une seule expression, non couverte.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/exams/data/exams_repository.dart';
import 'package:gestion_school_app/features/exams/domain/exam_models.dart';
import 'package:gestion_school_app/features/exams/presentation/exams_controller.dart';
import 'package:gestion_school_app/features/exams/presentation/exams_page.dart';

const _session = ExamSessionItem(
  id: 1,
  title: 'Composition du premier trimestre',
  term: 'T1',
  academicYearId: 1,
  startDate: '2025-12-01',
  endDate: '2025-12-06',
);

class _FauxDepot extends ExamsRepository {
  _FauxDepot() : super(Dio());

  @override
  Future<List<ExamSessionItem>> fetchSessions() async => const [_session];

  @override
  Future<List<ExamPlanningItem>> fetchPlannings() async => const [
    ExamPlanningItem(
      id: 5,
      sessionId: 1,
      classroomId: 10,
      subjectId: 20,
      examDate: '2025-12-01',
      startTime: '08:00',
      endTime: '10:00',
    ),
  ];

  @override
  Future<List<ExamResultItem>> fetchResults() async => const [
    ExamResultItem(id: 7, sessionId: 1, studentId: 30, subjectId: 20, score: 15.5),
  ];

  @override
  Future<List<ExamInvigilationItem>> fetchInvigilations() async => const [
    ExamInvigilationItem(
      id: 9,
      planningId: 5,
      supervisorId: 40,
      supervisorName: 'Fatou Kone',
    ),
  ];

  @override
  Future<List<OptionItem>> fetchAcademicYears() async => const [
    OptionItem(id: 1, label: '2025-2026'),
  ];

  @override
  Future<List<OptionItem>> fetchClassrooms() async => const [
    OptionItem(id: 10, label: '6A'),
  ];

  @override
  Future<List<OptionItem>> fetchSubjects({int? classroomId}) async => const [
    OptionItem(id: 20, label: 'Mathematiques'),
  ];

  @override
  Future<List<OptionItem>> fetchStudents() async => const [
    OptionItem(id: 30, label: 'Awa Traore', classroomId: 10),
  ];

  @override
  Future<List<OptionItem>> fetchSupervisors() async => const [
    OptionItem(id: 40, label: 'Fatou Kone'),
  ];
}

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'exams': ModulePermission(
        key: 'exams',
        label: 'Examens',
        group: 'academique',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<void> _monter(WidgetTester tester, AccessLevel niveau) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        examsRepositoryProvider.overrideWithValue(_FauxDepot()),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
      ],
      child: const MaterialApp(home: Scaffold(body: ExamsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Etat actif d'un bouton portant ce libelle, quel que soit son type.
bool _estActif(WidgetTester tester, String libelle) {
  final bouton = find.ancestor(
    of: find.text(libelle),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(bouton, findsWidgets, reason: 'bouton « $libelle » introuvable');
  return (tester.widget(bouton.first) as ButtonStyleButton).onPressed != null;
}

void main() {
  testWidgets('un profil en lecture seule est annonce comme tel', (
    tester,
  ) async {
    await _monter(tester, AccessLevel.read);

    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsOneWidget,
    );
    // Actualiser reste possible: consulter n'est pas ecrire.
    expect(_estActif(tester, 'Actualiser'), isTrue);
    expect(_estActif(tester, 'Imports académiques'), isFalse);
  });

  testWidgets('un profil en ecriture garde ses actions', (tester) async {
    await _monter(tester, AccessLevel.write);

    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsNothing,
    );
    expect(_estActif(tester, 'Imports académiques'), isTrue);
  });

  testWidgets('les sessions chargees s_affichent', (tester) async {
    await _monter(tester, AccessLevel.write);

    expect(find.textContaining('Composition du premier trimestre'), findsWidgets);
  });
}
