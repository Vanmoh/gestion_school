import '../../../core/models/presence.dart';

/// Un compte, tel que l'administration le voit.
///
/// L'etat manquait entierement: ni actif, ni derniere connexion, ni date de
/// creation. On ne pouvait donc ni voir qui gardait un acces apres son
/// depart, ni reperer les comptes crees puis jamais utilises.
class UserAccount {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String roleLabel;
  final String phone;
  final int? etablissementId;
  final String etablissementName;

  /// Un compte desactive ne se connecte plus. C'est la facon de retirer un
  /// acces sans effacer ce que la personne a produit.
  final bool isActive;
  final DateTime? lastLogin;
  final DateTime? dateJoined;

  /// La derniere fois que le compte a donne signe de vie, et si c'est
  /// maintenant. `last_login` ne repond pas a cela: il date de l'ouverture de
  /// session, pas de la derniere action.
  final Presence presence;

  const UserAccount({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.phone,
    this.roleLabel = '',
    this.etablissementId,
    this.etablissementName = '',
    this.isActive = true,
    this.lastLogin,
    this.dateJoined,
    this.presence = const Presence(),
  });

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username']?.toString() ?? '',
      firstName: json['first_name']?.toString() ?? '',
      lastName: json['last_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      roleLabel: json['role_label']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      etablissementId: (json['etablissement'] as num?)?.toInt(),
      etablissementName: json['etablissement_name']?.toString() ?? '',
      // Absent d'un serveur anterieur: on suppose le compte ouvert plutot
      // que de l'afficher coupe a tort.
      isActive: json['is_active'] as bool? ?? true,
      lastLogin: DateTime.tryParse(
        json['last_login']?.toString() ?? '',
      )?.toLocal(),
      dateJoined: DateTime.tryParse(
        json['date_joined']?.toString() ?? '',
      )?.toLocal(),
      presence: Presence.depuisJson(json),
    );
  }

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? username : name;
  }

  /// Un compte cree puis oublie: c'est ce qu'on cherche en faisant le menage.
  ///
  /// Une connexion suffit a le sortir de cet etat, meme si l'ancien serveur
  /// n'ecrivait pas `last_login`: la presence, elle, l'a vu passer.
  bool get jamaisConnecte => lastLogin == null && presence.jamaisVue;

  /// Vrai tant que la personne donne signe de vie.
  bool get enLigne => presence.enLigne();

  /// « En ligne », « Vu hier à 08:05 », « Jamais connecté »: l'etat du compte
  /// en une ligne, celle que l'administration lit.
  String get etatDeConnexion {
    if (enLigne) return 'En ligne';
    final quand = presence.vuA ?? lastLogin;
    if (quand == null) return 'Jamais connecté';
    return 'Vu ${dateHeureLisible(quand)}';
  }

  /// « il y a 3 jours », « jamais connecté ».
  String get derniereActivite {
    if (enLigne) return 'En ligne';
    final quand = _derniereTrace;
    if (quand == null) return 'Jamais connecté';

    final ecart = DateTime.now().difference(quand);
    if (ecart.inMinutes < 60) return 'Il y a moins d’une heure';
    if (ecart.inHours < 24) return 'Il y a ${ecart.inHours} h';
    if (ecart.inDays == 1) return 'Hier';
    if (ecart.inDays < 30) return 'Il y a ${ecart.inDays} jours';
    if (ecart.inDays < 365) return 'Il y a ${(ecart.inDays / 30).round()} mois';
    return 'Il y a plus d’un an';
  }

  /// Le plus recent des deux repères: la derniere activite si on l'a, sinon
  /// l'ouverture de session.
  DateTime? get _derniereTrace {
    final vuA = presence.vuA;
    final connexion = lastLogin;
    if (vuA == null) return connexion;
    if (connexion == null) return vuA;
    return vuA.isAfter(connexion) ? vuA : connexion;
  }
}
