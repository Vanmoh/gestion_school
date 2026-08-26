/// L'ecran de passation: ce qui separe un clic de la rentree suivante.
///
/// « Simuler » et « Executer » sont deux boutons voisins, et seul le second
/// reaffecte toute l'ecole, archive les sortants et ecrit leur historique.
/// Rien ne verifiait ni les droits, ni qu'une confirmation soit demandee.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/promotion/presentation/promotion_page.dart';

/// Transport qui repond par chemin et retient les envois.
class _Transport implements HttpClientAdapter {
  final List<RequestOptions> envois = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method != 'GET') {
      envois.add(options);
      return _json(const {'id': 1, 'status': 'executed'});
    }

    final chemin = options.path;
    if (chemin.contains('/academic-years/')) {
      return _json({
        'results': [
          {'id': 1, 'name': '2025-2026', 'is_active': true},
          {'id': 2, 'name': '2026-2027', 'is_active': false},
        ],
      });
    }
    if (chemin.contains('/classrooms/')) {
      return _json({
        'results': [
          {'id': 10, 'name': '6A', 'academic_year': 1},
          {'id': 11, 'name': '5A', 'academic_year': 2},
        ],
      });
    }
    return _json(const {'results': []});
  }

  ResponseBody _json(Object data) => ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'promotion': ModulePermission(
        key: 'promotion',
        label: 'Passation & Archivage',
        group: 'academique',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<_Transport> _monter(WidgetTester tester, AccessLevel niveau) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
      ],
      child: const MaterialApp(home: Scaffold(body: PromotionPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return transport;
}

void main() {
  testWidgets('le censeur, en lecture seule, n_obtient aucun bouton', (
    tester,
  ) async {
    // La matrice lui donne « L » sur la passation. L'ecran ne lisait aucun
    // droit: il proposait deux boutons actifs et le serveur repondait 403.
    await _monter(tester, AccessLevel.read);

    expect(find.byKey(const Key('bouton-simuler')), findsNothing);
    expect(find.byKey(const Key('bouton-executer')), findsNothing);
    expect(
      find.textContaining('reserve a la direction'),
      findsOneWidget,
    );
  });

  testWidgets('la direction dispose des deux boutons', (tester) async {
    await _monter(tester, AccessLevel.admin);

    expect(find.byKey(const Key('bouton-simuler')), findsOneWidget);
    expect(find.byKey(const Key('bouton-executer')), findsOneWidget);
  });

  testWidgets('simuler part sans confirmation', (tester) async {
    // Une simulation ne touche a rien: la faire confirmer aurait use le
    // reflexe qui protege l'execution.
    final transport = await _monter(tester, AccessLevel.admin);

    await tester.tap(find.byKey(const Key('bouton-simuler')));
    await tester.pumpAndSettle();

    expect(transport.envois.length, 1);
    expect(transport.envois.single.path, contains('/promotion-runs/simulate/'));
  });

  testWidgets('executer demande confirmation avant de partir', (tester) async {
    final transport = await _monter(tester, AccessLevel.admin);

    await tester.tap(find.byKey(const Key('bouton-executer')));
    await tester.pumpAndSettle();

    // Rien n'est parti tant que la question n'a pas de reponse.
    expect(transport.envois, isEmpty);
    expect(find.text('Executer la passation ?'), findsOneWidget);
    expect(find.textContaining('ne peut pas etre annulee'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmer-execution')));
    await tester.pumpAndSettle();

    expect(transport.envois.length, 1);
    expect(transport.envois.single.path, contains('/promotion-runs/execute/'));
  });

  testWidgets('annuler la confirmation n_execute rien', (tester) async {
    final transport = await _monter(tester, AccessLevel.admin);

    await tester.tap(find.byKey(const Key('bouton-executer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(transport.envois, isEmpty);
  });
}
