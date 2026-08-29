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
      lastLogin: DateTime.tryParse(json['last_login']?.toString() ?? ''),
      dateJoined: DateTime.tryParse(json['date_joined']?.toString() ?? ''),
    );
  }

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? username : name;
  }

  /// Un compte cree puis oublie: c'est ce qu'on cherche en faisant le menage.
  bool get jamaisConnecte => lastLogin == null;

  /// « il y a 3 jours », « jamais connecté ».
  String get derniereActivite {
    final quand = lastLogin;
    if (quand == null) return 'Jamais connecté';

    final ecart = DateTime.now().difference(quand);
    if (ecart.inMinutes < 60) return 'Il y a moins d’une heure';
    if (ecart.inHours < 24) return 'Il y a ${ecart.inHours} h';
    if (ecart.inDays == 1) return 'Hier';
    if (ecart.inDays < 30) return 'Il y a ${ecart.inDays} jours';
    if (ecart.inDays < 365) return 'Il y a ${(ecart.inDays / 30).round()} mois';
    return 'Il y a plus d’un an';
  }
}
