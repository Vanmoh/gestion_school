/// Les trois tableaux de bord d'encadrement, refondus.
///
/// Ils comptaient des **lignes de table**: « Paiements enregistrés : 4 165 »
/// pour un comptable, « Notes visibles » pour une famille. Le nombre de lignes
/// d'une table ne dit rien à personne; « 93,0 % de recouvrement, 5 040 000
/// FCFA restants » dit tout à un comptable.
///
/// Et ils les obtenaient en rapatriant les lignes pour les compter: 450 élèves
/// et 2 131 absences téléchargés pour afficher deux nombres.
///
/// Ces tests portent sur ce qui compte vraiment: **chaque écran montre le
/// domaine de son rôle, et pas celui du voisin**. La charge utile est
/// restreinte côté serveur (`portee_du_tableau_de_bord.py`), donc un censeur ne
/// reçoit aucune clé de finance — ici on vérifie que l'écran s'en accommode
/// sans afficher de zéro trompeur.
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
import 'package:gestion_school_app/features/dashboard/presentation/dashboards_encadrement.dart';

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

/// La charge utile d'un **comptable**: l'argent, sans les notes ni les
/// absences. `grades` et `attendance` sont à « - » pour lui, donc le serveur ne
/// renvoie pas ces clés et le modèle garde ses valeurs par défaut.
const _duComptable = DashboardStats(
  students: 450,
  monthlyRevenue: 66965000,
  monthlyExpenses: 0,
  monthlyExpensesPending: 90000,
  monthlyProfit: 66965000,
  monthlyAbsences: 0,
  classrooms: 15,
  teachers: 58,
  activeEtablissementName: 'IFP-OBK',
  academicYearName: '2025-2026',
  feesDue: 72000000,
  feesCollected: 66960000,
  feesOutstanding: 5040000,
  collectionRate: 93,
  studentsUnpaid: 112,
  yearExpensesPending: 4124000,
  yearExpensesPendingCount: 36,
  payrollTotal: 29913950,
  payrollCount: 119,
);

/// La charge utile d'un **censeur**: le pédagogique et le service des
/// enseignants, sans aucune clé de finance.
const _duCenseur = DashboardStats(
  students: 450,
  monthlyRevenue: 0,
  monthlyExpenses: 0,
  monthlyProfit: 0,
  monthlyAbsences: 363,
  classrooms: 15,
  teachers: 58,
  activeEtablissementName: 'IFP-OBK',
  academicYearName: '2025-2026',
  generalAverage: 13.3,
  gradesCount: 26730,
  bulletinsDelivered: 276,
  bulletinsTotal: 455,
  bulletinsFailed: 92,
  teacherAbsences: 83,
  teacherLate: 253,
  payrollTotal: 29913950,
  payrollCount: 119,
);

/// La charge utile d'un **surveillant**: l'assiduité des élèves et le stock.
const _duSurveillant = DashboardStats(
  students: 450,
  monthlyRevenue: 0,
  monthlyExpenses: 0,
  monthlyProfit: 0,
  monthlyAbsences: 363,
  classrooms: 15,
  teachers: 0,
  activeEtablissementName: 'IFP-OBK',
  academicYearName: '2025-2026',
  bulletinsDelivered: 276,
  bulletinsTotal: 455,
  stockBelowThreshold: 1,
  stockTotal: 5,
  studentsUnassigned: 0,
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
  WidgetTester tester,
  Widget ecran, {
  AsyncValue<DashboardStats>? etat,
  DashboardStats? chiffres,
}) async {
  final valeur = etat ?? AsyncValue.data(chiffres ?? _duComptable);
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
        dashboardStatsProvider.overrideWith((ref) async {
          return valeur.when(
            data: (donnees) => donnees,
            error: (erreur, pile) => Future<DashboardStats>.error(erreur, pile),
            loading: () => Completer<DashboardStats>().future,
          );
        }),
      ],
      child: MaterialApp(home: Scaffold(body: ecran)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('le comptable', () {
    testWidgets('voit l_argent, nommé et interprété', (tester) async {
      await _monter(
        tester,
        const AccountantDashboardPage(),
        chiffres: _duComptable,
      );

      expect(find.text('L\'ARGENT'), findsOneWidget);
      expect(find.text('93,0 %'), findsOneWidget);
      expect(
        find.textContaining('5 040 000 FCFA restent à encaisser'),
        findsOneWidget,
      );
      expect(find.text('Masse salariale'), findsOneWidget);
      expect(find.textContaining('119 fiches de paie'), findsOneWidget);
    });

    testWidgets('ne compte plus des lignes de table', (tester) async {
      await _monter(
        tester,
        const AccountantDashboardPage(),
        chiffres: _duComptable,
      );

      // « Paiements enregistrés », « Frais élèves », « Dépenses »: des nombres
      // de lignes, qui ne disaient rien à personne.
      expect(find.textContaining('Paiements enregistrés'), findsNothing);
      expect(find.textContaining('Frais élèves'), findsNothing);
    });

    testWidgets('sa file de validation passe en tête d_À traiter', (
      tester,
    ) async {
      await _monter(
        tester,
        const AccountantDashboardPage(),
        chiffres: _duComptable,
      );

      expect(
        find.textContaining('36 dépenses attendent une validation'),
        findsOneWidget,
      );
    });

    testWidgets('l_année est nommée, comme chez la direction', (tester) async {
      await _monter(
        tester,
        const AccountantDashboardPage(),
        chiffres: _duComptable,
      );

      expect(find.text('Année 2025-2026'), findsOneWidget);
    });
  });

  group('le censeur', () {
    testWidgets('voit le pédagogique et le service des enseignants', (
      tester,
    ) async {
      await _monter(tester, const CensorDashboardPage(), chiffres: _duCenseur);

      expect(find.text('L\'ÉCOLE'), findsOneWidget);
      expect(find.text('13,30'), findsOneWidget);
      expect(find.text('Bulletins remis'), findsOneWidget);
      expect(find.text('Assiduité enseignants'), findsOneWidget);
      expect(find.textContaining('253 retards également'), findsOneWidget);
    });

    testWidgets('ne voit pas la caisse, et n_affiche pas de zéro trompeur', (
      tester,
    ) async {
      await _monter(tester, const CensorDashboardPage(), chiffres: _duCenseur);

      // `finance` est à « - » pour lui: le serveur ne renvoie aucune de ces
      // clés, et l'écran ne doit pas inventer « 0 % de recouvrement », qui se
      // lirait comme une catastrophe.
      expect(find.text('Recouvrement'), findsNothing);
      expect(find.textContaining('restent à encaisser'), findsNothing);
      expect(find.text('Dépenses à valider'), findsNothing);
    });

    testWidgets('les bulletins manquants l_appellent à agir', (tester) async {
      await _monter(tester, const CensorDashboardPage(), chiffres: _duCenseur);

      // 455 préparés, 276 remis: 179 restent, dont 92 en échec d'envoi.
      expect(
        find.textContaining('179 bulletins ne sont pas remis'),
        findsOneWidget,
      );
      expect(
        find.textContaining('dont 92 en échec d\'envoi'),
        findsOneWidget,
      );
    });
  });

  group('le surveillant', () {
    testWidgets('voit l_assiduité des élèves', (tester) async {
      await _monter(
        tester,
        const SupervisorDashboardPage(),
        chiffres: _duSurveillant,
      );

      expect(find.text('L\'ASSIDUITÉ'), findsOneWidget);
      expect(find.text('Absences du mois'), findsOneWidget);
      expect(find.text('363'), findsOneWidget);
      expect(find.text('Élèves suivis'), findsOneWidget);
    });

    testWidgets('ne voit ni la caisse ni l_émargement des enseignants', (
      tester,
    ) async {
      await _monter(
        tester,
        const SupervisorDashboardPage(),
        chiffres: _duSurveillant,
      );

      // L'ancien écran lui montrait le recouvrement de l'école.
      expect(find.text('Recouvrement'), findsNothing);
      expect(find.text('Masse salariale'), findsNothing);
      expect(find.text('Assiduité enseignants'), findsNothing);
    });

    testWidgets('le stock sous seuil l_appelle à agir', (tester) async {
      await _monter(
        tester,
        const SupervisorDashboardPage(),
        chiffres: _duSurveillant,
      );

      expect(
        find.textContaining('1 article est sous leur seuil'),
        findsOneWidget,
      );
    });
  });

  group('les trois parlent la même langue', () {
    testWidgets('une panne se dit, au lieu d_une page muette', (tester) async {
      await _monter(
        tester,
        const AccountantDashboardPage(),
        etat: AsyncValue.error(Exception('serveur muet'), StackTrace.empty),
      );

      expect(find.textContaining('Erreur'), findsWidgets);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('pendant le chargement, l_écran le dit', (tester) async {
      await _monter(
        tester,
        const CensorDashboardPage(),
        etat: const AsyncValue.loading(),
      );

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });
  });
}
