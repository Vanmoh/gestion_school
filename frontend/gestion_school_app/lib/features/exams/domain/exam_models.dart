class ExamSessionItem {
  final int id;
  final String title;
  final String term;
  final int academicYearId;
  final String startDate;
  final String endDate;

  /// Vrai quand les familles peuvent lire les notes de cette session.
  ///
  /// Elles les lisaient dès la saisie: un élève voyait passer une note avant
  /// que le jury ne l'ait arrêtée, et parfois une autre après correction.
  final bool resultatsPublies;
  final String resultatsPubliesLe;

  /// Combien de notes la session porte déjà. Publier une session vide ferait
  /// chercher aux familles des résultats qui n'existent pas.
  final int resultatsSaisis;

  const ExamSessionItem({
    required this.id,
    required this.title,
    required this.term,
    required this.academicYearId,
    required this.startDate,
    required this.endDate,
    this.resultatsPublies = false,
    this.resultatsPubliesLe = '',
    this.resultatsSaisis = 0,
  });

  bool get peutEtrePubliee => !resultatsPublies && resultatsSaisis > 0;
}

class ExamPlanningItem {
  final int id;
  final int sessionId;
  final int classroomId;
  final int subjectId;
  final String examDate;
  final String startTime;
  final String endTime;

  const ExamPlanningItem({
    required this.id,
    required this.sessionId,
    required this.classroomId,
    required this.subjectId,
    required this.examDate,
    required this.startTime,
    required this.endTime,
  });
}

class ExamResultItem {
  final int id;
  final int sessionId;
  final int studentId;
  final int subjectId;
  final double score;

  /// Les libellés servis par le serveur, plutôt que trois relations résolues
  /// ici. L'écran d'administration tient ses référentiels en cache et n'en a
  /// pas besoin ; celui de la famille aurait fait trois requêtes pour
  /// afficher « Mathématiques » à la place de « 7 ».
  final String subjectName;
  final String sessionTitle;
  final String sessionTerm;
  final String studentFullName;
  final String studentMatricule;

  const ExamResultItem({
    required this.id,
    required this.sessionId,
    required this.studentId,
    required this.subjectId,
    required this.score,
    this.subjectName = '',
    this.sessionTitle = '',
    this.sessionTerm = '',
    this.studentFullName = '',
    this.studentMatricule = '',
  });

  /// Le nom de la matière, ou de quoi ne pas afficher un identifiant nu.
  String get matiere => subjectName.trim().isEmpty ? 'Matière' : subjectName;

  /// L'épreuve telle qu'elle se nomme sur le bulletin.
  String get epreuve {
    final titre = sessionTitle.trim();
    final periode = sessionTerm.trim();
    if (titre.isEmpty) return periode.isEmpty ? 'Examen' : periode;
    return periode.isEmpty ? titre : '$titre • $periode';
  }
}

class ExamInvigilationItem {
  final int id;
  final int planningId;
  final int supervisorId;
  final String supervisorName;

  const ExamInvigilationItem({
    required this.id,
    required this.planningId,
    required this.supervisorId,
    required this.supervisorName,
  });
}

class OptionItem {
  final int id;
  final String label;
  final int? classroomId;

  const OptionItem({required this.id, required this.label, this.classroomId});
}
