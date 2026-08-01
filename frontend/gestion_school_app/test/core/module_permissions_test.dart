import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';

/// Charge utile representative de /auth/permissions/ pour un censeur.
Map<String, dynamic> _censorPayload() => {
  'role': 'censor',
  'role_label': 'Censeur',
  'modules': {
    'grades': {
      'label': 'Notes & Bulletins',
      'group': 'academique',
      'level': 'write',
      'read': true,
      'write': true,
      'delete': false,
      'scoped': false,
    },
    'students': {
      'label': 'Gestion des eleves',
      'group': 'pedagogie',
      'level': 'read',
      'read': true,
      'write': false,
      'delete': false,
      'scoped': false,
    },
    'finance': {
      'label': 'Finances',
      'group': 'finances',
      'level': 'none',
      'read': false,
      'write': false,
      'delete': false,
      'scoped': false,
    },
  },
  'paths': {
    'grades': ['/grades'],
    'students': ['/students', '/parents'],
    'finance': ['/payments', '/expenses'],
  },
};

void main() {
  group('lecture de la matrice', () {
    final permissions = ModulePermissions.fromJson(_censorPayload());

    test('les trois niveaux se lisent correctement', () {
      expect(permissions.canWrite('grades'), isTrue);
      expect(permissions.canDelete('grades'), isFalse);
      expect(permissions.isReadOnly('students'), isTrue);
      expect(permissions.canRead('finance'), isFalse);
    });

    test('un module inconnu est refuse, pas suppose ouvert', () {
      expect(permissions.canRead('module_qui_nexiste_pas'), isFalse);
      expect(permissions.canWrite('module_qui_nexiste_pas'), isFalse);
    });
  });

  group('rattachement d\'une ecriture a son module', () {
    final permissions = ModulePermissions.fromJson(_censorPayload());

    test('collection et element sont rattaches', () {
      expect(permissions.moduleGoverningWrite('/grades/'), 'grades');
      expect(permissions.moduleGoverningWrite('/grades/42/'), 'grades');
      expect(permissions.moduleGoverningWrite('/students/7'), 'students');
    });

    test('les sous-actions sont laissees au backend', () {
      // Ces routes portent leurs propres regles cote serveur (validation en
      // deux niveaux, feuille d'appel): le client ne doit pas les deviner.
      expect(
        permissions.moduleGoverningWrite('/payments/12/validate_level_one/'),
        isNull,
      );
      expect(
        permissions.moduleGoverningWrite('/grades/validation_status/'),
        isNull,
      );
    });

    test('un chemin hors matrice reste libre', () {
      expect(permissions.moduleGoverningWrite('/chat/messages/'), isNull);
    });
  });

  group('refus local des ecritures', () {
    setUp(() {
      ModulePermissionsRegistry.current = ModulePermissions.fromJson(
        _censorPayload(),
      );
    });

    tearDown(() {
      ModulePermissionsRegistry.current = ModulePermissions.empty;
    });

    test('la lecture passe toujours', () {
      expect(ModulePermissionsRegistry.refusalFor('GET', '/students/'), isNull);
    });

    test('une ecriture autorisee passe', () {
      expect(ModulePermissionsRegistry.refusalFor('POST', '/grades/'), isNull);
    });

    test('une ecriture sur un module en lecture seule est refusee', () {
      final refusal = ModulePermissionsRegistry.refusalFor(
        'POST',
        '/students/',
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('lecture seule'));
    });

    test('la suppression demande le niveau administration', () {
      final refusal = ModulePermissionsRegistry.refusalFor(
        'DELETE',
        '/grades/5/',
      );
      expect(refusal, isNotNull);
      expect(refusal, contains('administration'));
    });

    test('un module ferme refuse aussi', () {
      expect(
        ModulePermissionsRegistry.refusalFor('POST', '/payments/'),
        contains('non accessible'),
      );
    });

    test('sans matrice chargee, rien n\'est bloque localement', () {
      ModulePermissionsRegistry.current = ModulePermissions.empty;
      expect(ModulePermissionsRegistry.refusalFor('POST', '/grades/'), isNull);
    });
  });
}
