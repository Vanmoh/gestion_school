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

  /// Combien de ses épreuves sont ouvertes aux familles.
  ///
  /// Le booléen `resultatsPublies` ne gouverne plus que les notes qu'aucune
  /// épreuve ne porte : l'afficher tel quel dirait « publiée » devant trois
  /// épreuves ouvertes sur sept.
  final int epreuvesTotal;
  final int epreuvesPubliees;

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
    this.epreuvesTotal = 0,
    this.epreuvesPubliees = 0,
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

  /// Les libellés servis par le serveur. L'écran les résolvait sur ses
  /// propres caches, et une épreuve d'une classe absente du cache
  /// s'intitulait « Matière ».
  final String classroomName;
  final String subjectName;
  final String sessionTitle;

  /// Combien de copies sont corrigées. Rien ne distinguait une épreuve
  /// corrigée d'une épreuve en attente : la note ne se rattachait à aucune
  /// épreuve.
  final int resultatsSaisis;

  /// Vrai quand les familles lisent les notes de cette épreuve.
  ///
  /// La publication se décidait pour la campagne entière, alors que les
  /// copies reviennent classe par classe.
  final bool resultatsPublies;
  final String resultatsPubliesLe;

  const ExamPlanningItem({
    required this.id,
    required this.sessionId,
    required this.classroomId,
    required this.subjectId,
    required this.examDate,
    required this.startTime,
    required this.endTime,
    this.classroomName = '',
    this.subjectName = '',
    this.sessionTitle = '',
    this.resultatsSaisis = 0,
    this.resultatsPublies = false,
    this.resultatsPubliesLe = '',
  });

  /// Publier le vide ferait chercher aux familles des notes qui n'existent
  /// pas encore.
  bool get peutEtrePubliee => !resultatsPublies && resultatsSaisis > 0;

  /// L'épreuve telle qu'on la nomme au secrétariat.
  String get intitule {
    final classe = classroomName.trim().isEmpty ? 'Classe' : classroomName;
    final matiere = subjectName.trim().isEmpty ? 'Matière' : subjectName;
    return '$classe • $matiere';
  }
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

/// Ce que la suppression d'une campagne emporterait.
///
/// Ses épreuves, ses surveillances et toutes ses notes partent en cascade.
/// L'inventaire informe, il n'empêche pas : une école qui a créé une campagne
/// en double le jour de la rentrée doit pouvoir la défaire.
class InventaireDeSuppression {
  final String titre;
  final int epreuves;
  final int notes;
  final int surveillances;

  const InventaireDeSuppression({
    this.titre = '',
    this.epreuves = 0,
    this.notes = 0,
    this.surveillances = 0,
  });

  factory InventaireDeSuppression.fromJson(dynamic data) {
    if (data is! Map) return const InventaireDeSuppression();
    final deps = data['dependencies'];
    int compte(String cle) =>
        deps is Map ? (deps[cle] as num?)?.toInt() ?? 0 : 0;
    return InventaireDeSuppression(
      titre: data['title']?.toString() ?? '',
      epreuves: compte('exam_plannings'),
      notes: compte('exam_results'),
      surveillances: compte('exam_invigilations'),
    );
  }

  /// Vrai quand rien ne part avec elle : la question ne se pose pas.
  bool get estVide => epreuves == 0 && notes == 0 && surveillances == 0;

  /// Ce qui partirait, dit en clair et dans l'ordre de ce qui compte.
  ///
  /// Les notes d'abord : ce sont elles qui figurent sur des bulletins déjà
  /// imprimés.
  String get resume {
    final morceaux = <String>[
      if (notes > 0) '$notes note(s)',
      if (epreuves > 0) '$epreuves épreuve(s)',
      if (surveillances > 0) '$surveillances surveillance(s)',
    ];
    return morceaux.join(', ');
  }
}
