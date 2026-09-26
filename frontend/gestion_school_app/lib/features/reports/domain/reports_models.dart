/// Un encaissement, tel qu'il s'imprime sur un reçu.
class RecuItem {
  final int id;
  final String quand;
  final String eleve;
  final String matricule;
  final String typeDeFrais;
  final double montant;
  final String moyen;
  final String reference;
  final String encaissePar;

  const RecuItem({
    required this.id,
    required this.quand,
    required this.eleve,
    required this.matricule,
    required this.typeDeFrais,
    required this.montant,
    required this.moyen,
    required this.reference,
    required this.encaissePar,
  });

  String get jour => quand.split('T').first;
}

/// Une page de reçus, telle que le serveur la découpe.
///
/// L'écran recevait la liste entière et la découpait lui-même, dix lignes par
/// dix lignes: le serveur envoyait quinze mille reçus pour en afficher dix.
class PageDeRecus {
  final List<RecuItem> lignes;
  final int total;
  final int page;
  final int pages;

  const PageDeRecus({
    required this.lignes,
    required this.total,
    required this.page,
    required this.pages,
  });

  static const vide = PageDeRecus(lignes: [], total: 0, page: 1, pages: 1);

  bool get aUnePrecedente => page > 1;
  bool get aUneSuivante => page < pages;
}

/// Ce qui peuple les listes de choix de l'écran, et les chiffres de l'en-tête.
class ContexteDesRapports {
  final List<OptionEleve> eleves;
  final List<OptionAnnee> annees;
  final int nombreDEncaissements;
  final double totalEncaisse;

  const ContexteDesRapports({
    required this.eleves,
    required this.annees,
    required this.nombreDEncaissements,
    required this.totalEncaisse,
  });

  static const vide = ContexteDesRapports(
    eleves: [],
    annees: [],
    nombreDEncaissements: 0,
    totalEncaisse: 0,
  );
}

class OptionEleve {
  final int id;
  final String nom;
  final String matricule;
  final int? classeId;
  final String classe;

  const OptionEleve({
    required this.id,
    required this.nom,
    required this.matricule,
    required this.classe,
    this.classeId,
  });

  String get libelle => matricule.isEmpty ? nom : '$nom — $matricule';
}

class OptionAnnee {
  final int id;
  final String nom;

  const OptionAnnee({required this.id, required this.nom});
}
