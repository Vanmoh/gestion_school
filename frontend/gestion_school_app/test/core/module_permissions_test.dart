import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  // Le serveur sert toutes les capacites, y compris celles a false: le client
  // doit distinguer « refuse » de « inconnu de cette version ».
  'capabilities': {
    'validation_paie_niveau_1': true,
    'validation_paie_niveau_2': false,
    'annulation_validation_paie': false,
    'annulation_validation_depense': false,
    'saisie_conduite': true,
    'appel_attention': true,
    'exports_sensibles': false,
  },
};

void main() {
  group('porte d_entree de la coquille', _gateTests);

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

    test('les gestes affines se lisent a part des modules', () {
      // Le censeur ecrit dans la paie, mais n'y valide que le niveau 1: la
      // case « payroll: E » ne sait pas dire cette moitie-la.
      expect(permissions.can(Capacites.validationPaieNiveau1), isTrue);
      expect(permissions.can(Capacites.validationPaieNiveau2), isFalse);
      expect(permissions.can(Capacites.saisieConduite), isTrue);
      expect(permissions.can(Capacites.exportsSensibles), isFalse);
      expect(permissions.can(Capacites.appelAttention), isTrue);
      // Il signe le niveau 1, donc il ne defait pas sa propre signature.
      expect(permissions.can(Capacites.annulationValidationPaie), isFalse);
    });

    test('un geste inconnu est refuse, comme un module inconnu', () {
      // Une version du client plus recente que le serveur ne doit pas
      // afficher un bouton que celui-ci refusera.
      expect(permissions.can('geste_qui_nexiste_pas'), isFalse);
      expect(ModulePermissions.empty.can(Capacites.exportsSensibles), isFalse);
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

void _gateTests() {
  const empty = ModulePermissions.empty;
  final matrix = ModulePermissions.fromJson(_censorPayload());

  test('un echec l_emporte sur une matrice vide gardee en cache', () {
    // Regression: le provider rend d'abord `empty` (personne n'est connecte),
    // Riverpod garde cette valeur quand la requete suivante echoue. La coquille
    // s'affichait alors avec zero module et aucun message.
    final stale = const AsyncValue<ModulePermissions>.data(
      empty,
    ).copyWithPrevious(const AsyncValue.data(empty));
    final failed = AsyncValue<ModulePermissions>.error(
      Exception('404'),
      StackTrace.empty,
    ).copyWithPrevious(stale);

    expect(failed.hasValue, isTrue, reason: 'la valeur perimee reste presente');
    expect(
      permissionsGate(failed, hasVisibleModule: false),
      PermissionsGate.unavailable,
    );
  });

  test('matrice servie mais sans module: etat dedie, pas un menu vide', () {
    expect(
      permissionsGate(
        const AsyncValue.data(empty),
        hasVisibleModule: false,
      ),
      PermissionsGate.noModule,
    );
  });

  test('matrice servie avec des modules: la coquille se construit', () {
    expect(
      permissionsGate(AsyncValue.data(matrix), hasVisibleModule: true),
      PermissionsGate.ready,
    );
  });

  test('chargement initial: ni erreur ni menu', () {
    expect(
      permissionsGate(
        const AsyncValue<ModulePermissions>.loading(),
        hasVisibleModule: false,
      ),
      PermissionsGate.loading,
    );
  });
}
