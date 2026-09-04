/// Le vocabulaire du menu, profil par profil.
///
/// Chaque écran porte le nom que lui donne l'administration. C'est le bon nom
/// pour qui pilote l'établissement, et le mauvais pour tous les autres :
/// « Gestion des élèves » ne montre à un enseignant que ses classes, et
/// « Finances » ne montre à ce même enseignant que sa fiche de paie. Ce qui
/// suit fixe les renommages, et surtout la règle qui les borne — renommer ne
/// donne aucun droit, c'est le backend qui restreint.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/permissions/libelles_de_module.dart';

void main() {
  group('la famille lit son propre périmètre', () {
    test('l_élève ne cherche pas une liste qui n_existe pas pour lui', () {
      expect(
        libelleDeModule('student_lookup', 'student', parDefaut: 'Recherche élève'),
        'Mon dossier',
      );
      expect(
        libelleDeModule('attendance', 'student', parDefaut: 'Émargements'),
        'Mes absences',
      );
      expect(
        libelleDeModule('finance', 'student', parDefaut: 'Finances'),
        'Mes frais scolaires',
      );
    });

    test('le parent lit « mes enfants », pas « les élèves »', () {
      expect(
        libelleDeModule('student_lookup', 'parent', parDefaut: 'Recherche élève'),
        'Mes enfants',
      );
      expect(
        libelleDeModule('attendance', 'parent', parDefaut: 'Émargements'),
        'Absences de mes enfants',
      );
      expect(
        libelleDeModule('grades', 'parent', parDefaut: 'Notes & Bulletins'),
        'Notes de mes enfants',
      );
    });
  });

  group('le personnel lit ce que son écran contient vraiment', () {
    test('l_enseignant: ses classes, et sa seule paie', () {
      expect(
        libelleDeModule('students', 'teacher', parDefaut: 'Gestion des élèves'),
        'Mes élèves',
      );
      // Il n'a pas les finances courantes: cet écran ne lui ouvre que la paie,
      // et seulement la sienne.
      expect(
        libelleDeModule('finance', 'teacher', parDefaut: 'Finances'),
        'Ma paie',
      );
    });

    test('censeur et comptable entrent par des portes différentes', () {
      // Le censeur n'a pas les finances non plus: il vient valider le niveau 1.
      expect(
        libelleDeModule('finance', 'censor', parDefaut: 'Finances'),
        'Paie enseignants',
      );
      // Le comptable n'a pas l'appel des élèves: il vient voir l'émargement
      // des enseignants, qu'il paie.
      expect(
        libelleDeModule('attendance', 'accountant', parDefaut: 'Émargements'),
        'Émargement enseignants',
      );
    });
  });

  group('ce que le renommage ne fait pas', () {
    test('un profil sans variante garde le nom du module', () {
      // Le cas courant: la direction et le pilotage voient l'écran entier, et
      // le nom administratif est alors le bon.
      for (final role in ['super_admin', 'director', 'promoter']) {
        expect(
          libelleDeModule('students', role, parDefaut: 'Gestion des élèves'),
          'Gestion des élèves',
          reason: '$role pilote l_établissement: pas de renommage',
        );
      }
    });

    test('un module sans table garde son nom pour tout le monde', () {
      for (final role in ['student', 'parent', 'teacher', 'accountant']) {
        expect(
          libelleDeModule('chat', role, parDefaut: 'Messagerie'),
          'Messagerie',
        );
        expect(
          libelleDeModule('canteen', role, parDefaut: 'Cantine'),
          'Cantine',
        );
      }
    });

    test('un rôle inconnu retombe sur le nom du module', () {
      // Une version du serveur qui ajouterait un rôle ne doit pas rendre le
      // menu muet.
      expect(
        libelleDeModule('finance', 'role_qui_nexiste_pas', parDefaut: 'Finances'),
        'Finances',
      );
      expect(libelleDeModule('finance', '', parDefaut: 'Finances'), 'Finances');
    });
  });

  test('la table ne renomme que des modules connus de la matrice', () {
    // Une clef mal orthographiée ici ne casse rien et ne renomme rien: elle
    // reste invisible jusqu'à ce que quelqu'un remarque que l'étiquette n'a
    // pas changé. Cette liste vient de MODULES, côté serveur.
    const modulesConnus = {
      'dashboard',
      'students',
      'student_lookup',
      'teachers',
      'attendance',
      'teacher_timesheet',
      'discipline',
      'teacher_availability',
      'academics',
      'academic_imports',
      'grades',
      'promotion',
      'exams',
      'timetable',
      'finance',
      'payroll',
      'communication',
      'sms_config',
      'chat',
      'reports',
      'users',
      'etablissements',
      'activity_logs',
      'backup_restore',
      'library',
      'canteen',
      'stock',
    };

    for (final module in libellesDeModuleParRole.keys) {
      expect(
        modulesConnus,
        contains(module),
        reason: '« $module » ne figure pas dans la matrice du backend',
      );
    }
  });

  test('la table ne renomme que pour des rôles connus', () {
    const rolesConnus = {
      'super_admin',
      'promoter',
      'director',
      'censor',
      'accountant',
      'supervisor',
      'teacher',
      'parent',
      'student',
    };

    for (final entree in libellesDeModuleParRole.entries) {
      for (final role in entree.value.keys) {
        expect(
          rolesConnus,
          contains(role),
          reason: '« $role » (module ${entree.key}) n_est pas un rôle connu',
        );
      }
    }
  });
}
