import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/models/etablissement.dart';

/// Le chargement de la liste des établissements.
///
/// Deux écrans le demandaient chacun de son côté, avec deux gestions
/// d'erreur qui ont fini par diverger: l'un affichait la raison de l'échec et
/// proposait de réessayer, l'autre l'avalait en silence et posait un verrou
/// qu'il ne relâchait jamais. Le même serveur momentanément absent laissait
/// donc un écran utilisable et figeait l'autre.
class _TransportFactice implements HttpClientAdapter {
  _TransportFactice(this.reponses);

  /// Ce que le serveur répond, appel après appel.
  final List<Object> reponses;
  int appels = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async {
    final reponse = reponses[appels.clamp(0, reponses.length - 1)];
    appels++;
    if (reponse is DioException) throw reponse;
    return ResponseBody.fromString(
      reponse as String,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _uneEcole = '[{"id": 1, "name": "LTOB"}]';

EtablissementProvider _provider(_TransportFactice transport) {
  FlutterSecureStorage.setMockInitialValues({});
  final dio = Dio(BaseOptions(baseUrl: 'http://test/api'))
    ..httpClientAdapter = transport;
  return EtablissementProvider(TokenStorage(), dio);
}

DioException _injoignable() => DioException(
  requestOptions: RequestOptions(path: '/etablissements/'),
  type: DioExceptionType.connectionError,
);

void main() {
  test('le chargement garnit la liste', () async {
    final provider = _provider(_TransportFactice([_uneEcole]));

    await provider.charger();

    expect(provider.etablissements.single.name, 'LTOB');
  });

  test('une liste deja garnie n_est pas rechargee', () async {
    final transport = _TransportFactice([_uneEcole]);
    final provider = _provider(transport);
    await provider.charger();

    await provider.charger();

    expect(transport.appels, 1);
  });

  test('« Reessayer » force un nouvel appel', () async {
    final transport = _TransportFactice([_uneEcole]);
    final provider = _provider(transport);
    await provider.charger();

    await provider.charger(forcer: true);

    expect(transport.appels, 2);
  });

  test('deux ecrans montes ensemble ne font qu_un appel', () async {
    final transport = _TransportFactice([_uneEcole]);
    final provider = _provider(transport);

    await Future.wait([provider.charger(), provider.charger()]);

    expect(transport.appels, 1);
    expect(provider.etablissements, hasLength(1));
  });

  test('un echec remonte au lieu d_etre avale', () async {
    final provider = _provider(_TransportFactice([_injoignable()]));

    await expectLater(provider.charger(), throwsA(isA<DioException>()));
  });

  test('un echec ne ferme pas la porte au suivant', () async {
    // C'est le coeur du defaut: le verrou etait pose avant la tentative et
    // jamais repris, si bien qu'un backend encore en train de demarrer
    // figeait l'ecran jusqu'au rechargement complet de la page.
    final transport = _TransportFactice([_injoignable(), _uneEcole]);
    final provider = _provider(transport);

    await provider.charger().catchError((_) {});
    await provider.charger();

    expect(transport.appels, 2);
    expect(provider.etablissements.single.name, 'LTOB');
  });
}
