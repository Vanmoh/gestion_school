// Regroupement des incidents disciplinaires par enfant, pour la vue parent.
// Logique pure, isolee de la presentation pour rester testable.

/// Incidents d'un meme enfant, tries du plus recent au plus ancien.
class ChildIncidentGroup {
  final String studentKey;
  final String childName;
  final String matricule;
  final List<Map<String, dynamic>> incidents;

  const ChildIncidentGroup({
    required this.studentKey,
    required this.childName,
    required this.matricule,
    required this.incidents,
  });

  int get openCount =>
      incidents.where((row) => incidentStatus(row) != 'resolved').length;
}

/// Statut normalise d'un incident: 'open' par defaut.
String incidentStatus(Map<String, dynamic> incident) {
  final raw = incident['status']?.toString().trim() ?? '';
  return raw.isEmpty ? 'open' : raw;
}

/// Date de l'incident; les dates absentes ou invalides sont repoussees en fin
/// de liste plutot que d'interrompre le tri.
DateTime incidentDate(Map<String, dynamic> incident) {
  return DateTime.tryParse(incident['incident_date']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// Groupe les incidents par eleve, chaque groupe trie du plus recent au plus
/// ancien, les groupes eux-memes tries par nom d'enfant.
List<ChildIncidentGroup> groupIncidentsByChild(
  List<Map<String, dynamic>> incidents,
) {
  final buckets = <String, List<Map<String, dynamic>>>{};
  final names = <String, String>{};
  final matricules = <String, String>{};

  for (final incident in incidents) {
    final key = incident['student']?.toString() ?? '';
    final name = incident['student_full_name']?.toString().trim() ?? '';
    final matricule = incident['student_matricule']?.toString().trim() ?? '';

    buckets.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(incident);
    // Le nom peut manquer sur certaines lignes: on garde le premier non vide.
    if (name.isNotEmpty) {
      names.putIfAbsent(key, () => name);
    }
    if (matricule.isNotEmpty) {
      matricules.putIfAbsent(key, () => matricule);
    }
  }

  final groups = buckets.entries.map((entry) {
    final sorted = [...entry.value]
      ..sort((a, b) => incidentDate(b).compareTo(incidentDate(a)));
    return ChildIncidentGroup(
      studentKey: entry.key,
      childName: names[entry.key] ?? 'Eleve',
      matricule: matricules[entry.key] ?? '',
      incidents: sorted,
    );
  }).toList();

  groups.sort((a, b) => a.childName.compareTo(b.childName));
  return groups;
}
