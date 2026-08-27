/// Une annee scolaire, telle que le serveur la sert.
///
/// Elle appartient a un etablissement: chaque ecole a ses annees, ses dates
/// et sa cloture. Une seule est ouverte a la saisie a la fois.
class AnneeScolaire {
  final int id;
  final String nom;
  final String debut;
  final String fin;

  /// L'annee de saisie de l'etablissement. Une seule a la fois.
  final bool estCourante;

  /// Une annee cloturee reste consultable; l'ecriture y est reservee a la
  /// direction, et le serveur en garde la trace.
  final bool estCloturee;

  final String etablissementNom;

  const AnneeScolaire({
    required this.id,
    required this.nom,
    this.debut = '',
    this.fin = '',
    this.estCourante = false,
    this.estCloturee = false,
    this.etablissementNom = '',
  });

  factory AnneeScolaire.fromJson(Map<String, dynamic> json) {
    return AnneeScolaire(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nom: json['name']?.toString() ?? '',
      debut: json['start_date']?.toString() ?? '',
      fin: json['end_date']?.toString() ?? '',
      estCourante: json['is_active'] == true,
      estCloturee: json['is_closed'] == true,
      etablissementNom: json['etablissement_name']?.toString() ?? '',
    );
  }

  /// Reduit a ce que l'intercepteur reseau doit relire: l'identifiant, et
  /// de quoi reafficher le libelle avant le premier chargement.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': nom,
    'is_active': estCourante,
    'is_closed': estCloturee,
  };

  /// Ce qui s'affiche dans le selecteur.
  String get libelle {
    if (estCloturee) return '$nom (clôturée)';
    if (estCourante) return '$nom (en cours)';
    return nom;
  }
}
