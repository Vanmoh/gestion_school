class AuthUser {
  final int id;
  final String username;
  final String fullName;
  final String role;

  const AuthUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });

  String get homeRoute {
    switch (role) {
      case 'super_admin':
      case 'director':
        return '/home/admin';
      case 'accountant':
        return '/home/accountant';
      case 'teacher':
        return '/home/teacher';
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
