import 'package:dio/dio.dart';

import '../domain/bulletin_whatsapp.dart';

/// Envoi des bulletins aux familles par WhatsApp.
///
/// Le serveur fabrique le lien `wa.me` et le texte du message; cette classe
/// ne fait que les transporter. Rien du contenu envoye aux familles n'est
/// redige ici: deux formulations, l'une dans l'application et l'autre dans
/// l'API, divergeraient des la premiere correction.
class BulletinWhatsAppRepository {
  final Dio dio;
  BulletinWhatsAppRepository(this.dio);

  /// Levee quand le bulletin est deja parti et que l'ecole n'a pas confirme.
  static const int codeDejaEnvoye = 409;

  String _urlEleve(int studentId, int academicYearId, String term) =>
      '/reports/bulletin/$studentId/$academicYearId/$term/whatsapp/';

  String _urlClasse(int classroomId, int academicYearId, String term) =>
      '/reports/bulletins/class/$classroomId/$academicYearId/$term/whatsapp/';

  /// Ce qui empeche ou permet l'envoi, sans rien preparer.
  Future<BulletinWhatsAppEtat> etatEleve({
    required int studentId,
    required int academicYearId,
    required String term,
  }) async {
    final response = await dio.get(_urlEleve(studentId, academicYearId, term));
    return BulletinWhatsAppEtat.fromMap(_map(response.data));
  }

  /// L'etat de toute une classe: qui est joignable, qui a deja recu.
  Future<BulletinWhatsAppClasse> etatClasse({
    required int classroomId,
    required int academicYearId,
    required String term,
  }) async {
    final response = await dio.get(
      _urlClasse(classroomId, academicYearId, term),
    );
    return BulletinWhatsAppClasse.fromMap(_map(response.data));
  }

  /// Prepare l'envoi d'un eleve et rend le lien a ouvrir.
  ///
  /// [forcer] rejoue un envoi deja parti. Sans lui, le serveur repond 409 et
  /// l'ecran demande confirmation: une classe reprise le lendemain ne doit
  /// pas renvoyer trente fois le meme bulletin.
  Future<BulletinWhatsAppEnvoi> preparerEleve({
    required int studentId,
    required int academicYearId,
    required String term,
    bool forcer = false,
  }) async {
    final response = await dio.post(
      _urlEleve(studentId, academicYearId, term),
      data: {'force': forcer},
    );
    return BulletinWhatsAppEnvoi.fromMap(_map(response.data));
  }

  /// Prepare les envois d'une classe, ou des seuls eleves demandes.
  Future<BulletinWhatsAppLot> preparerClasse({
    required int classroomId,
    required int academicYearId,
    required String term,
    List<int> studentIds = const [],
    bool forcer = false,
  }) async {
    final response = await dio.post(
      _urlClasse(classroomId, academicYearId, term),
      data: {
        'force': forcer,
        if (studentIds.isNotEmpty) 'student_ids': studentIds,
      },
    );
    return BulletinWhatsAppLot.fromMap(_map(response.data));
  }

  /// Declare qu'un envoi prepare est parti, ou pourquoi il ne l'est pas.
  ///
  /// C'est une declaration de l'ecole et non un accuse de reception: sur le
  /// canal assiste, le serveur ne voit pas le message partir. L'ecran doit
  /// le presenter ainsi.
  Future<void> marquerEnvoye(int deliveryId, {String motifEchec = ''}) async {
    await dio.post(
      '/reports/bulletin-deliveries/$deliveryId/sent/',
      data: {if (motifEchec.trim().isNotEmpty) 'failure_reason': motifEchec.trim()},
    );
  }

  /// Corrige le numero WhatsApp d'un parent et son accord.
  ///
  /// Depuis l'ecran d'envoi, et non depuis un autre module: un numero absent
  /// est la moitie des lignes bloquees, et renvoyer l'utilisateur ailleurs
  /// pour le saisir fait abandonner l'envoi en cours.
  ///
  /// Le numero part tel qu'il a ete tape (« 76 12 34 56 »): c'est le serveur
  /// qui le met au format international, seul endroit ou cette regle vit.
  Future<void> enregistrerContactParent({
    required int parentId,
    required String numero,
    required bool consentement,
  }) async {
    await dio.patch(
      '/parents/$parentId/',
      data: {
        'whatsapp_phone': numero.trim(),
        'whatsapp_consent': consentement,
      },
    );
  }

  Map<String, dynamic> _map(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
}

/// Le message que le serveur renvoie avec un refus, ou un texte de repli.
///
/// DRF place le motif sous « detail »; sans cette lecture, l'ecran affichait
/// la representation brute de l'exception Dio -- un pave technique la ou il
/// fallait dire « le parent n'a pas donne son accord ».
String messageDErreur(Object error, {String parDefaut = 'Envoi impossible.'}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] != null) {
      return data['detail'].toString();
    }
  }
  return parDefaut;
}

/// Le code HTTP d'un refus, quand il y en a un.
///
/// Sert a distinguer « deja envoye » (409, qui se confirme) d'un vrai echec:
/// sans lui, l'ecran traitait les deux de la meme facon et l'ecole ne
/// pouvait plus renvoyer un bulletin perdu par une famille.
int? codeHttp(Object error) {
  if (error is DioException) return error.response?.statusCode;
  return null;
}

/// Le corps de la reponse de refus, pour y lire les erreurs de champ.
dynamic donneesDErreur(Object error) {
  if (error is DioException) return error.response?.data;
  return null;
}
