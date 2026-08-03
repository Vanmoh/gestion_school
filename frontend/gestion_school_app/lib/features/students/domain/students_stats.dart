/// Effectifs d'un etablissement, tels que le serveur les compte.
///
/// Distincts du nombre de lignes affichees: l'en-tete de la page decrit
/// l'ecole entiere, le tableau ne decrit que la page filtree en cours.
class StudentsStats {
  final int total;
  final int active;
  final int archived;
  final int newThisYear;
  final int genderMissing;
  final String academicYear;

  const StudentsStats({
    required this.total,
    required this.active,
    required this.archived,
    required this.newThisYear,
    required this.genderMissing,
    required this.academicYear,
  });

  const StudentsStats.empty()
    : total = 0,
      active = 0,
      archived = 0,
      newThisYear = 0,
      genderMissing = 0,
      academicYear = '';

  /// Rien a afficher tant que le serveur n'a pas repondu: mieux vaut une
  /// ligne absente qu'une ligne de zeros, qui se lirait comme « ecole vide ».
  bool get isEmpty => total == 0 && active == 0 && archived == 0;
}
