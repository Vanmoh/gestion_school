/// Ce qu'un enseignant declare pouvoir assurer, avant que le planning existe.
///
/// Trois etats et non deux: une collecte sert justement a recueillir la
/// nuance. « Je peux, mais j'aimerais autant pas » n'est ni un refus ni un
/// volontariat, et l'ecraser dans un booleen fait perdre a l'administration
/// ce qui lui permet d'arbitrer entre deux enseignants egalement libres.
enum AvailabilityKind {
  preferred('preferred', 'Préférée'),
  possible('possible', 'Possible'),
  unavailable('unavailable', 'Indisponible');

  final String code;
  final String libelle;

  const AvailabilityKind(this.code, this.libelle);

  static AvailabilityKind? depuis(String? code) {
    for (final valeur in AvailabilityKind.values) {
      if (valeur.code == code) return valeur;
    }
    return null;
  }

  /// L'etat suivant quand on clique une case: préférée → possible →
  /// indisponible → rien. Le tour complet permet de corriger sans avoir a
  /// chercher un menu.
  AvailabilityKind? get suivant => switch (this) {
    AvailabilityKind.preferred => AvailabilityKind.possible,
    AvailabilityKind.possible => AvailabilityKind.unavailable,
    AvailabilityKind.unavailable => null,
  };
}

/// Une case de la grille hebdomadaire.
///
/// Elle porte les deux lectures dont les deux ecrans ont besoin: le compte
/// par etat, pour l'administration qui arbitre, et ce que l'enseignant vise
/// a declare, pour lui.
class AvailabilityCell {
  final String dayOfWeek;
  final String dayLabel;
  final String startTime;
  final String endTime;
  final int preferredCount;
  final int possibleCount;
  final int unavailableCount;
  final List<AvailabilityDeclarant> teachers;

  /// L'etat declare par l'enseignant vise, ou null s'il n'a rien dit.
  final AvailabilityKind? mine;
  final int? mineId;

  /// Vrai quand la declaration epouse exactement cette case. Une plage plus
  /// large la couvre aussi, mais la modifier depuis cette case reviendrait a
  /// decouper la declaration d'origine.
  final bool mineExact;

  const AvailabilityCell({
    required this.dayOfWeek,
    required this.dayLabel,
    required this.startTime,
    required this.endTime,
    required this.preferredCount,
    required this.possibleCount,
    required this.unavailableCount,
    required this.teachers,
    required this.mine,
    required this.mineId,
    required this.mineExact,
  });

  factory AvailabilityCell.fromJson(Map<String, dynamic> json) {
    int lire(String cle) => (json[cle] as num?)?.toInt() ?? 0;
    final brutes = json['teachers'];
    return AvailabilityCell(
      dayOfWeek: json['day_of_week']?.toString() ?? '',
      dayLabel: json['day_label']?.toString() ?? '',
      startTime: _hhmm(json['start_time']?.toString() ?? ''),
      endTime: _hhmm(json['end_time']?.toString() ?? ''),
      preferredCount: lire('preferred_count'),
      possibleCount: lire('possible_count'),
      unavailableCount: lire('unavailable_count'),
      teachers: brutes is List
          ? brutes
                .whereType<Map>()
                .map((l) => AvailabilityDeclarant.fromJson(Map<String, dynamic>.from(l)))
                .toList(growable: false)
          : const [],
      mine: AvailabilityKind.depuis(json['mine']?.toString()),
      mineId: (json['mine_id'] as num?)?.toInt(),
      mineExact: json['mine_exact'] == true,
    );
  }

  /// Enseignants qui se disent prenables sur cette case.
  int get ouverts => preferredCount + possibleCount;

  String get creneau => '$startTime – $endTime';
}

class AvailabilityDeclarant {
  final int teacherId;
  final String name;
  final AvailabilityKind? kind;

  const AvailabilityDeclarant({
    required this.teacherId,
    required this.name,
    required this.kind,
  });

  factory AvailabilityDeclarant.fromJson(Map<String, dynamic> json) {
    return AvailabilityDeclarant(
      teacherId: (json['teacher'] as num?)?.toInt() ?? 0,
      name: json['teacher_name']?.toString() ?? '',
      kind: AvailabilityKind.depuis(json['kind']?.toString()),
    );
  }
}

class AvailabilityDay {
  final String dayOfWeek;
  final String dayLabel;
  final List<AvailabilityCell> cells;

  const AvailabilityDay({
    required this.dayOfWeek,
    required this.dayLabel,
    required this.cells,
  });

  factory AvailabilityDay.fromJson(Map<String, dynamic> json) {
    final brutes = json['cells'];
    return AvailabilityDay(
      dayOfWeek: json['day_of_week']?.toString() ?? '',
      dayLabel: json['day_label']?.toString() ?? '',
      cells: brutes is List
          ? brutes
                .whereType<Map>()
                .map((l) => AvailabilityCell.fromJson(Map<String, dynamic>.from(l)))
                .toList(growable: false)
          : const [],
    );
  }
}

class AvailabilityGrid {
  final int startHour;
  final int endHour;
  final int slotMinutes;
  final int? teacherId;
  final List<AvailabilityDay> days;

  const AvailabilityGrid({
    required this.startHour,
    required this.endHour,
    required this.slotMinutes,
    required this.teacherId,
    required this.days,
  });

  factory AvailabilityGrid.fromJson(Map<String, dynamic> json) {
    final brutes = json['days'];
    return AvailabilityGrid(
      startHour: (json['start_hour'] as num?)?.toInt() ?? 7,
      endHour: (json['end_hour'] as num?)?.toInt() ?? 18,
      slotMinutes: (json['slot_minutes'] as num?)?.toInt() ?? 60,
      teacherId: (json['teacher'] as num?)?.toInt(),
      days: brutes is List
          ? brutes
                .whereType<Map>()
                .map((l) => AvailabilityDay.fromJson(Map<String, dynamic>.from(l)))
                .toList(growable: false)
          : const [],
    );
  }

  static const vide = AvailabilityGrid(
    startHour: 7,
    endHour: 18,
    slotMinutes: 60,
    teacherId: null,
    days: [],
  );

  /// Les plages horaires, prises sur le premier jour: toutes les colonnes
  /// partagent la meme decoupe.
  List<String> get creneaux {
    if (days.isEmpty) return const [];
    return days.first.cells.map((cell) => cell.creneau).toList(growable: false);
  }
}

/// La campagne qui encadre la collecte.
class AvailabilityCampaign {
  final int id;
  final String label;
  final String academicYearName;
  final DateTime? opensOn;
  final DateTime? closesOn;
  final String status;
  final String statusLabel;
  final bool isOpen;
  final String instructions;
  final int teachersTotal;
  final int teachersAnswered;

  const AvailabilityCampaign({
    required this.id,
    required this.label,
    required this.academicYearName,
    required this.opensOn,
    required this.closesOn,
    required this.status,
    required this.statusLabel,
    required this.isOpen,
    required this.instructions,
    required this.teachersTotal,
    required this.teachersAnswered,
  });

  factory AvailabilityCampaign.fromJson(Map<String, dynamic> json) {
    return AvailabilityCampaign(
      id: (json['id'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
      academicYearName: json['academic_year_name']?.toString() ?? '',
      opensOn: DateTime.tryParse(json['opens_on']?.toString() ?? ''),
      closesOn: DateTime.tryParse(json['closes_on']?.toString() ?? ''),
      status: json['status']?.toString() ?? 'draft',
      statusLabel: json['status_label']?.toString() ?? '',
      isOpen: json['is_open'] == true,
      instructions: json['instructions']?.toString() ?? '',
      teachersTotal: (json['teachers_total'] as num?)?.toInt() ?? 0,
      teachersAnswered: (json['teachers_answered'] as num?)?.toInt() ?? 0,
    );
  }

  int get teachersMissing =>
      teachersTotal - teachersAnswered < 0 ? 0 : teachersTotal - teachersAnswered;

  /// Part de repondants, ou null quand l'ecole n'a aucun enseignant: « 0 % »
  /// se lirait alors comme un manquement.
  double? get tauxReponse {
    if (teachersTotal <= 0) return null;
    return teachersAnswered / teachersTotal;
  }

  int? get joursRestants {
    final fin = closesOn;
    if (fin == null) return null;
    final maintenant = DateTime.now();
    return fin.difference(DateTime(maintenant.year, maintenant.month, maintenant.day)).inDays;
  }
}

/// Une ligne du suivi des reponses.
class AvailabilityResponseRow {
  final int teacherId;
  final String name;
  final String employeeCode;
  final bool isSubmitted;
  final int slotsDeclared;
  final int reminderCount;

  const AvailabilityResponseRow({
    required this.teacherId,
    required this.name,
    required this.employeeCode,
    required this.isSubmitted,
    required this.slotsDeclared,
    required this.reminderCount,
  });

  factory AvailabilityResponseRow.fromJson(Map<String, dynamic> json) {
    return AvailabilityResponseRow(
      teacherId: (json['teacher'] as num?)?.toInt() ?? 0,
      name: json['teacher_name']?.toString() ?? '',
      employeeCode: json['teacher_employee_code']?.toString() ?? '',
      isSubmitted: json['is_submitted'] == true,
      slotsDeclared: (json['slots_declared'] as num?)?.toInt() ?? 0,
      reminderCount: (json['reminder_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// « 08:00:00 » -> « 08:00 ». Les secondes n'apprennent rien sur un créneau.
String _hhmm(String valeur) {
  final morceaux = valeur.split(':');
  if (morceaux.length < 2) return valeur;
  return '${morceaux[0]}:${morceaux[1]}';
}
