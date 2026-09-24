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
  resultatsSaisis: 1,
  epreuvesTotal: 1,
);

const _epreuve = ExamPlanningItem(
  id: 5,
  sessionId: 1,
  classroomId: 10,
  subjectId: 20,
  examDate: '2025-12-01',
  startTime: '08:00',
  endTime: '10:00',
  classroomName: '6A',
  subjectName: 'Mathematiques',
  sessionTitle: 'Composition T1',
  resultatsSaisis: 1,
);

class _FauxDepot extends ExamsRepository {
  /// La session servie: publiée ou non, avec ou sans note saisie. C'est elle
  /// qui décide de l'état du bouton de publication.
  final ExamSessionItem session;

  /// L'épreuve servie: c'est elle qui porte désormais la publication.
  final ExamPlanningItem epreuve;

  /// Ce que l'écran a demandé au serveur, pour vérifier qu'il vise bien
  /// l'épreuve et non la campagne.
  final List<String> gestes = [];

  _FauxDepot({this.session = _session, this.epreuve = _epreuve}) : super(Dio());

  @override
  Future<List<ExamSessionItem>> fetchSessions() async => [session];

  @override
  Future<List<ExamPlanningItem>> fetchPlannings() async => [epreuve];

  @override
  Future<String> publierLEpreuve(int planningId) async {
    gestes.add('publier:$planningId');
    return 'Résultats publiés.';
  }

  @override
  Future<String> retirerLEpreuve(int planningId) async {
    gestes.add('retirer:$planningId');
    return 'Résultats retirés.';
  }

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

Future<_FauxDepot> _monter(
  WidgetTester tester,
  AccessLevel niveau, {
  ExamSessionItem session = _session,
  ExamPlanningItem epreuve = _epreuve,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final depot = _FauxDepot(session: session, epreuve: epreuve);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        examsRepositoryProvider.overrideWithValue(depot),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
      ],
      child: const MaterialApp(home: Scaffold(body: ExamsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return depot;
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

  group('la publication des résultats', () {
    // Les notes étaient lisibles par les familles dès la saisie: un élève
    // voyait passer un chiffre avant que le jury ne l'ait arrêté.

    testWidgets('une session non publiée propose de la publier', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.write);

      expect(find.text('Publication des résultats'), findsOneWidget);
      // La session resume ses epreuves: un booleen dirait « publiee »
      // devant trois epreuves ouvertes sur sept.
      expect(
        find.textContaining('0/1 épreuve(s) publiée(s)'),
        findsOneWidget,
      );
      expect(_estActif(tester, 'Tout publier'), isTrue);
    });

    testWidgets('une session sans note ne se publie pas', (tester) async {
      // Publier le vide ferait chercher aux familles ce qui n'existe pas.
      await _monter(
        tester,
        AccessLevel.write,
        session: const ExamSessionItem(
          id: 1,
          title: 'Session vide',
          term: 'T1',
          academicYearId: 1,
          startDate: '2025-12-01',
          endDate: '2025-12-06',
          resultatsSaisis: 0,
        ),
      );

      expect(_estActif(tester, 'Tout publier'), isFalse);
    });

    testWidgets('une session publiée propose de la retirer', (tester) async {
      await _monter(
        tester,
        AccessLevel.write,
        session: const ExamSessionItem(
          id: 1,
          title: 'Composition du premier trimestre',
          term: 'T1',
          academicYearId: 1,
          startDate: '2025-12-01',
          endDate: '2025-12-06',
          resultatsPublies: true,
          resultatsSaisis: 1,
          epreuvesTotal: 1,
          epreuvesPubliees: 1,
        ),
      );

      expect(find.textContaining('1/1 épreuve(s) publiée(s)'), findsOneWidget);
      expect(_estActif(tester, 'Tout retirer'), isTrue);
    });

    testWidgets('en lecture seule, la publication reste fermée', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.read);

      expect(_estActif(tester, 'Tout publier'), isFalse);
    });
  });

  group('la publication par épreuve', () {
    // Elle se décidait pour la campagne entière, alors que les copies
    // reviennent classe par classe: la direction devait ouvrir aussi ce qui
    // n'était pas corrigé, ou ne rien ouvrir.

    Future<void> tapoter(WidgetTester tester, Key cle) async {
      await tester.ensureVisible(find.byKey(cle));
      await tester.tap(find.byKey(cle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // La notification de succes pose un minuteur: sans le laisser
      // expirer, le test echoue sur « a Timer is still pending ».
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('une épreuve corrigée se publie seule', (tester) async {
      final depot = await _monter(tester, AccessLevel.write);

      await tapoter(tester, const ValueKey('publier-epreuve-5'));

      expect(depot.gestes, ['publier:5']);
    });

    testWidgets('une épreuve publiée se retire', (tester) async {
      final depot = await _monter(
        tester,
        AccessLevel.write,
        epreuve: _epreuveTelleQue(resultatsPublies: true),
      );

      await tapoter(tester, const ValueKey('retirer-epreuve-5'));

      expect(depot.gestes, ['retirer:5']);
    });

    testWidgets('une épreuve sans note ne se publie pas', (tester) async {
      // Publier le vide ferait chercher aux familles des notes qui
      // n'existent pas encore.
      await _monter(
        tester,
        AccessLevel.write,
        epreuve: _epreuveTelleQue(resultatsSaisis: 0),
      );

      final bouton = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('publier-epreuve-5')),
      );
      expect(bouton.onPressed, isNull);
      expect(find.textContaining('Aucune note saisie'), findsOneWidget);
    });

    testWidgets('l_état de correction se lit sur chaque épreuve', (
      tester,
    ) async {
      // Rien ne distinguait une épreuve corrigée d'une épreuve en attente.
      await _monter(tester, AccessLevel.write);

      expect(
        find.textContaining('1 note(s) saisie(s), non publiées'),
        findsWidgets,
      );
    });

    testWidgets('l_épreuve est nommée par sa classe et sa matière', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.write);

      expect(find.text('6A • Mathematiques'), findsOneWidget);
    });

    testWidgets('en lecture seule, aucun bouton de publication', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.read);

      expect(find.byKey(const ValueKey('publier-epreuve-5')), findsNothing);
      expect(find.byKey(const ValueKey('retirer-epreuve-5')), findsNothing);
    });

    testWidgets('la saisie d_un résultat a quitté cet écran', (tester) async {
      // Deux chemins pour le même geste, dont un seul respectait le verrou
      // de trimestre: c'est leur coexistence qui a produit des notes sans
      // épreuve. La saisie se fait dans « Notes & Bulletins ».
      await _monter(tester, AccessLevel.write);

      expect(find.text('Publier résultat'), findsNothing);
      expect(find.text('Publier un résultat'), findsNothing);
    });
  });
}

/// L'épreuve de référence, avec ce qu'on veut lui faire dire.
ExamPlanningItem _epreuveTelleQue({
  int resultatsSaisis = 1,
  bool resultatsPublies = false,
}) {
  return ExamPlanningItem(
    id: _epreuve.id,
    sessionId: _epreuve.sessionId,
    classroomId: _epreuve.classroomId,
    subjectId: _epreuve.subjectId,
    examDate: _epreuve.examDate,
    startTime: _epreuve.startTime,
    endTime: _epreuve.endTime,
    classroomName: _epreuve.classroomName,
    subjectName: _epreuve.subjectName,
    sessionTitle: _epreuve.sessionTitle,
    resultatsSaisis: resultatsSaisis,
    resultatsPublies: resultatsPublies,
  );
}
