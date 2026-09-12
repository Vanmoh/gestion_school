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

void main() {
  test('aucune entrée de menu ne reste hors des groupes', () {
    expect(
      entreesDeMenuSansGroupe(),
      isEmpty,
      reason:
          'Ces entrées existent mais la barre latérale ne les dessine pas. '
          'Ajoutez-les à un groupe, ou retirez-les.',
    );
  });
}
