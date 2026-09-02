/// Un chargement qui survit au refus d'une de ses sources.
///
/// Cinq écrans réclamaient plus que ce que le profil qui les ouvre a le droit
/// de lire — la liste des enseignants, l'année scolaire, les encaissements —
/// et un seul refus faisait tomber le groupe entier. L'enseignant ne pouvait
/// plus pointer, la famille plus ouvrir la cantine, le censeur plus consulter
/// les rapports.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/chargement_tolerant.dart';

DioException _refus(int code) => DioException(
  requestOptions: RequestOptions(path: '/teachers/'),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/teachers/'),
    statusCode: code,
  ),
);

void main() {
  group('tolerantAuRefus', () {
    test('une source ouverte passe telle quelle', () async {
      final valeur = await tolerantAuRefus(Future.value([1, 2, 3]), const []);

      expect(valeur, [1, 2, 3]);
    });

    test('un refus de droits rend le repli', () async {
      final valeur = await tolerantAuRefus(
        Future<List<int>>.error(_refus(403)),
        const <int>[],
      );

      expect(valeur, isEmpty);
    });

    test('une session expirée rend le repli aussi', () async {
      final valeur = await tolerantAuRefus(
        Future<List<int>>.error(_refus(401)),
        const <int>[],
      );

      expect(valeur, isEmpty);
    });

    test('une panne du serveur continue de remonter', () async {
      // Taire un 500 le rendrait introuvable: ce n'est pas une situation
      // normale, c'est un incident.
      expect(
        tolerantAuRefus(Future<List<int>>.error(_refus(500)), const <int>[]),
        throwsA(isA<DioException>()),
      );
    });

    test('une coupure réseau remonte également', () async {
      expect(
        tolerantAuRefus(
          Future<List<int>>.error(
            DioException(
              requestOptions: RequestOptions(path: '/teachers/'),
              type: DioExceptionType.connectionError,
            ),
          ),
          const <int>[],
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('reponseTolerante', () {
    test('une réponse servie passe telle quelle', () async {
      final options = RequestOptions(path: '/students/');
      final reponse = await reponseTolerante(
        Future.value(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: const {'results': [1]},
          ),
        ),
      );

      expect(reponse.statusCode, 200);
      expect(reponse.data, const {'results': [1]});
    });

    test('un refus rend une charge vide, pas une exception', () async {
      // L'appelant continue de lire `results[n].data` sans se demander, à
      // chaque accès, si la source lui était ouverte.
      final reponse = await reponseTolerante(
        Future<Response<dynamic>>.error(_refus(403)),
      );

      expect(reponse.statusCode, 403);
      expect(reponse.data, isEmpty);
    });

    test('le repli se choisit quand la forme attendue diffère', () async {
      final reponse = await reponseTolerante(
        Future<Response<dynamic>>.error(_refus(403)),
        donneesDeRepli: const {'results': <dynamic>[]},
      );

      expect(reponse.data, const {'results': <dynamic>[]});
    });

    test('une panne du serveur remonte', () async {
      expect(
        reponseTolerante(Future<Response<dynamic>>.error(_refus(502))),
        throwsA(isA<DioException>()),
      );
    });
  });
}
