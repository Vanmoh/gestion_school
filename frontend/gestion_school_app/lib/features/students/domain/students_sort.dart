// Tri du registre des eleves: correspondance entre les colonnes du tableau,
// la cle de tri interne et le parametre `ordering` de l'API.
// Logique pure, isolee de la presentation pour rester testable.

/// Colonnes triables du registre, indexees comme dans le DataTable.
///
/// L'index 0 est la colonne de cases a cocher, 1 le numéro de ligne: ni l'une
/// ni l'autre ne correspond a un ordre serveur. Les colonnes absentes de cette
/// table (Telephone, Acces) restent non triables faute d'ordre equivalent.
const studentSortKeyByColumnIndex = <int, String>{
  2: 'matricule',
  3: 'name',
  4: 'gender',
  5: 'classroom',
  6: 'birth',
  8: 'status',
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
    'gender' => 'gender',
    'birth' => 'birth_date',
    _ => 'user__last_name',
  };
  return ascending ? field : '-$field';
}
