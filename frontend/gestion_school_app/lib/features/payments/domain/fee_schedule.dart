/// Un barème de frais: ce que chaque élève d'une classe devra payer.
///
/// Sans lui, ouvrir une année voulait dire créer les frais un par un —
/// cinq mille saisies pour une école de cinq cents élèves avec une
/// inscription et neuf mensualités.
class FeeSchedule {
  final int id;
  final int academicYearId;

  /// Vide: le barème s'applique à toutes les classes de l'année.
  final int? classroomId;
  final String classroomName;
  final String feeType;
  final String feeTypeDisplay;
  final String label;
  final double amount;
  final String firstDueDate;

  /// 1 pour un frais unique (l'inscription), 9 pour neuf mensualités.
  final int occurrences;
  final List<String> echeances;
  final double montantTotal;
  final int elevesConcernes;
  final int fraisGeneres;

  const FeeSchedule({
    required this.id,
    required this.academicYearId,
    this.classroomId,
    this.classroomName = '',
    required this.feeType,
    this.feeTypeDisplay = '',
    this.label = '',
    required this.amount,
    required this.firstDueDate,
    this.occurrences = 1,
    this.echeances = const [],
    this.montantTotal = 0,
    this.elevesConcernes = 0,
    this.fraisGeneres = 0,
  });

  /// Vrai quand le barème n'a encore produit aucun frais.
  bool get jamaisApplique => fraisGeneres == 0;
}

/// Ce qu'une application produirait, avant de l'écrire.
///
/// Un barème mal saisi multiplie son erreur par le nombre d'échéances et par
/// la classe entière: il doit pouvoir se relire avant d'être posé.
class FeeScheduleApercu {
  final int elevesConcernes;
  final List<String> echeances;
  final double montantParEcheance;
  final double montantParEleve;
  final double montantTotal;
  final int fraisDejaGeneres;
  final int fraisACreer;

  const FeeScheduleApercu({
    required this.elevesConcernes,
    required this.echeances,
    required this.montantParEcheance,
    required this.montantParEleve,
    required this.montantTotal,
    required this.fraisDejaGeneres,
    required this.fraisACreer,
  });
}
