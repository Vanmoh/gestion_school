/// Les recettes et dépenses d'une période, telles que la base les compte.
///
/// L'écran Finances additionnait les lignes qu'il avait chargées. Le journal
/// des encaissements étant paginé par vingt-cinq, « Montant encaissé »
/// décrivait la page et non la période : au-delà de vingt-cinq versements
/// dans le mois, le chiffre était faux, et il changeait en tournant la page.
///
/// Le serveur agrège désormais en base, et ce type transporte le résultat.
class TotauxFinance {
  /// Somme des versements non annulés de la période.
  final double recettes;

  /// Combien de versements composent ce montant.
  final int encaissements;

  /// Ventilation par méthode, pour rapprocher la caisse du relevé.
  final Map<String, double> parMethode;

  /// Dépenses validées aux deux niveaux. Nul pour une famille, qui voit ses
  /// propres versements et jamais les dépenses de l'école.
  final double? depensesValidees;

  /// Dépenses saisies mais pas encore contresignées. Montrées à part plutôt
  /// que passées sous silence : une école qui n'a pas fait tourner son
  /// circuit doit voir où est passé son argent.
  final double? depensesEnAttente;

  /// Recettes moins dépenses validées. Nul pour une famille.
  final double? resultat;

  const TotauxFinance({
    required this.recettes,
    required this.encaissements,
    this.parMethode = const {},
    this.depensesValidees,
    this.depensesEnAttente,
    this.resultat,
  });

  static double _montant(Object? brut) =>
      double.tryParse('${brut ?? ''}'.replaceAll(',', '.')) ?? 0;

  static double? _montantOuNul(Object? brut) =>
      brut == null ? null : _montant(brut);

  factory TotauxFinance.fromJson(Map<String, dynamic> json) {
    final ventilation = json['recettes_par_methode'];
    return TotauxFinance(
      recettes: _montant(json['recettes']),
      encaissements: (json['encaissements'] as num?)?.toInt() ?? 0,
      parMethode: ventilation is Map
          ? {
              for (final entree in ventilation.entries)
                entree.key.toString(): _montant(entree.value),
            }
          : const {},
      depensesValidees: _montantOuNul(json['depenses_validees']),
      depensesEnAttente: _montantOuNul(json['depenses_en_attente']),
      resultat: _montantOuNul(json['resultat']),
    );
  }
}
