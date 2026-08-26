/// Le socle academique et ses droits d'ecriture.
///
/// L'ecran ne lisait aucun droit: la matrice met le promoteur et
/// l'enseignant en lecture seule sur l'academique, et tous deux recevaient
/// les boutons « Creer annee », « Creer matiere » et « Creer classe », pour
/// se faire refuser au clic.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/academics/presentation/academics_page.dart';

class _Transport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/academic-years/')) {
      return _json({
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

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'academics': ModulePermission(
        key: 'academics',
        label: 'Academique',
        group: 'academique',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<void> _monter(WidgetTester tester, AccessLevel niveau) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _Transport();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
      ],
      child: const MaterialApp(home: Scaffold(body: AcademicsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('un profil en lecture seule n_obtient aucune creation', (
    tester,
  ) async {
    await _monter(tester, AccessLevel.read);

    expect(find.byKey(const Key('creer-annee')), findsNothing);
    expect(find.byKey(const Key('creer-matiere')), findsNothing);
    expect(find.byKey(const Key('creer-classe')), findsNothing);
    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsOneWidget,
    );
  });

  testWidgets('la direction dispose des trois creations', (tester) async {
    await _monter(tester, AccessLevel.admin);

    expect(find.byKey(const Key('creer-annee')), findsOneWidget);
    expect(find.byKey(const Key('creer-matiere')), findsOneWidget);
    expect(find.byKey(const Key('creer-classe')), findsOneWidget);
    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsNothing,
    );
  });

  testWidgets('actualiser reste offert a tous', (tester) async {
    // Recharger n'est pas ecrire: le retirer aurait laisse les profils en
    // consultation devant une page qu'ils ne peuvent pas rafraichir.
    await _monter(tester, AccessLevel.read);

    final bouton = find.ancestor(
      of: find.text('Actualiser'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(bouton, findsWidgets);
    expect((tester.widget(bouton.first) as ButtonStyleButton).onPressed, isNotNull);
  });
}
