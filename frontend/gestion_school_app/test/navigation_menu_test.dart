/// La barre latérale et ce qu'elle laisse atteindre.
///
/// Elle ne dessine que les groupes. Une entrée oubliée dans la table des
/// groupes existe, se construit, répond à son adresse — et reste introuvable.
/// C'est arrivé à « Dossier élève » : la matrice l'ouvre aux neuf rôles, elle
/// est la seule page montrant à une famille tout ce que l'école sait de son
/// enfant, et aucun menu n'y menait.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/app.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/auth/domain/auth_user.dart';

/// Les droits d'un profil, réduits à ce que le menu lit: la clé et le niveau.
ModulePermissions _droits(String role, Map<String, AccessLevel> niveaux) {
  return ModulePermissions(
    role: role,
    modules: {
      for (final entree in niveaux.entries)
        entree.key: ModulePermission(
          key: entree.key,
          label: entree.key,
          group: 'pedagogie',
          level: entree.value,
          scoped: true,
        ),
    },
  );
}

/// Ce que la matrice ouvre au parent et à l'élève, y compris le référentiel
/// scolaire — leurs écrans de notes, d'examens, d'emploi du temps et de frais
/// le chargent avant d'afficher quoi que ce soit.
ModulePermissions _famille(String role) => _droits(role, const {
  'dashboard': AccessLevel.read,
  'students': AccessLevel.read,
  'student_lookup': AccessLevel.read,
  'academics': AccessLevel.read,
  'grades': AccessLevel.read,
  'exams': AccessLevel.read,
  'timetable': AccessLevel.read,
  'finance': AccessLevel.read,
  'attendance': AccessLevel.read,
  'discipline': AccessLevel.read,
  'reports': AccessLevel.read,
});

void main() {
  _nomAffiche();

  test('aucune entrée de menu ne reste hors des groupes', () {
    expect(
      entreesDeMenuSansGroupe(),
      isEmpty,
      reason:
          'Ces entrées existent mais la barre latérale ne les dessine pas. '
          'Ajoutez-les à un groupe, ou retirez-les.',
    );
  });

  group('la famille', () {
    // Le référentiel scolaire lui a été ouvert pour que ses propres écrans
    // cessent d'afficher « Classes 0 · Années 0 ». Il ouvrait du même coup
    // deux entrées d'administration, parce que leur visibilité se déduisait
    // de ce droit-là faute d'être écrite.
    for (final role in ['parent', 'student']) {
      test('$role garde « Mes enfants » et non « Gestion des élèves »', () {
        final visibles = entreesDeMenuVisiblesPour(_famille(role));

        expect(visibles, contains('student_lookup'));
        expect(visibles, isNot(contains('students')));
      });

      test('$role n_administre pas le référentiel scolaire', () {
        expect(
          entreesDeMenuVisiblesPour(_famille(role)),
          isNot(contains('academics')),
        );
      });

      test('$role atteint ses notes et son emploi du temps', () {
        final visibles = entreesDeMenuVisiblesPour(_famille(role));

        expect(visibles, containsAll(['grades', 'exams', 'timetable']));
      });
    }
  });

  test('le personnel garde « Gestion des élèves », et elle ferme le dossier', () {
    // La réciproque: personne n'a les deux chemins, personne n'en a zéro.
    final visibles = entreesDeMenuVisiblesPour(
      _droits('director', const {
        'students': AccessLevel.admin,
        'student_lookup': AccessLevel.read,
        'academics': AccessLevel.admin,
      }),
    );

    expect(visibles, contains('students'));
    expect(visibles, isNot(contains('student_lookup')));
    expect(visibles, contains('academics'));
  });

  test('sans le référentiel, « Gestion des élèves » reste fermée', () {
    // La règle d'origine, qu'il ne faut pas perdre: l'écran charge classes et
    // années avant tout, et sans elles il ne rend que son message d'erreur.
    final visibles = entreesDeMenuVisiblesPour(
      _droits('supervisor', const {
        'students': AccessLevel.read,
        'student_lookup': AccessLevel.read,
      }),
    );

    expect(visibles, isNot(contains('students')));
    expect(visibles, contains('student_lookup'));
  });
}

/// Le nom sous lequel on reconnaît la personne connectée.
///
/// La barre latérale affichait l'identifiant sous le nom du rôle :
/// « Admin / superadmin », « Parent / test_parent ». Ni l'un ni l'autre ne dit
/// qui est devant l'écran, et c'est pourtant la seule ligne de l'application
/// qui devrait le dire.
void _nomAffiche() {
  AuthUser compte({String fullName = '', String username = ''}) => AuthUser(
    id: 1,
    username: username,
    fullName: fullName,
    role: 'super_admin',
  );

  group('le nom de la personne connectée', () {
    test('c_est son nom complet', () {
      expect(
        nomAAfficher(compte(fullName: 'Ousseini Mansoure', username: 'superadmin')),
        'Ousseini Mansoure',
      );
    });

    test('à défaut, son identifiant', () {
      // Un compte de service, ou une reprise de données sans état civil: la
      // ligne doit rester remplie.
      expect(nomAAfficher(compte(username: 'superadmin')), 'superadmin');
    });

    test('des espaces ne comptent pas pour un nom', () {
      expect(
        nomAAfficher(compte(fullName: '   ', username: 'superadmin')),
        'superadmin',
      );
    });

    test('sans rien, la ligne ne reste pas vide', () {
      expect(nomAAfficher(compte()), 'Utilisateur');
      expect(nomAAfficher(null), 'Utilisateur');
    });
  });

  group('l_initiale de sa pastille', () {
    // Les deux pastilles de l'écran affichaient « A » pour Admin et « S »
    // pour superadmin: deux lettres différentes pour une même personne, dont
    // aucune n'était la sienne.
    test('c_est celle de son nom', () {
      expect(
        initialeDe(compte(fullName: 'Ousseini Mansoure', username: 'superadmin')),
        'O',
      );
    });

    test('elle est en majuscule, quoi qu_on ait saisi', () {
      expect(initialeDe(compte(fullName: 'ousseini mansoure')), 'O');
    });

    test('à défaut de nom, celle de l_identifiant', () {
      expect(initialeDe(compte(username: 'superadmin')), 'S');
    });

    test('sans rien, la pastille reste remplie', () {
      expect(initialeDe(compte()), 'U');
      expect(initialeDe(null), 'U');
    });
  });
}
