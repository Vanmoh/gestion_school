import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/features/auth/presentation/login_page.dart';

/// Un etablissement au nom long, comme celui qui a fait apparaitre le
/// debordement en conditions reelles.
const _etablissementJson = {
  'id': 4,
  'name': 'Complexe Scolaire Omar Bah (CSOB)',
  'address': 'LTOB (1er etage)',
  'phone': '78 32 59 13 / 66 74 22 32',
};

/// Le nom tel que le titre l'affiche: le sigle est passe en sous-titre.
const _titreAffiche = 'Complexe Scolaire Omar Bah';

/// Un transport muet.
///
/// L'ecran demande la personnalisation de l'ecole a son ouverture; sans cet
/// adaptateur, le test emettrait une vraie requete et attendrait le delai de
/// connexion de Dio.
class _TransportMuet implements HttpClientAdapter {
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

Future<void> _pumpLoginPage(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _TransportMuet();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: LoginPage()),
    ),
  );
  // hydrate() lit le stockage securise de facon asynchrone.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    // Le cache memoire de TokenStorage est statique: sans cette purge, le
    // premier etablissement lu vaudrait pour tous les cas du fichier.
    TokenStorage.purgerCacheMemoire();
    FlutterSecureStorage.setMockInitialValues({
      'selected_etablissement': jsonEncode(_etablissementJson),
    });
  });

  testWidgets('ne deborde pas sur une fenetre courte en mode deux colonnes', (
    tester,
  ) async {
    // 1052x600: la taille exacte qui produisait
    // "A RenderFlex overflowed by 24 pixels on the bottom".
    await _pumpLoginPage(tester, const Size(1052, 600));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ne deborde pas sur une fenetre haute', (tester) async {
    await _pumpLoginPage(tester, const Size(1440, 900));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ne deborde pas en colonne unique etroite', (tester) async {
    await _pumpLoginPage(tester, const Size(600, 520));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ne deborde pas sur un telephone', (tester) async {
    await _pumpLoginPage(tester, const Size(360, 640));

    expect(tester.takeException(), isNull);
  });

  group('l_ecole reste nommee a toutes les largeurs', () {
    // C'est le defaut que cette refonte corrige: sous 980 px, la colonne de
    // marque disparaissait entierement et il ne restait qu'une carte nue.
    // L'ecran que voient la plupart des parents ne portait donc plus le nom
    // de leur ecole.
    for (final taille in const [
      Size(1440, 900),
      Size(1052, 600),
      Size(600, 520),
      Size(360, 640),
    ]) {
      testWidgets('${taille.width.toInt()}x${taille.height.toInt()}', (
        tester,
      ) async {
        await _pumpLoginPage(tester, taille);

        expect(find.text(_titreAffiche), findsWidgets);
      });
    }
  });
}
