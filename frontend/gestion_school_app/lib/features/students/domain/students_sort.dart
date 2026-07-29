// Tri du registre des eleves: correspondance entre les colonnes du tableau,
// la cle de tri interne et le parametre `ordering` de l'API.
// Logique pure, isolee de la presentation pour rester testable.

/// Colonnes triables du registre, indexees comme dans le DataTable.
///
/// Les colonnes absentes (N°, Genre, Date de naissance, Telephone, Acces)
/// n'ont pas d'ordre serveur correspondant et restent non triables.
const studentSortKeyByColumnIndex = <int, String>{
  1: 'matricule',
  2: 'name',
  4: 'classroom',
  7: 'status',
};

/// Cle de tri par defaut, appliquee au chargement et apres reinitialisation.
const defaultStudentSortKey = 'name';

/// Index de la colonne portant l'indicateur de tri, ou `null` si la cle
/// courante ne correspond a aucune colonne affichee.
int? studentSortColumnIndex(String sortKey) {
  for (final entry in studentSortKeyByColumnIndex.entries) {
    if (entry.value == sortKey) return entry.key;
  }
  return null;
}

/// Cle de tri associee a une colonne, ou `null` si elle n'est pas triable.
String? studentSortKeyForColumn(int columnIndex) =>
    studentSortKeyByColumnIndex[columnIndex];

/// Parametre `ordering` envoye a l'API pour la cle et le sens donnes.
String studentsOrdering({required String sortKey, required bool ascending}) {
  final field = switch (sortKey) {
    'matricule' => 'matricule',
    'classroom' => 'classroom__name',
    'status' => 'is_archived',
    _ => 'user__last_name',
  };
  return ascending ? field : '-$field';
}
