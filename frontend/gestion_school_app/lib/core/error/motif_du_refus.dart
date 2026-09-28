/// Le motif d'un refus, tel que le serveur le formule.
///
/// Le backend explique précisément ce qui ne va pas : « L'épreuve doit tomber
/// dans la session « Composition du premier trimestre », du 1er au 6
/// décembre », « 6ème A compose déjà « Mathématiques » ce jour-là de 08:00 à
/// 10:00 », « Accès refusé : export sensible réservé à l'administration ».
/// Ces phrases sont écrites pour être lues par qui travaille dans l'école.
///
/// Les écrans les remplaçaient par « Épreuve refusée », « Création refusée »,
/// « Opération impossible » — ou pire, par `erreur.toString()`, qui rend le
/// texte de `DioException` : « DioException [bad response]: This exception was
/// thrown because the response has a status code of 400 ». L'utilisateur voyait
/// donc un message d'erreur sans savoir ce qu'on lui reprochait, alors que le
/// serveur venait de le lui dire.
///
/// Cette fonction vivait en double, recopiée dans `personnalisation_page` et
/// `timetable_page`. Elle est ici une fois, et les deux l'appellent.
library;

import 'package:dio/dio.dart';

/// Rend la phrase du serveur, ou [parDefaut] si l'on n'en trouve aucune.
///
/// Les formes gérées sont celles que DRF produit :
///
/// - `{"detail": "Accès refusé."}` — les permissions et les `APIException` ;
/// - `{"start_time": ["6ème A compose déjà…"]}` — les erreurs de validation,
///   champ par champ ;
/// - `{"non_field_errors": ["…"]}` — les règles qui ne portent sur aucun champ ;
/// - une liste, ou une chaîne brute.
String motifDuRefus(Object? erreur, {String parDefaut = 'Opération refusée.'}) {
  final donnees = erreur is DioException ? erreur.response?.data : erreur;

  final phrase = _phraseDe(donnees);
  if (phrase != null && phrase.trim().isNotEmpty) return phrase.trim();

  // Un refus sans corps: on dit au moins ce que le code veut dire, plutôt que
  // de rendre la trace technique de Dio.
  if (erreur is DioException) {
    final code = erreur.response?.statusCode;
    if (code != null) return _selonLeCode(code, parDefaut);
    if (erreur.type == DioExceptionType.connectionTimeout ||
        erreur.type == DioExceptionType.connectionError) {
      return 'Le serveur ne répond pas.';
    }
  }
  return parDefaut;
}

String? _phraseDe(Object? donnees) {
  if (donnees == null) return null;

  if (donnees is String) {
    // Une page d'erreur HTML n'est pas un motif: la rendre telle quelle
    // inonderait l'écran de balises.
    final texte = donnees.trim();
    if (texte.startsWith('<')) return null;
    return texte.isEmpty ? null : texte;
  }

  if (donnees is List) {
    for (final element in donnees) {
      final phrase = _phraseDe(element);
      if (phrase != null) return phrase;
    }
    return null;
  }

  if (donnees is Map) {
    // `detail` d'abord: c'est la forme des refus de permission et des
    // exceptions applicatives, et la plus explicite.
    for (final cle in const ['detail', 'message', 'erreur', 'non_field_errors']) {
      final phrase = _phraseDe(donnees[cle]);
      if (phrase != null) return phrase;
    }
    for (final valeur in donnees.values) {
      final phrase = _phraseDe(valeur);
      if (phrase != null) return phrase;
    }
  }

  return null;
}

/// Ce qu'un code de réponse veut dire, quand le corps ne dit rien.
String _selonLeCode(int code, String parDefaut) {
  switch (code) {
    case 401:
      return 'Session expirée : reconnectez-vous.';
    case 403:
      return 'Votre profil n\'a pas le droit de faire cela.';
    case 404:
      return 'Cet élément n\'existe plus.';
    case 409:
      return 'Opération impossible en l\'état.';
    case 413:
      return 'Le fichier est trop lourd.';
    case 500:
    case 502:
    case 503:
      return 'Le serveur a rencontré une erreur.';
    default:
      return parDefaut;
  }
}
