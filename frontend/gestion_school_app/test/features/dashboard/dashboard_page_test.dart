/// Le tableau de bord, écran d'accueil de tous les profils.
///
/// C'est le premier écran que chacun voit en se connectant, et il n'avait
/// aucun test. Il lit ses chiffres par des providers et complète par des
/// appels directs : ce qui suit vérifie qu'il s'affiche, qu'il dit son état
/// pendant le chargement, et qu'une panne n'y laisse pas une page muette.
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
import 'package:gestion_school_app/features/payments/domain/payment.dart';
import 'package:gestion_school_app/features/payments/domain/student_fee.dart';
import 'package:gestion_school_app/features/payments/presentation/payments_controller.dart';

class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);
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

const _chiffres = DashboardStats(
  students: 128,
  monthlyRevenue: 450000,
  monthlyExpenses: 120000,
  monthlyProfit: 330000,
  monthlyAbsences: 7,
  classrooms: 9,
  teachers: 14,
  activeEtablissementId: 1,
  activeEtablissementName: 'IFP-OBK',
);

ModulePermissions _droits(Map<String, AccessLevel> niveaux) {
  return ModulePermissions(
    role: 'test',
    modules: {
      for (final entree in niveaux.entries)
        entree.key: ModulePermission(
          key: entree.key,
          label: entree.key,
          group: 'pilotage',
          level: entree.value,
          scoped: false,
        ),
    },
  );
}

Future<void> _monter(
  WidgetTester tester, {
  AsyncValue<DashboardStats> chiffres = const AsyncValue.data(_chiffres),
  Map<String, AccessLevel> niveaux = const {},
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
        currentPermissionsProvider.overrideWithValue(
          _droits({'dashboard': AccessLevel.read, ...niveaux}),
        ),
        // Ces deux-là gardent leur valeur en cache derrière un minuteur de
        // trois minutes: en les servant directement, le test n'en crée aucun
        // et ne se termine pas sur une fuite qui n'existe pas.
        paymentsProvider.overrideWith((ref) async => const <PaymentItem>[]),
        feesProvider.overrideWith((ref) async => const <StudentFeeItem>[]),
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
  // Deux temps d'attente: l'écran d'accueil pose de courts minuteurs
  // d'animation qu'il faut laisser s'achever, sinon le test se termine
  // dessus.
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('l_écran d_accueil se construit sans erreur', (tester) async {
    // Le détail affiché dépend du tableau de bord propre au rôle connecté;
    // ce que ce test fixe, c'est que l'écran d'accueil de tous les profils
    // se monte et n'annonce pas de panne.
    await _monter(tester);

    expect(find.textContaining('Erreur'), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('pendant le chargement, l_écran le dit', (tester) async {
    // Une page blanche se lit comme une panne; un indicateur se lit comme
    // une attente.
    await _monter(tester, chiffres: const AsyncValue.loading());

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('une panne se dit au lieu de laisser la page muette', (
    tester,
  ) async {
    await _monter(
      tester,
      chiffres: AsyncValue.error(
        DioException(requestOptions: RequestOptions(path: '/dashboard/')),
        StackTrace.empty,
      ),
    );

    expect(find.textContaining('Erreur'), findsWidgets);
  });
}
