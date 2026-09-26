/// Une ligne du journal d'audit.
///
/// L'écran manipulait des `Map<String, dynamic>` bruts, et relisait
/// `row['status_code']` à six endroits avec six conversions différentes.
class LigneDuJournal {
  final int id;
  final String quand;
  final String auteur;
  final String role;
  final String action;
  final String methode;
  final String module;
  final String chemin;
  final String cible;
  final int statutHttp;
  final bool reussi;
  final String adresseIp;
  final String details;
  final String etablissement;

  const LigneDuJournal({
    required this.id,
    required this.quand,
    required this.auteur,
    required this.role,
    required this.action,
    required this.methode,
    required this.module,
    required this.chemin,
    required this.cible,
    required this.statutHttp,
    required this.reussi,
    required this.adresseIp,
    required this.details,
    required this.etablissement,
  });

  /// La date seule, sans l'heure — pour une colonne qui doit rester lisible.
  String get jour => quand.split('T').first;

  /// L'heure seule, à la seconde.
  String get heure {
    final parts = quand.split('T');
    if (parts.length < 2) return '';
    return parts[1].split('.').first.split('+').first;
  }
}

/// Ce dont les filtres ont besoin, tel que le journal le contient.
///
/// Les modules sont lus dans le journal réel plutôt que devinés: ils viennent
/// du chemin d'URL, et une liste écrite à la main côté écran aurait vieilli
/// dès la première route ajoutée.
class RepertoireDuJournal {
  final List<String> modules;
  final List<AuteurDuJournal> auteurs;

  const RepertoireDuJournal({required this.modules, required this.auteurs});

  static const vide = RepertoireDuJournal(modules: [], auteurs: []);
}

class AuteurDuJournal {
  final int id;
  final String nom;
  final String role;

  const AuteurDuJournal({
    required this.id,
    required this.nom,
    required this.role,
  });
}

/// Comment trier le journal.
enum TriDuJournal {
  plusRecentDAbord('-created_at', 'Date (récent → ancien)'),
  plusAncienDAbord('created_at', 'Date (ancien → récent)'),
  actionCroissante('action', 'Action (A → Z)'),
  actionDecroissante('-action', 'Action (Z → A)'),
  statutDecroissant('-status_code', 'Statut HTTP (décroissant)'),
  statutCroissant('status_code', 'Statut HTTP (croissant)');

  final String code;
  final String libelle;

  const TriDuJournal(this.code, this.libelle);
}
