import '../../students/domain/student.dart';

/// Une rubrique du dossier, ou son refus.
///
/// Une section interdite arrive avec `granted: false` et sans donnees. Elle
/// n'est volontairement pas filtree par le serveur: masquer la rubrique ferait
/// lire « aucun incident » la ou il faut lire « vous n'y avez pas acces ».
class DossierSection {
  final String key;
  final String label;
  final String module;
  final bool granted;
  final int count;

  /// Chiffres cles calcules sur la totalite de la rubrique, pas sur les
  /// elements renvoyes: `count` peut valoir 200 quand `items` en porte 50.
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> items;
  final bool hasMore;

  const DossierSection({
    required this.key,
    required this.label,
    required this.module,
    required this.granted,
    this.count = 0,
    this.summary = const {},
    this.items = const [],
    this.hasMore = false,
  });

  bool get isEmpty => granted && count == 0;

  factory DossierSection.fromJson(Map<String, dynamic> map) {
    final granted = map['granted'] == true;
    return DossierSection(
      key: map['key']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      module: map['module']?.toString() ?? '',
      granted: granted,
      count: granted ? _asInt(map['count']) : 0,
      summary: granted && map['summary'] is Map
          ? Map<String, dynamic>.from(map['summary'] as Map)
          : const {},
      items: granted && map['items'] is List
          ? (map['items'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : const [],
      hasMore: granted && map['has_more'] == true,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// Tout ce que l'etablissement sait d'un eleve, en une reponse.
class StudentDossier {
  final Student student;
  final List<DossierSection> sections;

  const StudentDossier({required this.student, required this.sections});

  DossierSection? section(String key) {
    for (final section in sections) {
      if (section.key == key) return section;
    }
    return null;
  }

  factory StudentDossier.fromJson(Map<String, dynamic> map) {
    final rawSections = map['sections'];
    return StudentDossier(
      student: Student.fromJson(
        map['student'] is Map
            ? Map<String, dynamic>.from(map['student'] as Map)
            : const {},
      ),
      sections: rawSections is List
          ? rawSections
                .whereType<Map>()
                .map(
                  (row) =>
                      DossierSection.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList()
          : const [],
    );
  }
}
