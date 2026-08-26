// Regroupement des incidents disciplinaires par enfant, pour la vue parent.
// Logique pure, isolee de la presentation pour rester testable.

import 'discipline_incident.dart';

/// Incidents d'un meme enfant, tries du plus recent au plus ancien.
class ChildIncidentGroup {
  final int studentId;
  final String childName;
  final String matricule;
  final List<DisciplineIncident> incidents;

  const ChildIncidentGroup({
    required this.studentId,
    required this.childName,
    required this.matricule,
    required this.incidents,
  });

  int get openCount => incidents.where((row) => row.estOuvert).length;
}

/// Groupe les incidents par eleve, chaque groupe trie du plus recent au plus
/// ancien, les groupes eux-memes tries par nom d'enfant.
///
/// Prend des incidents typés et non des `Map` brutes: la vue parent lisait
/// directement le JSON de l'API, si bien qu'un champ renomme cote serveur
/// ne se voyait qu'a l'execution, sur un ecran vide.
List<ChildIncidentGroup> groupIncidentsByChild(
  List<DisciplineIncident> incidents,
) {
  final buckets = <int, List<DisciplineIncident>>{};
  final names = <int, String>{};
  final matricules = <int, String>{};

  for (final incident in incidents) {
    final key = incident.studentId;
    buckets.putIfAbsent(key, () => <DisciplineIncident>[]).add(incident);

    // Le nom peut manquer sur certaines lignes: on garde le premier non vide.
    final name = incident.studentFullName.trim();
    if (name.isNotEmpty) {
      names.putIfAbsent(key, () => name);
    }
    final matricule = incident.studentMatricule.trim();
    if (matricule.isNotEmpty) {
      matricules.putIfAbsent(key, () => matricule);
    }
  }

  final groups = buckets.entries.map((entry) {
    final sorted = [...entry.value]
      ..sort((a, b) => b.dateDeTri.compareTo(a.dateDeTri));
    return ChildIncidentGroup(
      studentId: entry.key,
      childName: names[entry.key] ?? 'Eleve',
      matricule: matricules[entry.key] ?? '',
      incidents: sorted,
    );
  }).toList();

  groups.sort((a, b) => a.childName.compareTo(b.childName));
  return groups;
}
