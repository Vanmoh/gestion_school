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

  /// L'année et l'école que ces chiffres couvrent, nommées par le serveur.
  ///
  /// Sans elles, l'écran affichait « Montant encaissé 187 520 000 FCFA » sous
  /// un bandeau disant « IFP-OBK · 2025-2026 » — et c'étaient les quatre
  /// établissements de toutes leurs années. Un chiffre qui ne dit pas ce
  /// qu'il couvre se lit comme couvrant ce que la page annonce.
  final String anneeNommee;
  final String etablissementNomme;

  const ContexteDesRapports({
    required this.eleves,
    required this.annees,
    required this.nombreDEncaissements,
    required this.totalEncaisse,
    this.anneeNommee = '',
    this.etablissementNomme = '',
  });

  static const vide = ContexteDesRapports(
    eleves: [],
    annees: [],
    nombreDEncaissements: 0,
    totalEncaisse: 0,
  );

  /// « 2025-2026 · IFP-OBK », ou ce qui s'en approche le plus.
  String get portee {
    final morceaux = [
      anneeNommee.trim(),
      etablissementNomme.trim(),
    ].where((part) => part.isNotEmpty);
    return morceaux.join(' · ');
  }
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

  /// « Awa Coulibaly — IO1EM125E0001F », et jamais le matricule deux fois.
  ///
  /// Le dépôt lisait le nom sous une clé que le serveur n'envoie pas: il
  /// était donc toujours vide, et un repli le remplaçait par le matricule.
  /// La liste affichait « IO2TC26E0001M — IO2TC26E0001M », où l'on ne
  /// reconnaît aucun élève.
  String get libelle {
    final nomNet = nom.trim();
    final matriculeNet = matricule.trim();
    if (nomNet.isEmpty || nomNet == matriculeNet) {
      return matriculeNet.isEmpty ? 'Élève' : matriculeNet;
    }
    return matriculeNet.isEmpty ? nomNet : '$nomNet — $matriculeNet';
  }
}

class OptionAnnee {
  final int id;
  final String nom;

  const OptionAnnee({required this.id, required this.nom});
}
