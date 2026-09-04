/// Un PDF du fonds.
///
/// `isDownloaded` ne change rien a la lecture -- l'API sert le fichier dans
/// les deux cas -- mais dit si l'ecole en possede la copie ou si elle depend
/// encore de la source.
class LibraryDocument {
  final int id;
  final String title;
  final int categoryId;
  final String categoryName;
  final int sizeBytes;
  final bool isDownloaded;

  /// Ce document s'ouvrira-t-il sur ce serveur, aujourd'hui.
  ///
  /// Faux quand le fichier n'est pas rapatrie et que le serveur ne relaie pas
  /// la source -- le cas d'une ecole sans Internet. Le serveur le calcule, lui
  /// seul connaissant son reglage.
  final bool isReadable;
  final String importError;
  final String description;

  /// « import » pour le fonds commun, « upload » pour un depot de l'ecole.
  ///
  /// Seul le second se renomme et se supprime: le premier revient tel quel
  /// a la prochaine passe d'import, et il est partage par toutes les ecoles.
  final String origin;
  final String uploadedByName;

  const LibraryDocument({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.categoryName,
    required this.sizeBytes,
    required this.isDownloaded,
    required this.importError,
    // Vrai par defaut: c'est ce que repond une API qui ne connait pas encore
    // le champ, et un document qu'on croit lisible a tort echoue au clic --
    // l'inverse le rendrait inaccessible sans raison.
    this.isReadable = true,
    // Valeurs du fonds importe: c'est le cas historique, et un document de
    // test n'a pas a les repeter pour dire qu'il en vient.
    this.description = '',
    this.origin = 'import',
    this.uploadedByName = '',
  });

  factory LibraryDocument.fromJson(Map<String, dynamic> json) {
    return LibraryDocument(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      categoryId: (json['category'] as num?)?.toInt() ?? 0,
      categoryName: json['category_name']?.toString() ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      isDownloaded: json['is_downloaded'] == true,
      isReadable: json.containsKey('is_readable')
          ? json['is_readable'] == true
          : true,
      importError: json['import_error']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      origin: json['origin']?.toString() ?? 'import',
      uploadedByName: json['uploaded_by_name']?.toString() ?? '',
    );
  }

  /// Depose depuis l'application, par opposition au fonds importe.
  bool get estDepose => origin == 'upload';

  /// Taille lisible, vide tant que le fichier n'a pas ete pese.
  ///
  /// Un « 0 Ko » sur une ligne encore chez la source se lirait comme un
  /// fichier vide.
  String get tailleLisible {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).round()} Ko';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}
