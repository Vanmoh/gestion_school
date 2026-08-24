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
  final String importError;

  const LibraryDocument({
    required this.id,
    required this.title,
    required this.categoryId,
    required this.categoryName,
    required this.sizeBytes,
    required this.isDownloaded,
    required this.importError,
  });

  factory LibraryDocument.fromJson(Map<String, dynamic> json) {
    return LibraryDocument(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      categoryId: (json['category'] as num?)?.toInt() ?? 0,
      categoryName: json['category_name']?.toString() ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      isDownloaded: json['is_downloaded'] == true,
      importError: json['import_error']?.toString() ?? '',
    );
  }

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
