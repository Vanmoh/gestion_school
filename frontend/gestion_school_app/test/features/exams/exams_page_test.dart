/// L'écran Examens, rangé par la question qu'on se pose.
///
/// Il empilait quatre formulaires et quatre listes calqués sur les quatre
/// ViewSets du backend : un censeur y voyait la plomberie du module, pas son
/// travail. Trois onglets le suivent désormais — préparer la campagne,
/// planifier les épreuves, les faire surveiller — et la publication se décide
/// là où les copies reviennent, épreuve par épreuve.
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
import 'package:gestion_school_app/features/exams/presentation/exams_module_page.dart';

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
  sessionTitle: 'Composition du premier trimestre',
  resultatsSaisis: 1,
);

/// L'épreuve de référence, avec ce qu'on veut lui faire dire.
ExamPlanningItem _epreuveTelleQue({
  int id = 5,
  String classe = '6A',
  int resultatsSaisis = 1,
  bool resultatsPublies = false,
}) {
  return ExamPlanningItem(
    id: id,
    sessionId: _epreuve.sessionId,
    classroomId: _epreuve.classroomId,
    subjectId: _epreuve.subjectId,
    examDate: _epreuve.examDate,
    startTime: _epreuve.startTime,
    endTime: _epreuve.endTime,
    classroomName: classe,
    subjectName: _epreuve.subjectName,
    sessionTitle: _epreuve.sessionTitle,
    resultatsSaisis: resultatsSaisis,
    resultatsPublies: resultatsPublies,
  );
}

class _FauxDepot extends ExamsRepository {
  final ExamSessionItem session;
  final List<ExamPlanningItem> epreuves;
  final List<ExamInvigilationItem> affectations;

  /// Ce que l'écran a demandé au serveur : les gestes, et les filtres.
  final List<String> gestes = [];
  final List<String> filtres = [];

  _FauxDepot({
    this.session = _session,
    List<ExamPlanningItem>? epreuves,
    this.affectations = const [],
  }) : epreuves = epreuves ?? const [_epreuve],
       super(Dio());

  @override
  Future<List<ExamSessionItem>> fetchSessions() async => [session];

  @override
  Future<List<ExamPlanningItem>> fetchPlannings({
    int? sessionId,
    int? classroomId,
    int? subjectId,
    bool? publiees,
  }) async {
    filtres.add('session=$sessionId classe=$classroomId publiees=$publiees');
    return epreuves;
  }

  @override
  Future<List<ExamResultItem>> fetchResults({int? planningId}) async {
    if (planningId != null) filtres.add('notes-de=$planningId');
    return const [
      ExamResultItem(
        id: 7,
        sessionId: 1,
        studentId: 30,
        subjectId: 20,
        score: 15.5,
        studentFullName: 'Awa Traore',
        subjectName: 'Mathematiques',
      ),
    ];
  }

  @override
  Future<List<ExamInvigilationItem>> fetchInvigilations() async => affectations;

  @override
  Future<String> publierLEpreuve(int planningId) async {
    gestes.add('publier-epreuve:$planningId');
    return 'Résultats publiés.';
  }

  @override
  Future<String> retirerLEpreuve(int planningId) async {
    gestes.add('retirer-epreuve:$planningId');
    return 'Résultats retirés.';
  }

  @override
  Future<String> publierLesResultats(int sessionId) async {
    gestes.add('tout-publier:$sessionId');
    return 'Résultats publiés.';
  }

  @override
  Future<InventaireDeSuppression> inventaireDeLaSession(int id) async {
    gestes.add('inventaire:$id');
    return const InventaireDeSuppression(
      titre: 'Composition du premier trimestre',
      epreuves: 1,
      notes: 1,
    );
  }

  @override
  Future<void> deleteSession(int id) async => gestes.add('supprimer-session:$id');

  @override
  Future<void> deletePlanning(int id) async => gestes.add('supprimer-epreuve:$id');

  @override
  Future<List<OptionItem>> fetchAcademicYears() async => const [
    OptionItem(id: 1, label: '2025-2026'),
  ];

  @override
  Future<List<OptionItem>> fetchClassrooms() async => const [
    OptionItem(id: 10, label: '6A'),
    OptionItem(id: 11, label: '5B'),
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

ModulePermissions _droits(AccessLevel niveau, {bool peutPublier = true}) {
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
    capabilities: {Capacites.publicationDesExamens: peutPublier},
  );
}

Future<_FauxDepot> _monter(
  WidgetTester tester,
  AccessLevel niveau, {
  ExamSessionItem session = _session,
  List<ExamPlanningItem>? epreuves,
  List<ExamInvigilationItem> affectations = const [],
  bool peutPublier = true,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final depot = _FauxDepot(
    session: session,
    epreuves: epreuves,
    affectations: affectations,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        examsRepositoryProvider.overrideWithValue(depot),
        currentPermissionsProvider.overrideWithValue(
          _droits(niveau, peutPublier: peutPublier),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: ExamsModulePage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return depot;
}

/// Ouvre l'onglet portant ce libellé, et attend ce qu'il charge.
///
/// Un onglet ne demande ses données qu'à sa première ouverture — la
/// surveillance ne charge ses affectations que là. Sans cette seconde
/// attente, le test lit un indicateur de chargement.
Future<void> _onglet(WidgetTester tester, String libelle) async {
  await tester.tap(find.widgetWithText(Tab, libelle));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Appuie sur un bouton et laisse expirer le minuteur de la notification.
Future<void> _appuyer(WidgetTester tester, Key cle) async {
  await tester.ensureVisible(find.byKey(cle));
  await tester.tap(find.byKey(cle));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  group('la coque', () {
    testWidgets('trois onglets, dans l_ordre du travail', (tester) async {
      // Préparer la campagne, planifier, faire surveiller: c'est la séquence
      // que la procédure de rentrée décrit.
      await _monter(tester, AccessLevel.write);

      expect(find.widgetWithText(Tab, 'Campagnes'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Calendrier'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Surveillance'), findsOneWidget);
    });

    testWidgets('l_en-tête dit ce qui reste à publier', (tester) async {
      // Le chiffre que la direction cherche en fin de trimestre.
      await _monter(tester, AccessLevel.write);

      expect(find.text('Prêtes à publier'), findsOneWidget);
    });

    testWidgets('un profil en lecture seule est annoncé comme tel', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.read);

      expect(find.textContaining('Consultation seule'), findsOneWidget);
    });
  });

  group('onglet Campagnes', () {
    testWidgets('la création est repliée par défaut', (tester) async {
      // Elle occupait la page en permanence, y compris pour un profil qui ne
      // crée rien.
      await _monter(tester, AccessLevel.write);

      expect(find.byKey(const Key('basculer-creation-campagne')), findsOneWidget);
      expect(find.byKey(const Key('titre-campagne')), findsNothing);
    });

    testWidgets('elle se déplie à la demande', (tester) async {
      await _monter(tester, AccessLevel.write);

      await tester.tap(find.byKey(const Key('basculer-creation-campagne')));
      await tester.pump();

      expect(find.byKey(const Key('titre-campagne')), findsOneWidget);
    });

    testWidgets('en lecture seule, rien ne se crée', (tester) async {
      await _monter(tester, AccessLevel.read);

      expect(find.byKey(const Key('basculer-creation-campagne')), findsNothing);
    });

    testWidgets('l_avancement est un compte, pas un booléen', (tester) async {
      // « Publiée » devant trois épreuves ouvertes sur sept serait faux.
      await _monter(tester, AccessLevel.write);

      expect(
        find.textContaining('0/1 épreuve(s) publiée(s)'),
        findsOneWidget,
      );
    });

    testWidgets('supprimer une campagne dit d_abord ce qu_elle emporte', (
      tester,
    ) async {
      // Ses épreuves, ses surveillances et toutes ses notes partent en
      // cascade — et des notes figurent sur des bulletins déjà imprimés.
      final depot = await _monter(tester, AccessLevel.write);

      await tester.tap(find.byKey(const Key('supprimer-campagne-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(depot.gestes, contains('inventaire:1'));
      expect(find.textContaining('1 note(s)'), findsWidgets);
      expect(depot.gestes, isNot(contains('supprimer-session:1')));
    });

    testWidgets('sans le droit de publier, le bouton n_apparaît pas', (
      tester,
    ) async {
      // Ouvrir aux familles est une décision de la direction, pas une
      // conséquence de pouvoir corriger.
      await _monter(tester, AccessLevel.write, peutPublier: false);

      expect(find.byKey(const Key('tout-publier-1')), findsNothing);
    });
  });

  group('onglet Calendrier', () {
    testWidgets('une épreuve se nomme par sa classe et sa matière', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.write);
      await _onglet(tester, 'Calendrier');

      expect(find.text('6A • Mathematiques'), findsOneWidget);
    });

    testWidgets('l_état de correction se lit sur chaque ligne', (tester) async {
      // Rien ne distinguait une épreuve corrigée d'une épreuve en attente.
      await _monter(tester, AccessLevel.write);
      await _onglet(tester, 'Calendrier');

      expect(
        find.textContaining('1 note(s) saisie(s), non publiées'),
        findsOneWidget,
      );
    });

    testWidgets('une épreuve corrigée se publie seule', (tester) async {
      final depot = await _monter(tester, AccessLevel.write);
      await _onglet(tester, 'Calendrier');

      await _appuyer(tester, const ValueKey('publier-epreuve-5'));

      expect(depot.gestes, contains('publier-epreuve:5'));
    });

    testWidgets('une épreuve publiée se retire', (tester) async {
      final depot = await _monter(
        tester,
        AccessLevel.write,
        epreuves: [_epreuveTelleQue(resultatsPublies: true)],
      );
      await _onglet(tester, 'Calendrier');

      await _appuyer(tester, const ValueKey('retirer-epreuve-5'));

      expect(depot.gestes, contains('retirer-epreuve:5'));
    });

    testWidgets('une épreuve sans note ne se publie pas', (tester) async {
      await _monter(
        tester,
        AccessLevel.write,
        epreuves: [_epreuveTelleQue(resultatsSaisis: 0)],
      );
      await _onglet(tester, 'Calendrier');

      final bouton = tester.widget<ButtonStyleButton>(
        find.byKey(const ValueKey('publier-epreuve-5')),
      );
      expect(bouton.onPressed, isNull);
      expect(find.textContaining('Aucune note saisie'), findsOneWidget);
    });

    testWidgets('on voit ce qu_on publie avant de le publier', (tester) async {
      // La question qu'on se pose au moment de cliquer, et à laquelle rien
      // ne répondait.
      final depot = await _monter(tester, AccessLevel.write);
      await _onglet(tester, 'Calendrier');

      await tester.tap(find.text('6A • Mathematiques'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(depot.filtres, contains('notes-de=5'));
      expect(find.text('Awa Traore'), findsOneWidget);
      expect(find.textContaining('les familles ne les voient pas'), findsOneWidget);
    });

    testWidgets('le filtre part au serveur, pas en mémoire', (tester) async {
      // Une école de quinze classes déroulait sinon tout son calendrier.
      final depot = await _monter(tester, AccessLevel.write);
      await _onglet(tester, 'Calendrier');

      await tester.tap(find.byKey(const Key('filtre-a-publier')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        depot.filtres,
        contains('session=null classe=null publiees=false'),
      );
    });

    testWidgets('en lecture seule, aucun geste n_est offert', (tester) async {
      await _monter(tester, AccessLevel.read);
      await _onglet(tester, 'Calendrier');

      expect(find.byKey(const ValueKey('publier-epreuve-5')), findsNothing);
      expect(find.byKey(const ValueKey('supprimer-epreuve-5')), findsNothing);
      expect(find.byKey(const Key('basculer-creation-epreuve')), findsNothing);
    });
  });

  group('onglet Surveillance', () {
    testWidgets('une épreuve sans surveillant se voit en premier', (
      tester,
    ) async {
      // La seule question qu'on se pose la veille des compositions, et elle
      // n'était posée nulle part.
      await _monter(tester, AccessLevel.write);
      await _onglet(tester, 'Surveillance');

      expect(find.text('Épreuves sans surveillant'), findsOneWidget);
      expect(find.byKey(const ValueKey('sans-surveillant-5')), findsOneWidget);
    });

    testWidgets('toutes tenues, l_écran le dit', (tester) async {
      await _monter(
        tester,
        AccessLevel.write,
        affectations: const [
          ExamInvigilationItem(
            id: 9,
            planningId: 5,
            supervisorId: 40,
            supervisorName: 'Fatou Kone',
          ),
        ],
      );
      await _onglet(tester, 'Surveillance');

      expect(
        find.textContaining('Toutes les épreuves ont un surveillant'),
        findsOneWidget,
      );
    });

    testWidgets('une affectation nomme l_épreuve, pas son numéro', (
      tester,
    ) async {
      await _monter(
        tester,
        AccessLevel.write,
        affectations: const [
          ExamInvigilationItem(
            id: 9,
            planningId: 5,
            supervisorId: 40,
            supervisorName: 'Fatou Kone',
          ),
        ],
      );
      await _onglet(tester, 'Surveillance');

      expect(find.text('Fatou Kone'), findsOneWidget);
      expect(find.text('6A • Mathematiques'), findsOneWidget);
    });
  });
}
