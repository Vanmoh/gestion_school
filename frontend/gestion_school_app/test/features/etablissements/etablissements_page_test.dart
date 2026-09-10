/// L'écran des établissements, et les réglages qui changent des chiffres.
///
/// Neuf cents lignes pilotant le coefficient de conduite — qui entre dans la
/// moyenne de chaque bulletin et dans le classement de chaque classe — sans
/// aucun test. Le champ était par ailleurs noyé entre « Échelle cachet % » et
/// les libellés de signature, au milieu d'une trentaine de champs de mise en
/// page.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/features/etablissements/presentation/etablissements_page.dart';

class _Transport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/etablissements/')) {
      return _json(const {
        'results': [
          {
            'id': 1,
            'name': 'Lycee Test',
            'code': 'LT',
            'address': 'Bamako',
            'phone': '76000000',
            'email': 'contact@lycee.ml',
            'conduite_coefficient': '2.00',
            'library_penalty_per_day': '0.00',
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

Future<void> _monter(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _Transport();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: Scaffold(body: EtablissementsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('l_écran se monte et charge les établissements', (tester) async {
    await _monter(tester);

    expect(find.byType(EtablissementsPage), findsOneWidget);
  });

  group('les règles de calcul', () {
    testWidgets('elles ont leur propre section, annoncée comme telle', (
      tester,
    ) async {
      await _monter(tester);

      expect(find.text('Règles de calcul'), findsOneWidget);
      expect(
        find.textContaining('changent des chiffres déjà imprimés'),
        findsOneWidget,
      );
    });

    testWidgets('le coefficient de conduite dit sur quoi il pèse', (
      tester,
    ) async {
      // Un réglage qui déplace toutes les moyennes ne peut pas se présenter
      // comme une taille d'image.
      await _monter(tester);

      expect(find.text('Coefficient de conduite'), findsOneWidget);
      expect(
        find.textContaining('Pèse dans chaque bulletin et dans le classement'),
        findsOneWidget,
      );
    });

    testWidgets('la pénalité de bibliothèque reste distincte', (tester) async {
      await _monter(tester);

      expect(find.text('Pénalité de retard / jour'), findsOneWidget);
      expect(find.textContaining('Emprunts de la bibliothèque'), findsOneWidget);
    });

    testWidgets('le formulaire vierge propose le défaut du serveur', (
      tester,
    ) async {
      // Le formulaire ne se remplit qu'une fois un établissement choisi; à
      // vide il doit proposer 2, la valeur que le modèle applique aussi. Un
      // défaut divergent ferait basculer les moyennes au premier
      // enregistrement d'un formulaire qu'on croyait n'avoir pas touché.
      await _monter(tester);

      final champ = tester.widget<TextField>(
        find.ancestor(
          of: find.text('Coefficient de conduite'),
          matching: find.byType(TextField),
        ),
      );
      expect(champ.controller?.text, '2');
    });
  });
}
