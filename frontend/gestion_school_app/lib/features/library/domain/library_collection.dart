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

  /// Vrai pour le fonds partage par toutes les ecoles.
  ///
  /// Il ne s'alimente que par la commande d'import: c'est ce drapeau qui
  /// dit a l'ecran ou proposer le depot d'un document et ou l'inhiber,
  /// plutot que de laisser l'utilisateur remplir un formulaire que le
  /// serveur refusera.
  final bool isCommun;

  const LibraryCollection({
    required this.id,
    required this.code,
    required this.label,
    required this.documentCount,
    required this.categories,
    this.isCommun = true,
  });

  factory LibraryCollection.fromJson(Map<String, dynamic> json) {
    final brutes = json['categories'];
    return LibraryCollection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: json['code']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      documentCount: (json['document_count'] as num?)?.toInt() ?? 0,
      // Un serveur anterieur au cloisonnement ne renvoie pas le champ: tout
      // ce qu'il sert est alors le fonds commun, et l'ecran n'y propose
      // aucun depot -- le refus vient du serveur, jamais d'une supposition.
      isCommun: json['is_commun'] as bool? ?? true,
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
