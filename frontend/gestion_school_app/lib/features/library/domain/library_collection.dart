/// Une serie du fonds documentaire, et les matieres qu'elle contient.
///
/// Les compteurs viennent du serveur: les recalculer a partir des documents
/// charges donnerait un total faux tant qu'une page reste a venir.
class LibraryCollection {
  final int id;
  final String code;
  final String label;
  final int documentCount;
  final List<LibraryCategory> categories;

  const LibraryCollection({
    required this.id,
    required this.code,
    required this.label,
    required this.documentCount,
    required this.categories,
  });

  factory LibraryCollection.fromJson(Map<String, dynamic> json) {
    final brutes = json['categories'];
    return LibraryCollection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: json['code']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
      categories: brutes is List
          ? brutes
                .whereType<Map<String, dynamic>>()
                .map(LibraryCategory.fromJson)
                .toList(growable: false)
          : const [],
    );
  }
}

class LibraryCategory {
  final int id;
  final String name;
  final int documentCount;

  const LibraryCategory({
    required this.id,
    required this.name,
    required this.documentCount,
  });

  factory LibraryCategory.fromJson(Map<String, dynamic> json) {
    return LibraryCategory(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? '',
      documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
    );
  }
}
