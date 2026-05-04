import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/auth/domain/auth_user.dart';

void main() {
  AuthUser makeUser(String role) {
    return AuthUser(
      id: 1,
      username: 'u',
      fullName: 'User Test',
      role: role,
      etablissementId: 1,
      etablissementName: 'Etab',
    );
  }

  group('AuthUser.homeRoute role mapping', () {
    test('maps direction roles to admin home', () {
      expect(makeUser('super_admin').homeRoute, '/home/admin');
      expect(makeUser('director').homeRoute, '/home/admin');
      expect(makeUser('promoter').homeRoute, '/home/admin');
    });

    test('maps censor and supervisor to supervisor home', () {
      expect(makeUser('censor').homeRoute, '/home/supervisor');
      expect(makeUser('supervisor').homeRoute, '/home/supervisor');
    });

    test('maps legacy functional roles', () {
      expect(makeUser('accountant').homeRoute, '/home/accountant');
      expect(makeUser('teacher').homeRoute, '/home/teacher');
      expect(makeUser('parent').homeRoute, '/home/parent');
      expect(makeUser('student').homeRoute, '/home/student');
    });

    test('falls back to dashboard for unknown roles', () {
      expect(makeUser('unknown').homeRoute, '/dashboard');
    });
  });
}
