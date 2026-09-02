/// Une annee scolaire, telle que le serveur la sert.
///
/// Elle appartient a un etablissement: chaque ecole a ses annees, ses dates
/// et sa cloture. Une seule est ouverte a la saisie a la fois.
class AnneeScolaire {
  final int id;
  final String nom;
  final String debut;
  final String fin;

  /// L'année de saisie de l'etablissement. Une seule a la fois.
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

  /// L'etat de l'annee, en trois mots exclusifs.
  ///
  /// L'ordre compte: une année cloturee l'est meme si le serveur la marque
  /// encore courante -- la cloture prime sur tout le reste.
  EtatAnnee get etat {
    if (estCloturee) return EtatAnnee.cloturee;
    if (estCourante) return EtatAnnee.active;
    return EtatAnnee.consultee;
  }

  DateTime? get debutLe => DateTime.tryParse(debut);
  DateTime? get finLe => DateTime.tryParse(fin);

  /// « 1 sept. 2025 → 31 juil. 2026 », vide si les dates manquent.
  String get periode {
    final d = debutLe;
    final f = finLe;
    if (d == null || f == null) return '';
    return '${_jourCourt(d)} → ${_jourCourt(f)}';
  }

  /// Part de l'annee ecoulee, de 0 a 1. Null hors de sa periode ou sans
  /// dates: une barre a 0 % ou a 100 % se lirait comme une progression,
  /// alors qu'on est simplement en dehors.
  double? get avancement {
    final d = debutLe;
    final f = finLe;
    if (d == null || f == null) return null;

    final total = f.difference(d).inDays;
    if (total <= 0) return null;

    final maintenant = DateTime.now();
    if (maintenant.isBefore(d) || maintenant.isAfter(f)) return null;
    return (maintenant.difference(d).inDays / total).clamp(0.0, 1.0);
  }

  /// « 3e mois sur 11 », vide quand l'avancement n'a pas de sens.
  String get moisEcoules {
    final d = debutLe;
    final f = finLe;
    if (d == null || f == null || avancement == null) return '';

    final total = ((f.difference(d).inDays) / 30).round();
    final ecoules = ((DateTime.now().difference(d).inDays) / 30).floor() + 1;
    if (total <= 0) return '';
    return '$ecoules${ecoules == 1 ? 'er' : 'e'} mois sur $total';
  }

  static String _jourCourt(DateTime valeur) {
    const mois = [
      'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
    ];
    return '${valeur.day} ${mois[valeur.month - 1]} ${valeur.year}';
  }
}

/// Ce qu'une annee est pour celui qui la regarde.
///
/// Trois etats et non deux: « je saisis dedans », « je la consulte », « elle
/// est fermee ». Les confondre laissait saisir sur une annee passee sans que
/// rien ne le signale a l'ecran.
enum EtatAnnee {
  active('Active'),
  consultee('Consultée'),
  cloturee('Clôturée');

  final String libelle;

  const EtatAnnee(this.libelle);
}
