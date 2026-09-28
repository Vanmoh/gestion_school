/// Le motif d'un refus doit atteindre l'utilisateur.
///
/// Le serveur explique précisément ce qu'il reproche — « L'épreuve doit tomber
/// dans la session », « 6ème A compose déjà « Mathématiques » ce jour-là ». Les
/// écrans refondus remplaçaient ces phrases par « Épreuve refusée », « Création
/// refusée », « Opération impossible ». Pire, l'un d'eux rendait
/// `erreur.toString()` d'une `DioException` : « DioException [bad response]:
/// This exception was thrown because the response has a status code of 400 ».
///
/// Un utilisateur voyait donc une erreur sans savoir ce qu'on lui reprochait,
/// alors que la réponse venait de le lui dire. Ces tests tiennent le contraire.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/error/motif_du_refus.dart';

/// Un refus du serveur, tel que Dio le présente à l'écran.
DioException _refus(int code, Object? corps) {
  final requete = RequestOptions(path: '/exam-plannings/');
  return DioException(
    requestOptions: requete,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: requete,
      statusCode: code,
      data: corps,
    ),
  );
}

void main() {
  group('Ce que le serveur reproche', () {
    test('une erreur de validation par champ est rendue telle quelle', () {
      // Le cas signalé: créer une épreuve hors de sa campagne.
      final erreur = _refus(400, {
        'exam_date': [
          'L\'épreuve doit tomber dans la session « Examen Blanc T1 », '
              'du 2026-10-16 au 2026-10-19.',
        ],
      });

      expect(
        motifDuRefus(erreur),
        startsWith('L\'épreuve doit tomber dans la session'),
      );
    });

    test('un « detail » prime sur le reste', () {
      final erreur = _refus(403, {
        'detail': 'Accès refusé: export sensible réservé à l\'administration.',
        'autre': ['bruit'],
      });

      expect(motifDuRefus(erreur), contains('export sensible'));
    });

    test('une règle sans champ passe aussi', () {
      final erreur = _refus(400, {
        'non_field_errors': ['Cette épreuve existe déjà pour cet élève.'],
      });

      expect(motifDuRefus(erreur), 'Cette épreuve existe déjà pour cet élève.');
    });

    test('le premier champ en erreur suffit quand il n_y a pas de « detail »', () {
      final erreur = _refus(400, {
        'start_time': [
          '6ème A compose déjà « Mathématiques » ce jour-là de 08:00 à 10:00.',
        ],
      });

      expect(motifDuRefus(erreur), contains('compose déjà'));
    });

    test('une chaîne brute est rendue', () {
      expect(motifDuRefus(_refus(409, 'Suppression impossible.')),
          'Suppression impossible.');
    });

    test('une liste de messages rend le premier', () {
      expect(
        motifDuRefus(_refus(400, ['Champ manquant.', 'Autre chose.'])),
        'Champ manquant.',
      );
    });
  });

  group('Quand le serveur ne dit rien', () {
    test('le code est traduit plutôt que rendu brut', () {
      // Sans cela, l'écran affichait le texte de DioException, qui parle de
      // « status code » à quelqu'un qui saisit des notes.
      expect(motifDuRefus(_refus(403, null)), contains('droit'));
      expect(motifDuRefus(_refus(401, null)), contains('Session expirée'));
      expect(motifDuRefus(_refus(404, null)), contains('n\'existe plus'));
      expect(motifDuRefus(_refus(500, null)), contains('serveur'));
    });

    test('une page HTML n_est pas un motif', () {
      // Un proxy ou un serveur en panne renvoie du HTML: l'afficher
      // inonderait l'écran de balises.
      final erreur = _refus(502, '<html><body>Bad Gateway</body></html>');

      expect(motifDuRefus(erreur), isNot(contains('<')));
      expect(motifDuRefus(erreur), contains('serveur'));
    });

    test('un serveur injoignable se dit en français', () {
      final erreur = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );

      expect(motifDuRefus(erreur), 'Le serveur ne répond pas.');
    });

    test('une erreur qui n_est pas du réseau retombe sur le défaut', () {
      expect(
        motifDuRefus(Exception('quelque chose'), parDefaut: 'Refusé.'),
        'Refusé.',
      );
      expect(motifDuRefus(null, parDefaut: 'Refusé.'), 'Refusé.');
    });
  });

  group('Ce qu_on ne montre jamais', () {
    test('le texte technique de DioException ne fuit pas', () {
      // La régression exacte: `erreur.toString()` parlait de « status code ».
      for (final erreur in [
        _refus(400, null),
        _refus(400, {'champ': []}),
        _refus(400, ''),
      ]) {
        final motif = motifDuRefus(erreur);
        expect(motif, isNot(contains('DioException')));
        expect(motif, isNot(contains('status code')));
      }
    });

    test('un corps vide ne donne pas un message vide', () {
      expect(motifDuRefus(_refus(400, {})).trim(), isNotEmpty);
      expect(motifDuRefus(_refus(400, [])).trim(), isNotEmpty);
    });
  });
}
