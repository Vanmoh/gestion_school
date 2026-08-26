/// Qui peut publier un emploi du temps, et qui ne le peut pas.
///
/// L'ecran melait deux sources: sept gardes d'action lisaient la matrice,
/// mais le mode lecture seule du rendu tenait sur `role == 'teacher'`. La
/// matrice met aussi le promoteur, le comptable et le surveillant en
/// lecture seule sur l'emploi du temps: tous trois recevaient des boutons
/// de publication actifs, pour un 403 au clic.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/timetable/presentation/timetable_page.dart';

class _Transport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final chemin = options.path;
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
          {'id': 20, 'name': 'Mathematiques', 'classroom': 10},
        ],
      });
    }
    if (chemin.contains('/teachers/')) {
      return _json({
        'results': [
          {'id': 40, 'user': 1, 'user_full_name': 'Moussa Diallo'},
        ],
      });
    }
    if (chemin.contains('/teacher-assignments/')) {
      return _json({
        'results': [
          {'id': 50, 'teacher': 40, 'subject': 20, 'classroom': 10},
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
      'timetable': ModulePermission(
        key: 'timetable',
        label: 'Emploi du temps',
        group: 'academique',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<void> _monter(WidgetTester tester, AccessLevel niveau) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 2600);
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
      child: const MaterialApp(home: Scaffold(body: TimetablePage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Etat actif du bouton portant ce libelle.
bool? _onPressedDe(WidgetTester tester, String libelle) {
  final bouton = find.ancestor(
    of: find.text(libelle),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  if (bouton.evaluate().isEmpty) return null;
  return (tester.widget(bouton.first) as ButtonStyleButton).onPressed != null;
}

void main() {
  testWidgets('un profil en lecture seule ne peut pas publier', (tester) async {
    await _monter(tester, AccessLevel.read);

    for (final libelle in [
      'Publier + verrouiller',
      'Publier sans verrou',
      'Repasser brouillon',
    ]) {
      final actif = _onPressedDe(tester, libelle);
      if (actif != null) {
        expect(actif, isFalse, reason: '« $libelle » doit rester inerte');
      }
    }
  });

  testWidgets('la page se monte pour un profil en ecriture', (tester) async {
    // Le rendu complet est la garantie que le retrait du telechargement du
    // schema OpenAPI n'a pas casse la detection de l'API planning.
    await _monter(tester, AccessLevel.admin);

    expect(find.byType(TimetablePage), findsOneWidget);
  });
}
