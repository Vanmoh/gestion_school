/// Le tableau de bord de la direction, refondu.
///
/// L'écran affichait neuf blocs, quatre graphiques et trois chiffres faux:
/// **611 élèves** pour 450 inscrits, **30 classes** pour 15, et un
/// « Bénéfice net » qui était en réalité le montant encaissé, les charges non
/// doublement validées étant exclues du calcul. Le recouvrement — le chiffre
/// d'une école malienne — n'y figurait pas du tout.
///
/// Les sept intentions des tests précédents sont conservées: la page se
/// construit, elle dit son chargement, elle annonce les dépenses à valider,
/// elle se tait quand il n'y en a pas, une panne se dit, l'axe porte de vrais
/// mois, et une série manquante ne casse rien. S'y ajoutent celles que le
/// défaut réclamait: **l'année est nommée**, et le recouvrement est montré.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/dashboard/domain/dashboard_stats.dart';
import 'package:gestion_school_app/features/dashboard/presentation/dashboard_controller.dart';
import 'package:gestion_school_app/features/dashboard/presentation/dashboard_page.dart';

class _Transport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(const {'count': 0, 'results': []}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Les chiffres réels d'IFP-OBK sur son année active.
///
/// Volontairement ceux de la base: 450 élèves et non 611, 15 classes et non
/// 30, un recouvrement de 93,0 % et 5 040 000 FCFA restants.
const _chiffres = DashboardStats(
  students: 450,
  monthlyRevenue: 66965000,
  monthlyExpenses: 0,
  monthlyExpensesPending: 90000,
  monthlyProfit: 66965000,
  monthlyAbsences: 363,
  classrooms: 15,
  teachers: 58,
  activeEtablissementId: 3,
  activeEtablissementName: 'IFP-OBK',
  academicYearName: '2025-2026',
  academicYearStart: '2025-09-01',
  academicYearEnd: '2026-07-31',
  feesDue: 72000000,
  feesCollected: 66960000,
  feesOutstanding: 5040000,
  collectionRate: 93,
  studentsUnpaid: 112,
  yearExpensesPending: 4124000,
  yearExpensesPendingCount: 36,
);

const _echeancier = Echeancier(
  academicYearName: '2025-2026',
  mois: [
    MoisDEcheance(
      libelle: '10/2025',
      du: 6750000,
      encaisse: 6750000,
      manque: 0,
    ),
    MoisDEcheance(
      libelle: '11/2025',
      du: 6750000,
      encaisse: 6750000,
      manque: 0,
    ),
    MoisDEcheance(
      libelle: '04/2026',
      du: 6750000,
      encaisse: 5070000,
      manque: 1680000,
    ),
  ],
  du: 20250000,
  encaisse: 18570000,
);

ModulePermissions _droits() {
  return ModulePermissions(
    role: 'test',
    modules: {
      'dashboard': const ModulePermission(
        key: 'dashboard',
        label: 'dashboard',
        group: 'pilotage',
        level: AccessLevel.read,
        scoped: false,
      ),
    },
  );
}

Future<void> _monter(
  WidgetTester tester, {
  AsyncValue<DashboardStats> chiffres = const AsyncValue.data(_chiffres),
  AsyncValue<Echeancier> echeancier = const AsyncValue.data(_echeancier),
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _Transport();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits()),
        echeancierProvider.overrideWith((ref) async {
          return echeancier.when(
            data: (valeur) => valeur,
            error: (erreur, pile) => Future<Echeancier>.error(erreur, pile),
            loading: () => Completer<Echeancier>().future,
          );
        }),
        dashboardStatsProvider.overrideWith((ref) async {
          return chiffres.when(
            data: (valeur) => valeur,
            error: (erreur, pile) => Future<DashboardStats>.error(erreur, pile),
            loading: () => Completer<DashboardStats>().future,
          );
        }),
      ],
      child: const MaterialApp(home: Scaffold(body: DashboardPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('l_écran d_accueil se construit sans erreur', (tester) async {
    await _monter(tester);

    expect(find.textContaining('Erreur'), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('pendant le chargement, l_écran le dit', (tester) async {
    await _monter(tester, chiffres: const AsyncValue.loading());

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('une panne se dit au lieu de laisser la page muette', (
    tester,
  ) async {
    await _monter(
      tester,
      chiffres: AsyncValue.error(Exception('serveur muet'), StackTrace.empty),
    );

    expect(find.textContaining('Erreur'), findsWidgets);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  group('l_année est nommée', () {
    testWidgets('elle s_affiche en clair, avec ses bornes', (tester) async {
      await _monter(tester);

      // C'est son absence qui a laissé « 611 élèves » passer pour un effectif:
      // un écran qui ne nomme pas sa période n'invite pas à douter du nombre.
      expect(find.text('Année 2025-2026'), findsOneWidget);
      expect(find.textContaining('du 01/09/2025'), findsOneWidget);
    });

    testWidgets('sans année active, la page le dit au lieu de se taire', (
      tester,
    ) async {
      await _monter(
        tester,
        chiffres: const AsyncValue.data(
          DashboardStats(
            students: 0,
            monthlyRevenue: 0,
            monthlyExpenses: 0,
            monthlyProfit: 0,
            monthlyAbsences: 0,
            classrooms: 0,
            teachers: 0,
            activeEtablissementName: 'IFP-OBK',
          ),
        ),
      );

      expect(find.text('Aucune année active'), findsOneWidget);
    });
  });

  group('les quatre chiffres', () {
    testWidgets('l_effectif est celui de l_année', (tester) async {
      await _monter(tester);

      expect(find.text('450'), findsOneWidget);
      expect(find.textContaining('15 classes'), findsOneWidget);
      expect(find.textContaining('58 enseignants'), findsOneWidget);
    });

    testWidgets('le recouvrement est montré, avec ce qui reste', (
      tester,
    ) async {
      await _monter(tester);

      // Le chiffre d'une école malienne, absent de l'ancien écran.
      expect(find.text('Recouvrement'), findsOneWidget);
      expect(find.text('93,0 %'), findsOneWidget);
      expect(
        find.textContaining('5 040 000 FCFA restent à encaisser'),
        findsOneWidget,
      );
    });

    testWidgets('les dépenses restées à valider sont annoncées', (
      tester,
    ) async {
      await _monter(tester);

      expect(find.text('Dépenses à valider'), findsOneWidget);
      expect(
        find.textContaining('36 lignes attendent une signature'),
        findsOneWidget,
      );
    });

    testWidgets('sans dépense en attente, la carte le dit', (tester) async {
      await _monter(
        tester,
        chiffres: const AsyncValue.data(
          DashboardStats(
            students: 450,
            monthlyRevenue: 0,
            monthlyExpenses: 0,
            monthlyProfit: 0,
            monthlyAbsences: 0,
            classrooms: 15,
            teachers: 58,
            academicYearName: '2025-2026',
            activeEtablissementName: 'IFP-OBK',
          ),
        ),
      );

      expect(
        find.text('Aucune charge en attente de signature'),
        findsOneWidget,
      );
    });
  });

  group('l_échéancier', () {
    testWidgets('l_axe porte de vrais mois', (tester) async {
      await _monter(tester);

      // L'ancienne courbe étiquetait « S-3, S-2, S-1 » trois points obtenus
      // en multipliant le montant du mois par des coefficients écrits en dur.
      expect(find.text('Échéancier et encaissements'), findsOneWidget);
      expect(find.text('10/2025'), findsOneWidget);
      expect(find.text('11/2025'), findsOneWidget);
      expect(find.textContaining('S-1'), findsNothing);
    });

    testWidgets('le décrochage est nommé, et son mois avec', (tester) async {
      await _monter(tester);

      expect(
        find.textContaining('Le recouvrement décroche depuis 04/2026'),
        findsWidgets,
      );
    });

    testWidgets('une série indisponible ne casse pas l_écran', (tester) async {
      await _monter(
        tester,
        echeancier: AsyncValue.error(
          Exception('agrégation lente'),
          StackTrace.empty,
        ),
      );

      // Les quatre chiffres restent: une page amputée d'une courbe vaut mieux
      // qu'une page effacée.
      expect(find.text('450'), findsOneWidget);
      expect(find.text('93,0 %'), findsOneWidget);
      expect(
        find.textContaining('L\'échéancier n\'a pas pu être lu'),
        findsOneWidget,
      );
    });

    testWidgets('sans échéance posée, la page explique quoi faire', (
      tester,
    ) async {
      await _monter(
        tester,
        echeancier: const AsyncValue.data(
          Echeancier(
            academicYearName: '2026-2027',
            mois: [],
            du: 0,
            encaisse: 0,
          ),
        ),
      );

      expect(
        find.textContaining('appliquez un barème de frais'),
        findsOneWidget,
      );
    });
  });

  group('ce qui demande une décision', () {
    testWidgets('chaque ligne mène au module qui la règle', (tester) async {
      await _monter(tester);

      expect(find.text('À traiter'), findsOneWidget);
      expect(
        find.textContaining('36 dépenses attendent une validation'),
        findsOneWidget,
      );
      expect(
        find.textContaining('112 élèves ont un reste à payer'),
        findsOneWidget,
      );
    });

    testWidgets('une école à jour ne s_invente pas de tâches', (tester) async {
      await _monter(
        tester,
        chiffres: const AsyncValue.data(
          DashboardStats(
            students: 450,
            monthlyRevenue: 0,
            monthlyExpenses: 0,
            monthlyProfit: 0,
            monthlyAbsences: 0,
            classrooms: 15,
            teachers: 58,
            academicYearName: '2025-2026',
            activeEtablissementName: 'IFP-OBK',
          ),
        ),
        echeancier: const AsyncValue.data(
          Echeancier(
            academicYearName: '2025-2026',
            mois: [
              MoisDEcheance(
                libelle: '10/2025',
                du: 6750000,
                encaisse: 6750000,
                manque: 0,
              ),
            ],
            du: 6750000,
            encaisse: 6750000,
          ),
        ),
      );

      expect(find.text('Rien n\'attend de décision.'), findsOneWidget);
      expect(find.text('Chaque échéance de l\'année est soldée.'), findsOneWidget);
    });
  });
}
