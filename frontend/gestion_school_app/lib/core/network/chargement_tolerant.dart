import 'package:dio/dio.dart';

/// Un chargement qui survit au refus d'une de ses sources.
///
/// Les écrans demandent souvent plus que ce que le profil qui les ouvre a le
/// droit de lire : la liste des enseignants pour y retrouver son propre nom,
/// l'année scolaire pour dater un tableau, les paiements pour un encart de
/// synthèse. Ces sources sont annexes — l'écran a un sens sans elles.
///
/// Groupées dans un `Future.wait`, elles ne l'étaient pas : un seul refus
/// faisait tomber tout le groupe, et l'écran entier avec lui. L'enseignant
/// ouvrant son émargement, le parent ouvrant la cantine, le censeur ouvrant
/// les rapports voyaient « erreur de chargement » là où il ne leur manquait
/// qu'une donnée secondaire.
///
/// Seul le refus de droits est absorbé. Une panne de réseau, une erreur du
/// serveur, une route absente continuent de remonter : ce sont des incidents,
/// pas des situations normales, et les taire les rendrait introuvables.
Future<T> tolerantAuRefus<T>(Future<T> appel, T repli) async {
  try {
    return await appel;
  } on DioException catch (erreur) {
    final code = erreur.response?.statusCode;
    if (code == 403 || code == 401) {
      return repli;
    }
    rethrow;
  }
}

/// La même chose pour une réponse brute de Dio, quand l'appelant lit
/// lui-même `response.data`.
///
/// Le repli porte une charge vide plutôt que `null` : l'appelant continue de
/// lire `results[n].data` sans avoir à se demander, à chaque accès, si la
/// source lui était ouverte.
Future<Response<dynamic>> reponseTolerante(
  Future<Response<dynamic>> appel, {
  Object donneesDeRepli = const <dynamic>[],
}) async {
  try {
    return await appel;
  } on DioException catch (erreur) {
    final code = erreur.response?.statusCode;
    if (code == 403 || code == 401) {
      return Response<dynamic>(
        requestOptions: erreur.requestOptions,
        statusCode: code,
        data: donneesDeRepli,
      );
    }
    rethrow;
  }
}
