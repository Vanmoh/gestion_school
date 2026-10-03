/// La cantine, et ce qu'elle demande au serveur pour s'afficher.
///
/// L'écran chargeait ses cinq sources en un seul groupe, dont l'année scolaire
/// — fermée au parent et à l'élève, qui ont pourtant accès à la cantine. Un
/// refus faisait tomber le groupe entier : la famille voyait « erreur de
/// chargement » à la place des menus de la semaine.
///
/// Ce module n'avait aucun test d'interface. C'est ce qui a laissé le défaut
/// s'installer, et c'est ce qui aurait laissé passer sa réapparition.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/canteen/presentation/canteen_page.dart';

class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];

  /// Les routes que ce profil se voit refuser, comme le serveur le ferait.
  final Set<String> refusees;

  _Transport({this.refusees = const {}});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);

    if (refusees.any(options.path.contains)) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(requestOptions: options, statusCode: 403),
      );
    }

    if (options.path.contains('/canteen-menus')) {
      return _json(const {
        'results': [
          {
            'id': 1,
            'name': 'Riz au gras',
            'date': '2026-03-02',
          },
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

ModulePermissions _droits({
  AccessLevel canteen = AccessLevel.admin,
  bool scoped = false,
}) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'canteen': ModulePermission(
        key: 'canteen',
        label: 'Cantine',
        group: 'ressources',
        level: canteen,
        scoped: scoped,
      ),
    },
  );
}

Future<_Transport> _monter(
  WidgetTester tester, {
  Set<String> refusees = const {},
  ModulePermissions? droits,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(refusees: refusees);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(droits ?? _droits()),
      ],
      child: const MaterialApp(home: Scaffold(body: CanteenPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

void main() {
  testWidgets('l_écran s_affiche quand tout est ouvert', (tester) async {
    await _monter(tester);

    expect(find.textContaining('Erreur'), findsNothing);
  });

  testWidgets('la famille garde la cantine sans le référentiel scolaire', (
    tester,
  ) async {
    // Le parent et l'élève n'ont pas droit aux années scolaires: le groupe
    // entier tombait sur ce seul refus.
    await _monter(
      tester,
      refusees: {'/academic-years'},
      droits: _droits(canteen: AccessLevel.read, scoped: true),
    );

    expect(find.textContaining('Erreur chargement'), findsNothing);
    // Le menu est arrivé: c'est ce que la famille vient voir.
    expect(find.text('Menus: 1'), findsOneWidget);
  });

  testWidgets('le refus n_empêche pas de demander le reste', (tester) async {
    final transport = await _monter(
      tester,
      refusees: {'/academic-years'},
      droits: _droits(canteen: AccessLevel.read, scoped: true),
    );

    // Les quatre autres sources partent malgré le refus de la cinquième.
    for (final route in [
      '/students',
      '/canteen-menus',
      '/canteen-subscriptions',
      '/canteen-services',
    ]) {
      expect(
        transport.chemins.where((chemin) => chemin.contains(route)),
        isNotEmpty,
        reason: '$route aurait dû être demandée',
      );
    }
  });

  testWidgets('une panne du serveur reste visible', (tester) async {
    // Un 403 est une situation normale; une panne ne l'est pas, et la taire
    // la rendrait introuvable.
    FlutterSecureStorage.setMockInitialValues({});
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
      ..httpClientAdapter = _TransportEnPanne();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          currentPermissionsProvider.overrideWithValue(_droits()),
        ],
        child: const MaterialApp(home: Scaffold(body: CanteenPage())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('Erreur'), findsWidgets);
  });

  testWidgets('la famille ne voit aucun formulaire d_écriture', (tester) async {
    // Trois formulaires vivent ici -- créer un menu, abonner un élève,
    // enregistrer un repas servi -- et aucun n'était gardé. La famille, qui a
    // la cantine en lecture seule, les voyait tous, et le serveur refusait
    // ensuite chaque envoi par un 403. Offrir un geste qu'on refusera ensuite
    // est pire qu'un écran vide: on remplit, on clique, et l'on apprend alors
    // qu'on n'y avait pas droit.
    await _monter(
      tester,
      droits: _droits(canteen: AccessLevel.read, scoped: true),
    );

    expect(find.text('Creer un menu'), findsNothing);
    expect(find.textContaining('Abonner'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('le gestionnaire garde ses formulaires', (tester) async {
    // La fermeture ne devait pas déborder sur qui tient la cantine.
    await _monter(tester, droits: _droits(canteen: AccessLevel.write));

    expect(find.text('Creer un menu'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
  });

  testWidgets('la famille garde le suivi des repas', (tester) async {
    // Ce qu'elle vient chercher reste: les repas servis et leur règlement.
    await _monter(
      tester,
      droits: _droits(canteen: AccessLevel.read, scoped: true),
    );

    expect(find.text('Menus: 1'), findsOneWidget);
  });
}

class _TransportEnPanne implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      response: Response<dynamic>(requestOptions: options, statusCode: 500),
    );
  }

  @override
  void close({bool force = false}) {}
}
