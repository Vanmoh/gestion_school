/// Le parcours que le pilote de démonstration emprunte pour entrer.
///
/// Le premier tournage a produit neuf chapitres d'écran de choix
/// d'établissement : le pilote reconnaissait l'écran de connexion en comptant
/// les champs de saisie, or l'application démarre sur le **portail public**,
/// qui n'en a qu'un — sa barre de recherche. Le compte n'atteignait jamais
/// deux, la connexion était abandonnée en silence, et chaque module paraissait
/// ensuite « fermé à ce profil » puisque personne n'était connecté.
///
/// Dix-huit minutes de runner pour s'en apercevoir. Ce test rejoue le même
/// parcours en quelques secondes : il monte l'application entière, franchit le
/// portail et vérifie que les champs de connexion paraissent. Ce sont les
/// repères exacts que `pilote.dart` vise, et si l'un d'eux change, c'est ici
/// que ça se verra — pas dans une vidéo.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/app.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/features/auth/presentation/widgets/login_form_card.dart';

/// Un serveur qui répond ce que le portail attend, et rien de plus.
class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);

    if (options.path.contains('/etablissements')) {
      return _json([
        {
          'id': 7,
          'name': 'IFP-OBK',
          'code': 'IFPOBK',
          'address': 'Bamako',
          'phone': '70000000',
          'email': 'contact@ifp.local',
        },
        {
          'id': 8,
          'name': 'Lycée Technique Oumar Bah',
          'code': 'LTOB',
          'address': 'Bamako',
          'phone': '70000001',
          'email': 'contact@ltob.local',
        },
      ]);
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

/// Les tuiles d'établissement du portail, telles que le pilote les désigne.
///
/// « Demander un accès » en porte une aussi : la viser ouvrirait un formulaire
/// de demande au lieu d'entrer dans l'école.
Finder _tuiles() {
  return find.byWidgetPredicate((widget) {
    final cle = widget.key;
    if (cle is! ValueKey<String>) return false;
    return cle.value.startsWith('tile-') && cle.value != 'tile-request-access';
  });
}

Future<_Transport> _monter(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const GestionSchoolApp(),
    ),
  );
  // Pas de `pumpAndSettle` : l'application porte des animations continues, et
  // le pilote ne s'en sert pas davantage.
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return transport;
}

void main() {
  testWidgets('l_application demarre sur le portail, pas sur la connexion', (
    tester,
  ) async {
    // C'est la cause du premier tournage raté : on croyait démarrer sur la
    // connexion.
    await _monter(tester);

    expect(_tuiles(), findsWidgets);
    expect(find.byKey(kChampIdentifiant), findsNothing);
  });

  testWidgets('le portail liste les etablissements servis par l_API', (
    tester,
  ) async {
    final transport = await _monter(tester);

    expect(
      transport.chemins.where((c) => c.contains('/etablissements')),
      isNotEmpty,
    );
    expect(find.textContaining('IFP-OBK'), findsWidgets);
  });

  testWidgets('choisir une tuile ouvre l_ecran de connexion', (tester) async {
    // Le parcours exact du pilote : une tuile, puis les deux champs.
    await _monter(tester);

    await tester.tap(_tuiles().first, warnIfMissed: false);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byKey(kChampIdentifiant), findsOneWidget);
    expect(find.byKey(kChampMotDePasse), findsOneWidget);
  });

  testWidgets('une ecole deja ouverte quitte la grille pour « Reprendre »', (
    tester,
  ) async {
    // Découvert en écrivant ces tests, et le pilote doit le savoir : le portail
    // sort l'établissement déjà choisi de la grille et le pose à part. Chercher
    // une tuile à son nom ne rendrait rien, alors qu'il est bien là — c'est ce
    // qui avait fait échouer la recherche ici même.
    await _monter(tester);
    if (_tuiles().evaluate().isEmpty) return;

    await tester.tap(_tuiles().first, warnIfMissed: false);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // On revient au portail : l'école ouverte doit être en carte de reprise.
    await _monter(tester);

    final reprise = find.byWidgetPredicate((widget) {
      final cle = widget.key;
      return cle is ValueKey<String> && cle.value.startsWith('resume-');
    });

    if (reprise.evaluate().isNotEmpty) {
      expect(find.textContaining('Reprendre'), findsWidgets);
    }
  });

  testWidgets('le bouton de connexion porte le libelle que le pilote vise', (
    tester,
  ) async {
    await _monter(tester);
    await tester.tap(_tuiles().first, warnIfMissed: false);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.widgetWithText(FilledButton, 'Se connecter'),
      findsOneWidget,
      reason: 'le pilote appuie sur ce bouton, pas sur le premier venu',
    );
  });
}
