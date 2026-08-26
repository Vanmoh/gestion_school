/// Un incident disciplinaire, tel que le backend le sert.
///
/// Le modele porte le cycle de vie complet -- declaration, sanction,
/// cloture -- la ou la page ne savait que creer: un incident ouvert le
/// restait indefiniment faute d'ecran pour le traiter.
class DisciplineIncident {
  final int id;
  final int studentId;
  final String studentFullName;
  final String studentMatricule;
  final String incidentDate;
  final String category;
  final String description;
  final String severity;
  final String sanction;
  final String status;
  final bool parentNotified;
  final String reportedByName;

  /// Libelle du motif, calcule par le serveur.
  ///
  /// Le referentiel vit dans le modele Django: en recopier les neuf libelles
  /// ici les aurait fait diverger des la premiere evolution.
  final String categoryLabel;

  /// Date de cloture, vide tant que l'incident est ouvert.
  final String resolvedAt;

  const DisciplineIncident({
    required this.id,
    required this.studentId,
    required this.incidentDate,
    required this.category,
    required this.description,
    this.studentFullName = '',
    this.studentMatricule = '',
    this.severity = 'medium',
    this.sanction = '',
    this.status = 'open',
    this.parentNotified = false,
    this.reportedByName = '',
    this.categoryLabel = '',
    this.resolvedAt = '',
  });

  factory DisciplineIncident.fromJson(Map<String, dynamic> json) {
    return DisciplineIncident(
      id: (json['id'] as num?)?.toInt() ?? 0,
      studentId: (json['student'] as num?)?.toInt() ?? 0,
      studentFullName: json['student_full_name']?.toString() ?? '',
      studentMatricule: json['student_matricule']?.toString() ?? '',
      incidentDate: json['incident_date']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'medium',
      sanction: json['sanction']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      parentNotified: json['parent_notified'] == true,
      reportedByName: json['reported_by_name']?.toString() ?? '',
      categoryLabel: json['category_label']?.toString() ?? '',
      resolvedAt: json['resolved_at']?.toString() ?? '',
    );
  }

  bool get estOuvert => status != 'resolved';

  /// Motif affichable: le libelle du serveur, a defaut le code brut.
  String get libelleMotif =>
      categoryLabel.isNotEmpty ? categoryLabel : (category.isEmpty ? 'Incident' : category);

  /// Jour de cloture, sans l'heure, vide tant que l'incident est ouvert.
  String get jourDeCloture =>
      resolvedAt.length >= 10 ? resolvedAt.substring(0, 10) : '';

  /// Date de l'incident pour le tri; une date absente ou illisible est
  /// repoussee en fin de liste plutot que d'interrompre le classement.
  DateTime get dateDeTri =>
      DateTime.tryParse(incidentDate) ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Libelle de l'eleve, avec repli sur l'identifiant.
  ///
  /// Le nom vient du serializer et non d'une jointure cote client: la page
  /// croisait la liste des eleves pour l'afficher, ce qui laissait « Élève »
  /// tout court des que l'eleve tombait hors de la premiere page.
  String get libelleEleve {
    final matricule = studentMatricule.isEmpty ? 'N/A' : studentMatricule;
    final nom = studentFullName.isEmpty ? 'Élève $studentId' : studentFullName;
    return '$matricule • $nom';
  }

  static String libelleGravite(String value) {
    switch (value) {
      case 'low':
        return 'Faible';
      case 'high':
        return 'Élevée';
      default:
        return 'Moyenne';
    }
  }

  static String libelleStatut(String value) {
    return value == 'resolved' ? 'Traité' : 'Ouvert';
  }
}

/// Un eleve tel qu'il apparait dans le selecteur de declaration.
///
/// Volontairement reduit aux trois champs affiches: la page n'a pas besoin
/// du dossier complet pour proposer un nom dans une liste deroulante.
class DisciplineStudentOption {
  final int id;
  final String fullName;
  final String matricule;

  const DisciplineStudentOption({
    required this.id,
    this.fullName = '',
    this.matricule = '',
  });

  factory DisciplineStudentOption.fromJson(Map<String, dynamic> json) {
    return DisciplineStudentOption(
      id: (json['id'] as num?)?.toInt() ?? 0,
      fullName: json['user_full_name']?.toString() ?? '',
      matricule: json['matricule']?.toString() ?? '',
    );
  }

  String get libelle {
    final code = matricule.isEmpty ? 'N/A' : matricule;
    final nom = fullName.isEmpty ? 'Élève $id' : fullName;
    return '$code • $nom';
  }
}

/// Un motif du referentiel, servi par le serveur.
class DisciplineCategoryOption {
  final String value;
  final String label;

  const DisciplineCategoryOption({required this.value, required this.label});

  factory DisciplineCategoryOption.fromJson(Map<String, dynamic> json) {
    return DisciplineCategoryOption(
      value: json['value']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
    );
  }
}
