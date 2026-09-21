/// Ce que l'écran dit avant d'engager le papier.
///
/// Imprimer les cartes d'une classe, c'est une planche qu'on découpe. On ne
/// s'apercevait qu'après coup que quarante cartes sur soixante portaient un
/// cadre « PHOTO » vide, ou que le QR renvoyait à une adresse du réseau local
/// — et ni l'un ni l'autre ne se rattrape sur du carton déjà coupé.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/features/student_lookup/presentation/widgets/carte_des_documents.dart';
import 'package:gestion_school_app/features/students/domain/student.dart';

class _Transport implements HttpClientAdapter {
  final int sansPhoto;
  final bool qrActif;

  /// Ce que l'écran a réellement demandé au serveur.
  final List<RequestOptions> appels = [];

  _Transport({this.sansPhoto = 0, this.qrActif = true});

  List<RequestOptions> get impressions =>
      appels.where((appel) => !appel.path.endsWith('/verification/')).toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    appels.add(options);

    if (options.path.endsWith('/verification/')) {
      return ResponseBody.fromString(
        jsonEncode({
          'classe': '6A',
          'effectif': 20,
          'sans_photo': sansPhoto,
          'noms_sans_photo': List.generate(
            sansPhoto > 12 ? 12 : sansPhoto,
            (index) => 'Élève ${index + 1}',
          ),
          'qr_actif': qrActif,
          'motif_qr': qrActif ? '' : 'Les cartes sortiront sans QR.',
          'cartes_par_planche': 8,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromBytes(
      [37, 80, 68, 70],
      200,
      headers: {
        Headers.contentTypeHeader: ['application/pdf'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final _eleve = Student.fromJson({
  'id': 3,
  'user': 30,
  'user_full_name': 'Aminata Coulibaly',
  'matricule': 'M003',
  'gender': 'F',
  'classroom': 7,
  'classroom_name': '6A',
  'birth_date': '2012-03-14',
  'is_archived': false,
});

Future<_Transport> _monter(
  WidgetTester tester, {
  int sansPhoto = 0,
  bool qrActif = true,
}) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(sansPhoto: sansPhoto, qrActif: qrActif);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CarteDesDocuments(student: _eleve),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return transport;
}

void main() {
  testWidgets('le format bancaire est propose par defaut et part au serveur', (
    tester,
  ) async {
    // L'A6 fait 148 x 105 mm: une demi-carte postale qu'aucun eleve ne garde.
    final transport = await _monter(tester);

    await tester.tap(find.byKey(const Key('dossier-carte-scolaire')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final carte = transport.impressions.single;
    expect(carte.path, '/reports/student-card/3/');
    expect(carte.queryParameters['card_format'], 'cr80');
    tester.takeException();
  });

  testWidgets('l_ecran annonce le nombre de planches avant l_impression', (
    tester,
  ) async {
    await _monter(tester);

    expect(
      find.textContaining('20 cartes, 3 planche(s) A4'),
      findsOneWidget,
    );
    expect(find.textContaining('8 par feuille, taille réelle'), findsOneWidget);
  });

  testWidgets('les eleves sans photo sont annonces, et l_impression attend', (
    tester,
  ) async {
    final transport = await _monter(tester, sansPhoto: 12);

    expect(find.textContaining('12 élève(s) sans photo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dossier-cartes-classe')));
    await tester.pumpAndSettle();

    expect(find.text('Avant d\'imprimer'), findsOneWidget);
    expect(
      find.textContaining('12 élève(s) sur 20 n\'ont pas de photo'),
      findsOneWidget,
    );

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    // Annuler veut dire annuler: aucune planche n'a ete demandee.
    expect(transport.impressions, isEmpty);
  });

  testWidgets('un QR mort est annonce avant d_etre grave sur le carton', (
    tester,
  ) async {
    await _monter(tester, qrActif: false);

    expect(find.textContaining('Sans QR de vérification'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dossier-cartes-classe')));
    await tester.pumpAndSettle();

    expect(find.text('Les cartes sortiront sans QR.'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
  });

  testWidgets('sans rien a signaler, on imprime sans etape de plus', (
    tester,
  ) async {
    final transport = await _monter(tester);

    await tester.tap(find.byKey(const Key('dossier-cartes-classe')));
    // La verification passe d'abord, l'apercu ensuite: deux tours de boucle
    // avant que la planche soit demandee.
    for (var tour = 0; tour < 4; tour++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Avant d\'imprimer'), findsNothing);
    final planche = transport.impressions.single;
    expect(planche.path, '/reports/student-cards/class/7/');
    expect(planche.queryParameters['layout_mode'], 'a4');
    expect(planche.queryParameters['card_format'], 'cr80');
    tester.takeException();
  });
}
