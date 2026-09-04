/// Les imports académiques, et ce qu'ils réclament pour s'ouvrir.
///
/// L'écran charge trois référentiels d'un coup — classes, années, sessions
/// d'examen. Les profils qui y ont droit (super-administrateur, direction,
/// censeur) ont aussi ces trois-là, mais rien ne le garantissait : c'est le
/// genre d'accord tacite qui se défait à la première case de matrice changée.
///
/// Le module n'avait aucun test d'interface.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/imports/presentation/academic_imports_page.dart';

class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);

    if (options.path.contains('/classrooms')) {
      return _json(const {
        'results': [
          {'id': 10, 'name': '6ème A', 'academic_year': 1},
        ],
      });
    }
    if (options.path.contains('/academic-years')) {
      return _json(const {
        'results': [
          {'id': 1, 'name': '2025-2026', 'is_active': true},
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
  AccessLevel imports = AccessLevel.write,
  AccessLevel academics = AccessLevel.write,
}) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'academic_imports': ModulePermission(
        key: 'academic_imports',
        label: 'Imports académiques',
        group: 'academique',
        level: imports,
        scoped: false,
      ),
      'academics': ModulePermission(
        key: 'academics',
        label: 'Académique',
        group: 'academique',
        level: academics,
        scoped: false,
      ),
    },
  );
}

Future<_Transport> _monter(WidgetTester tester, {ModulePermissions? droits}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(droits ?? _droits()),
      ],
      child: const MaterialApp(home: Scaffold(body: AcademicImportsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

void main() {
  testWidgets('l_écran s_affiche', (tester) async {
    await _monter(tester);

    expect(find.textContaining('Erreur'), findsNothing);
  });

  testWidgets('les trois référentiels sont demandés', (tester) async {
    final transport = await _monter(tester);

    for (final route in ['/classrooms', '/academic-years', '/exam-sessions']) {
      expect(
        transport.chemins.where((chemin) => chemin.contains(route)),
        isNotEmpty,
        reason: '$route aurait dû être demandée',
      );
    }
  });

  testWidgets('la classe et l_année arrivées sont retenues', (tester) async {
    // Sans cette sélection, le formulaire d'import s'ouvre vide et refuse
    // l'envoi sans dire pourquoi.
    await _monter(tester);

    expect(find.textContaining('6ème A'), findsWidgets);
  });
}
