// L'adresse de l'API ne doit plus etre figee a la compilation.
//
// Le build embarquait une adresse IP; a chaque changement de reseau elle
// devenait morte, et l'application cessait de joindre le serveur sans qu'aucun
// message ne dise pourquoi. Les ecrans deja charges continuaient d'afficher
// leurs donnees en memoire, si bien que la panne se manifestait seulement au
// prochain clic — ici, l'impression des cartes.

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/constants/api_constants.dart';

void main() {
  test('la racine de l_API se termine par /api', () {
    expect(ApiConstants.baseUrl, endsWith('/api'));
  });

  test('elle designe un hote joignable, jamais une chaine vide', () {
    final uri = Uri.parse(ApiConstants.baseUrl);

    expect(uri.scheme, anyOf('http', 'https'));
    expect(uri.host, isNotEmpty);
    expect(uri.hasPort, isTrue);
  });

  test('elle ne contient aucune adresse figee d_un ancien reseau', () {
    // Ces adresses ont ete compilees dans des builds successifs, puis sont
    // devenues injoignables. Aucune ne doit reapparaitre en dur.
    for (final morte in ['192.168.13.84', '192.168.1.29', 'IP_DU_PC']) {
      expect(
        ApiConstants.baseUrl,
        isNot(contains(morte)),
        reason: 'une adresse de reseau revolue est revenue dans le code',
      );
    }
  });
}
