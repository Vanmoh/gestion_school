/// Ce que le serveur dit d'un bulletin a envoyer a une famille.
///
/// Deux objets et non un seul: consulter l'etat d'une classe n'engage rien,
/// preparer un envoi ouvre une ligne d'historique et fabrique un lien. Les
/// confondre ferait creer une trace a chaque fois qu'un ecran s'affiche.
library;

/// L'etat d'un eleve avant tout envoi: joignable, ou bloque et pourquoi.
class BulletinWhatsAppEtat {
  final int studentId;
  final String studentName;
  final String matricule;
  final String classroomName;
  final int? parentId;
  final String parentName;
  final bool parentConsent;
  final String phone;
  final bool canSend;

  /// Vide quand l'envoi est possible. Sinon la phrase a afficher telle
  /// quelle: le serveur la redige, l'ecran ne la reformule pas -- deux
  /// formulations pour un meme refus finiraient par diverger.
  final String blockedReason;

  final String lastStatus;
  final DateTime? lastSentAt;
  final bool alreadySent;

  const BulletinWhatsAppEtat({
    required this.studentId,
    this.studentName = '',
    this.matricule = '',
    this.classroomName = '',
    this.parentId,
    this.parentName = '',
    this.parentConsent = false,
    this.phone = '',
    this.canSend = false,
    this.blockedReason = '',
    this.lastStatus = '',
    this.lastSentAt,
    this.alreadySent = false,
  });

  factory BulletinWhatsAppEtat.fromMap(Map<String, dynamic> map) {
    return BulletinWhatsAppEtat(
      studentId: _asInt(map['student_id']) ?? 0,
      studentName: map['student_name']?.toString() ?? '',
      matricule: map['matricule']?.toString() ?? '',
      classroomName: map['classroom_name']?.toString() ?? '',
      parentId: _asInt(map['parent_id']),
      parentName: map['parent_name']?.toString() ?? '',
      parentConsent: map['parent_consent'] == true,
      phone: map['phone']?.toString() ?? '',
      canSend: map['can_send'] == true,
      blockedReason: map['blocked_reason']?.toString() ?? '',
      lastStatus: map['last_status']?.toString() ?? '',
      lastSentAt: _asDate(map['last_sent_at']),
      alreadySent: map['already_sent'] == true,
    );
  }
}

/// Un envoi prepare: le lien a ouvrir, et la trace a laquelle rendre compte.
class BulletinWhatsAppEnvoi {
  final int deliveryId;
  final int studentId;
  final String studentName;
  final String phone;

  /// Lien `wa.me` qui ouvre WhatsApp avec le message deja ecrit.
  final String whatsappUrl;

  final String message;
  final String downloadUrl;
  final DateTime? expiresAt;

  const BulletinWhatsAppEnvoi({
    required this.deliveryId,
    required this.studentId,
    this.studentName = '',
    this.phone = '',
    this.whatsappUrl = '',
    this.message = '',
    this.downloadUrl = '',
    this.expiresAt,
  });

  factory BulletinWhatsAppEnvoi.fromMap(Map<String, dynamic> map) {
    return BulletinWhatsAppEnvoi(
      deliveryId: _asInt(map['delivery_id']) ?? 0,
      studentId: _asInt(map['student_id']) ?? 0,
      studentName: map['student_name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      whatsappUrl: map['whatsapp_url']?.toString() ?? '',
      message: map['message']?.toString() ?? '',
      downloadUrl: map['download_url']?.toString() ?? '',
      expiresAt: _asDate(map['expires_at']),
    );
  }
}

/// Un eleve que la preparation a laisse de cote, avec son motif.
class BulletinWhatsAppIgnore {
  final int studentId;
  final String studentName;
  final String reason;
  final bool alreadySent;

  const BulletinWhatsAppIgnore({
    required this.studentId,
    this.studentName = '',
    this.reason = '',
    this.alreadySent = false,
  });

  factory BulletinWhatsAppIgnore.fromMap(Map<String, dynamic> map) {
    return BulletinWhatsAppIgnore(
      studentId: _asInt(map['student_id']) ?? 0,
      studentName: map['student_name']?.toString() ?? '',
      reason: map['reason']?.toString() ?? '',
      alreadySent: map['already_sent'] == true,
    );
  }
}

/// Le resultat d'une preparation de classe: ce qui part, ce qui ne part pas.
class BulletinWhatsAppLot {
  final String classroomName;
  final String term;
  final String academicYear;
  final List<BulletinWhatsAppEnvoi> prepares;
  final List<BulletinWhatsAppIgnore> ignores;

  const BulletinWhatsAppLot({
    this.classroomName = '',
    this.term = '',
    this.academicYear = '',
    this.prepares = const [],
    this.ignores = const [],
  });

  factory BulletinWhatsAppLot.fromMap(Map<String, dynamic> map) {
    return BulletinWhatsAppLot(
      classroomName: map['classroom_name']?.toString() ?? '',
      term: map['term']?.toString() ?? '',
      academicYear: map['academic_year']?.toString() ?? '',
      prepares: _rows(map['prepared'])
          .map(BulletinWhatsAppEnvoi.fromMap)
          .toList(),
      ignores: _rows(map['skipped'])
          .map(BulletinWhatsAppIgnore.fromMap)
          .toList(),
    );
  }
}

/// L'etat d'une classe entiere, avant toute preparation.
class BulletinWhatsAppClasse {
  final String classroomName;
  final String term;
  final String academicYear;
  final int readyCount;
  final int blockedCount;
  final List<BulletinWhatsAppEtat> eleves;

  const BulletinWhatsAppClasse({
    this.classroomName = '',
    this.term = '',
    this.academicYear = '',
    this.readyCount = 0,
    this.blockedCount = 0,
    this.eleves = const [],
  });

  factory BulletinWhatsAppClasse.fromMap(Map<String, dynamic> map) {
    return BulletinWhatsAppClasse(
      classroomName: map['classroom_name']?.toString() ?? '',
      term: map['term']?.toString() ?? '',
      academicYear: map['academic_year']?.toString() ?? '',
      readyCount: _asInt(map['ready_count']) ?? 0,
      blockedCount: _asInt(map['blocked_count']) ?? 0,
      eleves: _rows(map['students']).map(BulletinWhatsAppEtat.fromMap).toList(),
    );
  }
}

List<Map<String, dynamic>> _rows(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _asDate(dynamic value) {
  final texte = value?.toString() ?? '';
  if (texte.isEmpty) return null;
  return DateTime.tryParse(texte)?.toLocal();
}
