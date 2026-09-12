/// Les totaux de la période, tels que l'écran les lit.
///
/// Ils étaient additionnés sur place, à partir des lignes chargées. Le
/// journal des encaissements étant paginé par vingt-cinq, « Montant
/// encaissé » décrivait la page et non la période : au-delà de vingt-cinq
/// versements dans le mois, le chiffre était faux et il changeait en
/// tournant la page.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/payments/data/payments_repository.dart';
import 'package:gestion_school_app/features/payments/domain/finance_totals.dart';

class _Transport implements HttpClientAdapter {
  _Transport(this.charge);

  final Map<String, dynamic> charge;
  final List<RequestOptions> envoyees = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    envoyees.add(options);
    return ResponseBody.fromString(
      jsonEncode(charge),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(PaymentsRepository, _Transport) _depot(Map<String, dynamic> charge) {
  final transport = _Transport(charge);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;
  return (PaymentsRepository(dio), transport);
}

const _chargeComplete = {
  'periode': 'mois',
  'recettes': '1250000.00',
  'encaissements': 87,
  'recettes_par_methode': {'Especes': '900000.00', 'Mobile Money': '350000.00'},
  'depenses_validees': '400000.00',
  'depenses_en_attente': '75000.00',
  'resultat': '850000.00',
};

void main() {
  test('la période demandée accompagne la requête', () async {
    final (repo, transport) = _depot(_chargeComplete);

    await repo.totauxDeLaPeriode('semaine');

    final envoi = transport.envoyees.single;
    expect(envoi.path, contains('/payments/totaux/'));
    expect(envoi.queryParameters['periode'], 'semaine');
  });

  test('les montants arrivent en nombres, pas en chaînes', () async {
    // Le serveur les sérialise en décimal pour ne rien perdre en route; le
    // client doit les rendre comparables.
    final (repo, _) = _depot(_chargeComplete);

    final totaux = await repo.totauxDeLaPeriode('mois');

    expect(totaux.recettes, 1250000.0);
    expect(totaux.encaissements, 87);
    expect(totaux.depensesValidees, 400000.0);
    expect(totaux.depensesEnAttente, 75000.0);
    expect(totaux.resultat, 850000.0);
  });

  test('la ventilation par méthode est conservée', () async {
    // C'est elle qui permet de rapprocher la caisse du relevé Mobile Money.
    final (repo, _) = _depot(_chargeComplete);

    final totaux = await repo.totauxDeLaPeriode('jour');

    expect(totaux.parMethode['Especes'], 900000.0);
    expect(totaux.parMethode['Mobile Money'], 350000.0);
  });

  test('une famille reçoit ses recettes sans les dépenses', () async {
    // La matrice lui donne « finance » en portée restreinte: elle voit ses
    // propres versements, jamais les dépenses de l'école. Les champs absents
    // doivent rester nuls, et non tomber à zéro — un zéro se lirait comme
    // « aucune dépense ».
    final (repo, _) = _depot(const {
      'periode': 'mois',
      'recettes': '45000.00',
      'encaissements': 3,
      'recettes_par_methode': {'Especes': '45000.00'},
    });

    final totaux = await repo.totauxDeLaPeriode('mois');

    expect(totaux.recettes, 45000.0);
    expect(totaux.depensesValidees, isNull);
    expect(totaux.resultat, isNull);
  });

  test('une réponse vide ne fait pas tomber l_écran', () async {
    final (repo, _) = _depot(const {});

    final totaux = await repo.totauxDeLaPeriode('tout');

    expect(totaux.recettes, 0);
    expect(totaux.encaissements, 0);
    expect(totaux.parMethode, isEmpty);
    expect(totaux.resultat, isNull);
  });

  test('un résultat négatif reste négatif', () async {
    // Le déficit est précisément le chiffre qui appelle une réaction.
    final (repo, _) = _depot(const {
      'recettes': '100000.00',
      'encaissements': 4,
      'depenses_validees': '160000.00',
      'depenses_en_attente': '0.00',
      'resultat': '-60000.00',
    });

    final totaux = await repo.totauxDeLaPeriode('mois');

    expect(totaux.resultat, -60000.0);
  });
}
