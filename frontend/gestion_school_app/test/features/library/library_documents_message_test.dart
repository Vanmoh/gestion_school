/// Ce que l'ecran dit quand un document ne s'ouvre pas.
///
/// Le telechargement d'un PDF demande `ResponseType.bytes`, et Dio applique
/// ce choix a la reponse d'erreur comme aux autres: le message du serveur
/// arrivait donc en liste d'octets, jamais en Map, et la branche qui lit
/// `detail` ne pouvait pas se declencher. « Ce document n'a pas encore ete
/// rapatrie sur le serveur de l'ecole » s'affichait en
/// « DioException [bad response]: 503 » -- une phrase ecrite pour un
/// bibliothecaire, rendue illisible avant de l'atteindre.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/library/presentation/library_documents_page.dart';

const _refus =
    "Ce document n'a pas encore ete rapatrie sur le serveur de l'ecole: "
    "il ne peut pas etre ouvert sans Internet.";

class _Transport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/file/')) {
      // Le corps tel que Dio le rend quand la requete demandait des octets.
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 503,
          data: utf8.encode(jsonEncode({'detail': _refus})),
        ),
      );
    }
    if (options.path.contains('/library-collections/')) {
      return _json([
        {
          'id': 1,
          'code': 'TSExp',
          'label': 'Terminale Sciences Expérimentales',
          'document_count': 1,
          'categories': [
            {'id': 11, 'name': 'Mathematiques', 'document_count': 1},
          ],
        },
      ]);
    }
    return _json({
      'count': 1,
      'next': null,
      'results': [
        {
          'id': 201,
          'title': 'Annales-2020',
          'category': 11,
          'category_name': 'Mathematiques',
          'size_bytes': 0,
          'is_downloaded': false,
          // Le serveur l'annonce lisible: le relais est ouvert. C'est la
          // source qui se derobe au moment du clic.
          'is_readable': true,
          'import_error': '',
          'origin': 'import',
        },
      ],
    });
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

ModulePermissions _droits() => ModulePermissions(
  role: 'directeur',
  modules: {
    'library': const ModulePermission(
      key: 'library',
      label: 'library',
      group: 'administration',
      level: AccessLevel.admin,
      scoped: false,
    ),
  },
);

void main() {
  testWidgets('le refus du serveur s_affiche tel qu_il est ecrit', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
      ..httpClientAdapter = _Transport();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          currentPermissionsProvider.overrideWithValue(_droits()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: LibraryDocumentsPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Mathematiques'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annales-2020'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.textContaining('pas encore ete rapatrie'), findsOneWidget);
    expect(find.textContaining('DioException'), findsNothing);
  });
}
