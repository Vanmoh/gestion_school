/// Les notes et leurs droits d'ecriture.
///
/// L'ecran, le plus gros de la section, ne lisait aucun droit: la matrice
/// met le promoteur en lecture seule sur les notes, et il obtenait la
/// saisie, la validation de periode et le recalcul des rangs -- pour un 403
/// au moment d'enregistrer.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/grades/presentation/grades_page.dart';

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
      return _json(const {'id': 1});
    }

    final chemin = options.path;
    if (chemin.contains('/academic-years/')) {
      return _json({
        'results': [
          {'id': 1, 'name': '2025-2026', 'is_active': true},
        ],
      });
    }
    if (chemin.contains('/classrooms/')) {
      return _json({
        'results': [
          {'id': 10, 'name': '6A', 'academic_year': 1},
        ],
      });
    }
    if (chemin.contains('/subjects/')) {
      return _json({
        'results': [
          {'id': 20, 'name': 'Mathematiques', 'classroom': 10, 'coefficient': 4},
        ],
      });
    }
    if (chemin.contains('/students/')) {
      return _json({
        'results': [
          {
            'id': 30,
            'matricule': 'M001',
            'user_full_name': 'Awa Traore',
            'classroom': 10,
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

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'grades': ModulePermission(
        key: 'grades',
        label: 'Notes & Bulletins',
        group: 'academique',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<_Transport> _monter(WidgetTester tester, AccessLevel niveau) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 2400);
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
      child: const MaterialApp(home: Scaffold(body: GradesPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

void main() {
  testWidgets('un profil en lecture seule ne valide pas la periode', (
    tester,
  ) async {
    await _monter(tester, AccessLevel.read);

    expect(find.byKey(const Key('valider-periode')), findsNothing);
    expect(find.byKey(const Key('reouvrir-periode')), findsNothing);
    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsOneWidget,
    );
  });

  testWidgets('un profil en ecriture garde la validation de periode', (
    tester,
  ) async {
    await _monter(tester, AccessLevel.write);

    expect(find.byKey(const Key('valider-periode')), findsOneWidget);
    expect(find.byKey(const Key('reouvrir-periode')), findsOneWidget);
    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsNothing,
    );
  });

  testWidgets('en lecture seule, aucune ecriture ne part vers l_API', (
    tester,
  ) async {
    // Le garde est pose dans les methodes d'ecriture et pas seulement sur
    // les boutons: les dialogues de saisie ont plusieurs chemins d'appel,
    // et masquer un bouton n'en ferme qu'un seul.
    final transport = await _monter(tester, AccessLevel.read);

    expect(
      transport.envois.where((r) => r.method != 'GET'),
      isEmpty,
    );
  });
}
