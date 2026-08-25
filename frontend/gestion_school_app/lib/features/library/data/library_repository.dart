import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/library_collection.dart';
import '../domain/library_document.dart';

/// Le fonds documentaire: les series, leurs matieres, leurs PDF.
///
/// Distinct des ouvrages physiques de la meme rubrique: un PDF ne s'emprunte
/// pas, il se consulte, et il n'existe qu'en un exemplaire pour toute l'ecole.
class LibraryRepository {
  final Dio dio;

  LibraryRepository(this.dio);

  List<dynamic> _extractRows(dynamic data) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      return data['results'] as List<dynamic>;
    }
    if (data is List<dynamic>) {
      return data;
    }
    return const [];
  }

  Future<List<LibraryCollection>> fetchCollections() async {
    final response = await dio.get('/library-collections/');
    return _extractRows(response.data)
        .whereType<Map<String, dynamic>>()
        .map(LibraryCollection.fromJson)
        .toList(growable: false);
  }

  /// Tous les documents d'une serie, pagination suivie jusqu'au bout.
  ///
  /// La plus grosse serie en compte 322: une page de 500 suffit presque
  /// toujours, mais suivre `next` evite d'afficher une matiere tronquee le
  /// jour ou le fonds grossit.
  Future<List<LibraryDocument>> fetchDocuments({
    required int collectionId,
    String search = '',
  }) async {
    final documents = <LibraryDocument>[];
    String? chemin = '/library-documents/';
    Map<String, dynamic>? parametres = {
      'collection': collectionId,
      'page_size': 500,
      if (search.trim().isNotEmpty) 'search': search.trim(),
    };

    while (chemin != null) {
      final response = await dio.get(chemin, queryParameters: parametres);
      documents.addAll(
        _extractRows(response.data)
            .whereType<Map<String, dynamic>>()
            .map(LibraryDocument.fromJson),
      );

      final data = response.data;
      final suivant = data is Map<String, dynamic> ? data['next'] : null;
      // `next` est une URL absolue: les parametres y sont deja, les repasser
      // les dupliquerait.
      chemin = suivant?.toString();
      parametres = null;
    }

    return documents;
  }

  /// Le PDF lui-meme.
  ///
  /// Toujours par l'API, jamais par l'URL de la source: c'est elle qui sait
  /// si le fichier est deja rapatrie ou s'il faut encore le relayer.
  ///
  /// [onProgression] recoit une fraction entre 0 et 1, ou null tant que le
  /// poids total reste inconnu. Le fonds va de 50 Ko a 127 Mo: sans ce
  /// retour, l'ecran affichait le meme rond qui tourne pour une brochure de
  /// deux pages et pour un recueil d'annales entier.
  Future<Uint8List> fetchDocumentFile(
    int documentId, {
    void Function(double? fraction)? onProgression,
  }) async {
    final response = await dio.get<List<int>>(
      '/library-documents/$documentId/file/',
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onProgression == null
          ? null
          : (recus, total) {
              // total vaut -1 quand la reponse ne porte pas de
              // Content-Length. L'API prend soin de le transmettre, y compris
              // pour un document relaye, mais un intermediaire peut le
              // retirer: on annonce alors une progression indeterminee
              // plutot qu'une fraction fausse.
              onProgression(total > 0 ? recus / total : null);
            },
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }
}
