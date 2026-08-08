/// Le refus doit se lire avant l'effort, pas apres.
///
/// Les gardes d'ecriture existaient deja mais n'intervenaient qu'au moment
/// d'enregistrer: on ouvrait le formulaire, on le remplissait, puis on
/// apprenait « Mode lecture seule ». Le bouton grise dit non tout de suite.
///
/// Ces tests portent sur buildStudentActions, la fonction reellement appelee
/// par la palette: une reecriture de la regle dans le test ne verifierait que
/// le test lui-meme.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/students/presentation/student_actions.dart';

const _libelles = [
  'Éditer',
  'Historique',
  'Incident',
  'Absence',
  'Frais',
  'Paiement',
];

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'students': ModulePermission(
        key: 'students',
        label: 'Gestion des eleves',
        group: 'pedagogie',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

List<StudentAction> _actions(
  AccessLevel niveau, {
  bool saving = false,
  String nom = 'Fatou Diallo',
}) {
  return buildStudentActions(
    canWrite: _droits(niveau).canWrite('students'),
    saving: saving,
    studentName: nom,
  );
}

StudentAction _action(List<StudentAction> actions, String label) =>
    actions.firstWhere((action) => action.label == label);

void main() {
  test('la palette propose bien une action d_edition', () {
    final actions = _actions(AccessLevel.write);

    expect(actions.map((a) => a.label), containsAll(_libelles));
    expect(_action(actions, 'Éditer').enabled, isTrue);
  });

  test('en ecriture, toutes les actions sont actives', () {
    for (final action in _actions(AccessLevel.write)) {
      expect(action.enabled, isTrue, reason: action.label);
    }
  });

  test('en administration aussi', () {
    expect(_action(_actions(AccessLevel.admin), 'Éditer').enabled, isTrue);
  });

  test('en lecture seule, toutes les actions sont grisees', () {
    for (final action in _actions(AccessLevel.read)) {
      expect(action.enabled, isFalse, reason: action.label);
    }
  });

  test('sans aucun acces, elles le sont aussi', () {
    for (final action in _actions(AccessLevel.none)) {
      expect(action.enabled, isFalse, reason: action.label);
    }
  });

  test('le grisage porte son motif', () {
    // Un bouton eteint sans explication passe pour une panne.
    for (final action in _actions(AccessLevel.read)) {
      expect(action.tooltip, lectureSeuleMotif, reason: action.label);
    }
  });

  test('autorise, l_infobulle nomme l_eleve vise', () {
    expect(
      _action(_actions(AccessLevel.write), 'Incident').tooltip,
      'Incident — Fatou Diallo',
    );
  });

  test('sans eleve nomme, l_infobulle ne laisse pas un tiret orphelin', () {
    expect(_action(_actions(AccessLevel.write, nom: ''), 'Frais').tooltip, 'Frais');
  });

  test('un enregistrement en cours neutralise les actions', () {
    for (final action in _actions(AccessLevel.write, saving: true)) {
      expect(action.enabled, isFalse, reason: action.label);
    }
  });

  test('un enregistrement en cours ne fait pas passer pour un refus de droit', () {
    // Le motif de lecture seule mentirait: le profil a bien le droit.
    expect(
      _action(_actions(AccessLevel.write, saving: true), 'Éditer').tooltip,
      isNot(lectureSeuleMotif),
    );
  });

  group('lecture de la matrice', () {
    test('canWrite suit le niveau du module', () {
      expect(_droits(AccessLevel.none).canWrite('students'), isFalse);
      expect(_droits(AccessLevel.read).canWrite('students'), isFalse);
      expect(_droits(AccessLevel.write).canWrite('students'), isTrue);
      expect(_droits(AccessLevel.admin).canWrite('students'), isTrue);
    });

    test('un module inconnu est refuse, pas suppose permis', () {
      expect(_droits(AccessLevel.admin).canWrite('inexistant'), isFalse);
    });
  });
}
