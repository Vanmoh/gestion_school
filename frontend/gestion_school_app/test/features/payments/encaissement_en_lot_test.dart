/// Un seul versement qui règle plusieurs frais.
///
/// L'écran créait les paiements un par un. Hors espèces — quatre méthodes sur
/// six — le serveur refusait dès le deuxième frais : la référence du transfert
/// qui réglait l'ensemble était tenue pour un doublon. Et quand un refus
/// tombait au milieu, les paiements déjà passés restaient en base sans que
/// rien ne dise lesquels.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/payments/data/payments_repository.dart';

class _Transport implements HttpClientAdapter {
  _Transport({this.echoue = false});

  final bool echoue;
  final List<RequestOptions> envoyees = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    envoyees.add(options);
    if (echoue) {
      return ResponseBody.fromString(
        jsonEncode(const {'frais': 'Frais introuvable: 99.'}),
        400,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(const {'crees': 3, 'total': '75000.00', 'paiements': []}),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(PaymentsRepository, _Transport) _depot({bool echoue = false}) {
  final transport = _Transport(echoue: echoue);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;
  return (PaymentsRepository(dio), transport);
}

void main() {
  test('le lot part en une seule requête', () async {
    // C'est tout l'enjeu : trente frais faisaient trente allers-retours, et
    // chacun pouvait échouer seul.
    final (repo, transport) = _depot();

    await repo.encaisserEnLot(
      feeIds: const [11, 12, 13],
      method: 'Mobile Money',
      reference: 'MM7788',
    );

    expect(transport.envoyees, hasLength(1));
    final envoi = transport.envoyees.single;
    expect(envoi.method, 'POST');
    expect(envoi.path, contains('/payments/encaisser-en-lot/'));
    expect(envoi.data['frais'], const [11, 12, 13]);
    expect(envoi.data['method'], 'Mobile Money');
    expect(envoi.data['reference'], 'MM7788');
  });

  test('sans montant imposé, le serveur solde chaque frais', () async {
    // Le champ absent, et non zéro : zéro voudrait dire « n'encaisse rien ».
    final (repo, transport) = _depot();

    await repo.encaisserEnLot(feeIds: const [11], method: 'Especes');

    expect(transport.envoyees.single.data.containsKey('montant_par_frais'), isFalse);
  });

  test('un montant imposé accompagne la demande', () async {
    final (repo, transport) = _depot();

    await repo.encaisserEnLot(
      feeIds: const [11, 12],
      method: 'Especes',
      montantParFrais: 25000,
    );

    expect(transport.envoyees.single.data['montant_par_frais'], 25000);
  });

  test('le compte rendu dit ce qui est entré', () async {
    // Le caissier doit pouvoir rapprocher l'écriture du versement reçu.
    final (repo, _) = _depot();

    final compteRendu = await repo.encaisserEnLot(
      feeIds: const [11, 12, 13],
      method: 'Virement',
      reference: 'VIR2026',
    );

    expect(compteRendu['crees'], 3);
    expect(compteRendu['total'], '75000.00');
  });

  test('un refus remonte au lieu d_être avalé', () async {
    // Le lot est annulé en entier côté serveur : l'appelant doit le savoir
    // pour le dire, plutôt que de laisser croire à un encaissement partiel.
    final (repo, _) = _depot(echoue: true);

    expect(
      () => repo.encaisserEnLot(feeIds: const [99], method: 'Especes'),
      throwsA(isA<DioException>()),
    );
  });
}
