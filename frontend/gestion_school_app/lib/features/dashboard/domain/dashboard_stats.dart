class DashboardStats {
  final int students;
  final double monthlyRevenue;
  final double monthlyExpenses;

  /// Depenses saisies mais pas encore validees jusqu'au second niveau.
  ///
  /// Elles n'entrent pas dans le benefice -- elles l'amputaient avant, sans
  /// que rien ne le dise -- mais l'ecran doit les montrer: une ecole qui n'a
  /// pas encore fait tourner son circuit de validation doit voir ou sont
  /// passees ses depenses.
  final double monthlyExpensesPending;
  final double monthlyProfit;
  final int monthlyAbsences;
  final int classrooms;
  final int teachers;
  final int? activeEtablissementId;
  final String? activeEtablissementName;
  final String? activeEtablissementAddress;
  final String? activeEtablissementPhone;
  final String? activeEtablissementEmail;

  const DashboardStats({
    required this.students,
    required this.monthlyRevenue,
    required this.monthlyExpenses,
    this.monthlyExpensesPending = 0,
    required this.monthlyProfit,
    required this.monthlyAbsences,
    required this.classrooms,
    required this.teachers,
    this.activeEtablissementId,
    this.activeEtablissementName,
    this.activeEtablissementAddress,
    this.activeEtablissementPhone,
    this.activeEtablissementEmail,
  });
}

/// Un mois de l'année scolaire, tel que la caisse l'a vécu.
class MoisFinancier {
  final String mois;
  final String libelle;
  final double recettes;
  final double depenses;
  final double benefice;

  const MoisFinancier({
    required this.mois,
    required this.libelle,
    required this.recettes,
    required this.depenses,
    required this.benefice,
  });
}

/// Le rapport financier de l'année, mois par mois.
///
/// L'écran d'accueil traçait jusqu'ici une courbe fabriquée: trois points
/// obtenus en multipliant le montant du mois courant par des coefficients
/// écrits en dur, étiquetés « S-3, S-2, S-1 ». La direction lisait une
/// tendance qui n'existait pas.
class FinancesAnnuelles {
  final String academicYearName;
  final List<MoisFinancier> mois;
  final double totalRecettes;
  final double totalDepenses;
  final double benefice;

  const FinancesAnnuelles({
    this.academicYearName = '',
    this.mois = const [],
    this.totalRecettes = 0,
    this.totalDepenses = 0,
    this.benefice = 0,
  });

  bool get estVide => mois.isEmpty;
}
