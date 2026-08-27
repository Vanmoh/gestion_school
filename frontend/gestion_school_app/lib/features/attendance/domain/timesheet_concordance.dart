/// Le rapprochement entre l'emploi du temps et l'emargement enseignant.
///
/// Les deux modules vivaient cote a cote sans se regarder: une seance que
/// personne n'assurait ne remontait nulle part, et un pointage n'indiquait
/// pas a quel cours il correspondait. Ces objets portent la reponse du
/// serveur, qui seul connait les creneaux reellement couverts.
class ConcordanceTotals {
  final int plannedMinutes;
  final int coveredMinutes;
  final int gapMinutes;
  final int sessionsPlanned;
  final int sessionsAssured;
  final int sessionsPartial;
  final int sessionsMissed;
  final int offScheduleEntries;

  const ConcordanceTotals({
    this.plannedMinutes = 0,
    this.coveredMinutes = 0,
    this.gapMinutes = 0,
    this.sessionsPlanned = 0,
    this.sessionsAssured = 0,
    this.sessionsPartial = 0,
    this.sessionsMissed = 0,
    this.offScheduleEntries = 0,
  });

  factory ConcordanceTotals.fromJson(Map<String, dynamic> json) {
    int lire(String cle) => (json[cle] as num?)?.toInt() ?? 0;
    return ConcordanceTotals(
      plannedMinutes: lire('planned_minutes'),
      coveredMinutes: lire('covered_minutes'),
      gapMinutes: lire('gap_minutes'),
      sessionsPlanned: lire('sessions_planned'),
      sessionsAssured: lire('sessions_assured'),
      sessionsPartial: lire('sessions_partial'),
      sessionsMissed: lire('sessions_missed'),
      offScheduleEntries: lire('off_schedule_entries'),
    );
  }

  /// Part des seances assurees, de 0 a 1. Null quand rien n'etait planifie:
  /// « 0 % » sur une journee sans cours se lirait comme un manquement.
  double? get tauxAssure {
    if (sessionsPlanned <= 0) return null;
    return sessionsAssured / sessionsPlanned;
  }

  String get heuresPlanifiees => _heures(plannedMinutes);
  String get heuresAssurees => _heures(coveredMinutes);
  String get heuresManquantes => _heures(gapMinutes);

  static String _heures(int minutes) {
    if (minutes <= 0) return '0 h';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m';
  }
}

/// L'etat d'une seance planifiee, tel que le serveur l'a tranche.
enum ConcordanceStatus { assured, partial, missed }

class ConcordanceSession {
  final int slotId;
  final String subjectName;
  final String classroomName;
  final String room;
  final String startTime;
  final String endTime;
  final int plannedMinutes;
  final int coveredMinutes;
  final int lateMinutes;
  final ConcordanceStatus status;

  const ConcordanceSession({
    required this.slotId,
    required this.subjectName,
    required this.classroomName,
    required this.room,
    required this.startTime,
    required this.endTime,
    required this.plannedMinutes,
    required this.coveredMinutes,
    required this.lateMinutes,
    required this.status,
  });

  factory ConcordanceSession.fromJson(Map<String, dynamic> json) {
    return ConcordanceSession(
      slotId: (json['slot'] as num?)?.toInt() ?? 0,
      subjectName: json['subject_name']?.toString() ?? '',
      classroomName: json['classroom_name']?.toString() ?? '',
      room: json['room']?.toString() ?? '',
      startTime: json['start_time']?.toString() ?? '',
      endTime: json['end_time']?.toString() ?? '',
      plannedMinutes: (json['planned_minutes'] as num?)?.toInt() ?? 0,
      coveredMinutes: (json['covered_minutes'] as num?)?.toInt() ?? 0,
      lateMinutes: (json['late_minutes'] as num?)?.toInt() ?? 0,
      status: switch (json['status']?.toString()) {
        'assured' => ConcordanceStatus.assured,
        'partial' => ConcordanceStatus.partial,
        // Le statut inconnu se lit comme une seance manquee: mieux vaut
        // signaler a tort que taire un cours que personne n'a assure.
        _ => ConcordanceStatus.missed,
      },
    );
  }

  String get creneau => '$startTime – $endTime';
  String get intitule => '$subjectName • $classroomName';
}

/// Un pointage, vu depuis le rapprochement.
class ConcordanceEntry {
  final int id;
  final String checkInTime;
  final String? checkOutTime;
  final bool isAutoClosed;
  final bool isOffSchedule;
  final String offScheduleReason;
  final String workedHours;

  const ConcordanceEntry({
    required this.id,
    required this.checkInTime,
    required this.checkOutTime,
    required this.isAutoClosed,
    required this.isOffSchedule,
    required this.offScheduleReason,
    required this.workedHours,
  });

  factory ConcordanceEntry.fromJson(Map<String, dynamic> json) {
    return ConcordanceEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      checkInTime: json['check_in_time']?.toString() ?? '',
      checkOutTime: json['check_out_time']?.toString(),
      isAutoClosed: json['is_auto_closed'] == true,
      isOffSchedule: json['is_off_schedule'] == true,
      offScheduleReason: json['off_schedule_reason']?.toString() ?? '',
      workedHours: json['worked_hours']?.toString() ?? '0',
    );
  }
}

class ConcordanceDay {
  final DateTime? date;
  final String weekday;
  final List<ConcordanceSession> sessions;
  final List<ConcordanceEntry> entries;
  final ConcordanceTotals totals;

  const ConcordanceDay({
    required this.date,
    required this.weekday,
    required this.sessions,
    required this.entries,
    required this.totals,
  });

  factory ConcordanceDay.fromJson(Map<String, dynamic> json) {
    return ConcordanceDay(
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      weekday: json['weekday']?.toString() ?? '',
      sessions: _liste(json['sessions'], ConcordanceSession.fromJson),
      entries: _liste(json['entries'], ConcordanceEntry.fromJson),
      totals: ConcordanceTotals.fromJson(
        Map<String, dynamic>.from(json['totals'] as Map? ?? const {}),
      ),
    );
  }
}

class ConcordanceTeacher {
  final int teacherId;
  final String fullName;
  final String employeeCode;
  final ConcordanceTotals totals;
  final List<ConcordanceDay> days;

  const ConcordanceTeacher({
    required this.teacherId,
    required this.fullName,
    required this.employeeCode,
    required this.totals,
    required this.days,
  });

  factory ConcordanceTeacher.fromJson(Map<String, dynamic> json) {
    return ConcordanceTeacher(
      teacherId: (json['teacher'] as num?)?.toInt() ?? 0,
      fullName: json['teacher_full_name']?.toString() ?? '',
      employeeCode: json['teacher_employee_code']?.toString() ?? '',
      totals: ConcordanceTotals.fromJson(
        Map<String, dynamic>.from(json['totals'] as Map? ?? const {}),
      ),
      days: _liste(json['days'], ConcordanceDay.fromJson),
    );
  }
}

class TimesheetConcordance {
  final DateTime? from;
  final DateTime? to;
  final ConcordanceTotals totals;
  final List<ConcordanceTeacher> teachers;

  const TimesheetConcordance({
    required this.from,
    required this.to,
    required this.totals,
    required this.teachers,
  });

  factory TimesheetConcordance.fromJson(Map<String, dynamic> json) {
    return TimesheetConcordance(
      from: DateTime.tryParse(json['from']?.toString() ?? ''),
      to: DateTime.tryParse(json['to']?.toString() ?? ''),
      totals: ConcordanceTotals.fromJson(
        Map<String, dynamic>.from(json['totals'] as Map? ?? const {}),
      ),
      teachers: _liste(json['teachers'], ConcordanceTeacher.fromJson),
    );
  }

  static const vide = TimesheetConcordance(
    from: null,
    to: null,
    totals: ConcordanceTotals(),
    teachers: [],
  );
}

List<T> _liste<T>(dynamic brut, T Function(Map<String, dynamic>) depuis) {
  if (brut is! List) return const [];
  return brut
      .whereType<Map>()
      .map((ligne) => depuis(Map<String, dynamic>.from(ligne)))
      .toList(growable: false);
}
