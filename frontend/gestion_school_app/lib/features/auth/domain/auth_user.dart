class AuthUser {
  final int id;
  final String username;
  final String fullName;
  final String role;
  final int? etablissementId;
  final String etablissementName;

  /// Le mot de passe remis à l'inscription est provisoire: il suit une règle
  /// que l'école applique à tous, et l'identifiant est le matricule, imprimé
  /// sur la carte scolaire. Tant qu'il n'est pas remplacé, le serveur ne
  /// laisse passer que l'écran de changement.
  final bool doitChangerMotDePasse;

  const AuthUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.etablissementId,
    this.etablissementName = '',
    this.doitChangerMotDePasse = false,
  });

  String get homeRoute {
    switch (role) {
      case 'super_admin':
      case 'director':
      case 'promoter':
        return '/home/admin';
      case 'accountant':
        return '/home/accountant';
      case 'teacher':
        return '/home/teacher';
      case 'censor':
      case 'supervisor':
        return '/home/supervisor';
      case 'parent':
        return '/home/parent';
      case 'student':
        return '/home/student';
      default:
        return '/dashboard';
    }
  }
}
