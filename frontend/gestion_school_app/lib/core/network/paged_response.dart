import 'package:dio/dio.dart';

/// Recollement des reponses paginees renvoyees par l'API.
///
/// L'API pagine par defaut. Sans ce recollement, tout appel de liste qui ne
/// demande pas explicitement de page ne verrait que les 100 premiers elements:
/// une classe disparaitrait d'un menu deroulant sans le moindre message
/// d'erreur. Le recollement est fait ici, au niveau du client HTTP, plutot que
/// dans chacun des depots qui ont tous leur propre extraction de `results`.

/// Marque une requete emise par le suivi automatique des pages, pour qu'elle
/// ne declenche pas elle-meme un nouveau suivi.
const String followedPageFlag = 'followed_page';

/// Plafond de securite. A 100 elements par page cote serveur, cela represente
/// 5000 lignes: au-dela, une liste incomplete est preferable a une avalanche
/// de requetes.
const int maxAutoFollowedPages = 50;

/// Marque une taille de page posee par le client, et non par l'appelant.
///
/// La nuance compte: une page demandee par l'ecran veut dire « je pilote ma
/// pagination, ne recolle rien ». Une page posee ici veut dire l'inverse --
/// « ramene tout, mais en moins d'allers-retours ».
const String defaultPageSizeFlag = 'page_size_par_defaut';

/// Taille demandee aux listes qui n'en fixent pas.
///
/// L'API pagine par cent, et le recollement suit les pages **une par une, en
/// serie**: cinq cents eleves faisaient cinq allers-retours qui s'attendaient,
/// pour une seule liste -- et l'ecran des notes en charge six. A cinq cents,
/// le maximum accepte par l'API, la meme liste tient en une requete.
const int taillePageParDefaut = 500;

/// Vrai si l'appelant pilote lui-meme sa pagination.
///
/// La regle reprend la convention deja suivie par le code existant: les ecrans
/// qui affichent des tableaux pagines passent `page`/`page_size`, les autres
/// attendent une liste complete.
bool callerHandlesPaging(RequestOptions options) {
  if (options.extra[followedPageFlag] == true) {
    return true;
  }
  // Une taille posee par le client ne vaut pas pilotage: le recollement doit
  // continuer de suivre `next`. Sans cette exception, ajouter `page_size`
  // pour aller plus vite tronquerait silencieusement toute liste depassant
  // la page -- une classe disparaitrait d'un menu sans le moindre message.
  if (options.extra[defaultPageSizeFlag] == true) {
    return false;
  }
  if (options.queryParameters.containsKey('page') ||
      options.queryParameters.containsKey('page_size')) {
    return true;
  }
  // Le parametre peut aussi etre inscrit directement dans le chemin.
  final inPath = Uri.tryParse(options.path)?.queryParameters ?? const {};
  return inPath.containsKey('page') || inPath.containsKey('page_size');
}

/// Suit les liens `next` et renvoie la reponse enrichie de toutes les pages.
///
/// En cas de troncature par le plafond, ou d'echec sur une page suivante,
/// `next` est laisse renseigne: la liste est incomplete et doit pouvoir etre
/// reconnue comme telle plutot que passer pour complete.
Future<Response<dynamic>> followRemainingPages(
  Dio dio,
  Response<dynamic> response,
) async {
  final data = response.data;
  if (data is! Map || data['results'] is! List || !data.containsKey('next')) {
    return response;
  }
  if (callerHandlesPaging(response.requestOptions)) {
    return response;
  }

  final aggregated = List<dynamic>.from(data['results'] as List);
  String? next = _linkOf(data['next']);
  var followed = 0;

  while (next != null) {
    if (followed >= maxAutoFollowedPages) {
      return _rebuild(response, data, aggregated, next);
    }

    final Response<dynamic> page;
    try {
      page = await dio.get<dynamic>(
        next,
        options: Options(extra: const {followedPageFlag: true}),
      );
    } catch (_) {
      // Une page suivante inaccessible ne doit pas faire echouer un appel qui
      // a deja ramene des donnees exploitables.
      return _rebuild(response, data, aggregated, next);
    }

    final pageData = page.data;
    if (pageData is! Map || pageData['results'] is! List) {
      return _rebuild(response, data, aggregated, next);
    }

    aggregated.addAll(pageData['results'] as List);
    next = _linkOf(pageData['next']);
    followed += 1;
  }

  return _rebuild(response, data, aggregated, null);
}

/// Extrait les lignes d'une reponse de liste, paginee ou non.
///
/// A privilegier sur un `data as List`: l'API pagine par defaut, et un tel
/// transtypage leve une erreur au lieu de lire `results`. Quand l'appel est
/// enveloppe dans un `catch`, la panne se lit alors comme une liste vide.
List<Map<String, dynamic>> rowsOf(dynamic data) {
  final List<dynamic> raw;
  if (data is Map && data['results'] is List) {
    raw = data['results'] as List<dynamic>;
  } else if (data is List) {
    raw = data;
  } else {
    return const [];
  }

  return raw
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

String? _linkOf(dynamic raw) {
  if (raw == null) {
    return null;
  }
  final value = raw.toString().trim();
  if (value.isEmpty || value == 'null') {
    return null;
  }
  return value;
}

Response<dynamic> _rebuild(
  Response<dynamic> response,
  Map<dynamic, dynamic> original,
  List<dynamic> results,
  String? next,
) {
  final rebuilt = Map<String, dynamic>.from(original);
  rebuilt['results'] = results;
  rebuilt['next'] = next;
  response.data = rebuilt;
  return response;
}

/// Pose une taille de page sur une requete de liste qui n'en demande aucune.
///
/// Appelee par l'intercepteur du client, avant l'envoi. Ne touche ni aux
/// requetes qui pilotent deja leur pagination, ni aux pages suivies par le
/// recollement -- elles portent deja la taille de la premiere.
void appliquerLaTaillePageParDefaut(RequestOptions options) {
  if (options.method.toUpperCase() != 'GET') {
    return;
  }
  if (options.extra[followedPageFlag] == true) {
    return;
  }
  if (options.queryParameters.containsKey('page') ||
      options.queryParameters.containsKey('page_size')) {
    return;
  }
  final dansLeChemin = Uri.tryParse(options.path)?.queryParameters ?? const {};
  if (dansLeChemin.containsKey('page') ||
      dansLeChemin.containsKey('page_size')) {
    return;
  }

  options.queryParameters = {
    ...options.queryParameters,
    'page_size': taillePageParDefaut,
  };
  options.extra = {...options.extra, defaultPageSizeFlag: true};
}
