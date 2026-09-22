/// Le mot de passe remis à l'inscription est provisoire.
///
/// Il est écrit sur un papier et suit une règle que l'école applique à tous,
/// et l'identifiant est le matricule — imprimé sur la carte scolaire. Ce qui
/// le rend sans danger n'est pas le secret du modèle, c'est qu'il cesse de
/// servir à la première connexion. Cet écran est la seule porte ouverte tant
/// qu'il n'est pas remplacé.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/features/auth/presentation/changer_mot_de_passe_page.dart';

class _Transport implements HttpClientAdapter {
  final List<RequestOptions> appels = [];
  bool refuse = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    appels.add(options);

    if (options.path.contains('changer-mot-de-passe') && refuse) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 400,
          data: {
            'nouveau_mot_de_passe': [
              'Choisissez un mot de passe différent de celui qui vous a été remis.',
            ],
          },
        ),
      );
    }

    if (options.path.contains('users/me')) {
      return _json(const {
        'id': 7,
        'username': 'EFAM6A25E0001M',
        'first_name': 'Amadou',
        'last_name': 'Diarra',
        'role': 'student',
        'etablissement': 1,
        'etablissement_name': 'Ecole',
        'doit_changer_mot_de_passe': false,
      });
    }

    return _json(const {'detail': 'ok'});
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

Future<_Transport> _monter(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: ChangerMotDePassePage()),
    ),
  );
  await tester.pumpAndSettle();
  return transport;
}

void main() {
  testWidgets('l_ecran dit pourquoi il s_impose', (tester) async {
    await _monter(tester);

    expect(find.text('Choisissez votre mot de passe'), findsOneWidget);
    expect(find.textContaining('provisoire'), findsOneWidget);
  });

  testWidgets('deux saisies differentes ne partent pas au serveur', (
    tester,
  ) async {
    final transport = await _monter(tester);

    await tester.enterText(find.byKey(const Key('nouveau-mot-de-passe')), 'MonChoix2026');
    await tester.enterText(
      find.byKey(const Key('confirmation-mot-de-passe')),
      'AutreChose2026',
    );
    await tester.tap(find.byKey(const Key('valider-mot-de-passe')));
    await tester.pumpAndSettle();

    expect(find.textContaining('ne correspondent pas'), findsOneWidget);
    expect(transport.appels, isEmpty);
  });

  testWidgets('un mot de passe trop court est arrete avant l_appel', (
    tester,
  ) async {
    final transport = await _monter(tester);

    await tester.enterText(find.byKey(const Key('nouveau-mot-de-passe')), 'court');
    await tester.enterText(find.byKey(const Key('confirmation-mot-de-passe')), 'court');
    await tester.tap(find.byKey(const Key('valider-mot-de-passe')));
    await tester.pumpAndSettle();

    expect(find.textContaining('8 caractères'), findsWidgets);
    expect(transport.appels, isEmpty);
  });

  testWidgets('la saisie valide part au serveur', (tester) async {
    final transport = await _monter(tester);

    await tester.enterText(find.byKey(const Key('nouveau-mot-de-passe')), 'MonChoix2026');
    await tester.enterText(
      find.byKey(const Key('confirmation-mot-de-passe')),
      'MonChoix2026',
    );
    await tester.tap(find.byKey(const Key('valider-mot-de-passe')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final envoi = transport.appels.first;
    expect(envoi.path, '/auth/changer-mot-de-passe/');
    expect(envoi.data['nouveau_mot_de_passe'], 'MonChoix2026');
    // L'ancien n'est pas redemandé: il vient d'être saisi pour arriver ici.
    expect(envoi.data.containsKey('ancien_mot_de_passe'), isFalse);
  });

  testWidgets('un refus du serveur reste a l_ecran', (tester) async {
    final transport = await _monter(tester);
    transport.refuse = true;

    await tester.enterText(find.byKey(const Key('nouveau-mot-de-passe')), 'MonChoix2026');
    await tester.enterText(
      find.byKey(const Key('confirmation-mot-de-passe')),
      'MonChoix2026',
    );
    await tester.tap(find.byKey(const Key('valider-mot-de-passe')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('valider-mot-de-passe')), findsOneWidget);
  });
}
