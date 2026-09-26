/// Le public auquel une annonce s'adresse.
///
/// C'était un champ texte libre — « Audience (all, parents, teachers...) » —
/// que le serveur enregistrait sans jamais le lire. Une consigne écrite
/// « teachers » s'affichait donc chez les familles. Le serveur porte
/// désormais quatre publics fermés et filtre la liste selon le lecteur; cette
/// énumération est leur nom côté écran.
enum PublicDeLAnnonce {
  tous('all', 'Tout l\'établissement'),
  familles('families', 'Familles (parents et élèves)'),
  enseignants('teachers', 'Enseignants'),
  administration('staff', 'Administration');

  final String code;
  final String libelle;

  const PublicDeLAnnonce(this.code, this.libelle);

  /// Un code inconnu retombe sur « tout l'établissement ».
  ///
  /// C'est ce que faisaient de fait les anciennes annonces: faute de filtre,
  /// elles partaient à tout le monde quel que soit le texte saisi.
  static PublicDeLAnnonce depuisCode(String? code) {
    return PublicDeLAnnonce.values.firstWhere(
      (public) => public.code == code,
      orElse: () => PublicDeLAnnonce.tous,
    );
  }
}

class AnnonceItem {
  final int id;
  final String titre;
  final String message;
  final PublicDeLAnnonce public;
  final String publieeLe;
  final int? auteurId;

  const AnnonceItem({
    required this.id,
    required this.titre,
    required this.message,
    required this.public,
    required this.publieeLe,
    this.auteurId,
  });
}

enum CanalDeNotification {
  push('push', 'Push'),
  email('email', 'Email'),
  sms('sms', 'SMS');

  final String code;
  final String libelle;

  const CanalDeNotification(this.code, this.libelle);

  static CanalDeNotification depuisCode(String? code) {
    return CanalDeNotification.values.firstWhere(
      (canal) => canal.code == code,
      orElse: () => CanalDeNotification.push,
    );
  }
}

class NotificationItem {
  final int id;
  final String titre;
  final String message;
  final CanalDeNotification canal;
  final int? destinataireId;
  /// Le nom du destinataire, servi par le serveur.
  ///
  /// L'écran le résolvait sur l'annuaire qu'il gardait en mémoire: une
  /// notification adressée à quelqu'un absent de cette liste s'intitulait
  /// « Global » alors qu'elle avait bien un destinataire.
  final String destinataire;
  final bool envoyee;
  final String envoyeeLe;
  final String creeeLe;

  const NotificationItem({
    required this.id,
    required this.titre,
    required this.message,
    required this.canal,
    required this.destinataire,
    required this.envoyee,
    required this.envoyeeLe,
    required this.creeeLe,
    this.destinataireId,
  });

  /// Une notification sans destinataire s'adresse à tout l'établissement.
  bool get estGlobale => destinataireId == null;
}

class PasserelleSmsItem {
  final int id;
  final String fournisseur;
  final String urlApi;
  final String expediteur;
  final bool active;

  const PasserelleSmsItem({
    required this.id,
    required this.fournisseur,
    required this.urlApi,
    required this.expediteur,
    required this.active,
  });
}

class DestinataireItem {
  final int id;
  final String libelle;

  const DestinataireItem({required this.id, required this.libelle});
}
