/// Ce qui designe un eleve, et ce qui ne fait que le decrire.
///
/// Le serveur cherche par fragment et a raison de le faire: « diallo » doit
/// ramener les deux Diallo. Mais l'ecran en tirait qu'il ne pouvait jamais
/// trancher, et gardait ouvert l'eleve d'avant pendant qu'on en cherchait un
/// autre -- la barre affichait un matricule, la palette quelqu'un d'autre.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/students/domain/recherche_eleve.dart';
import 'package:gestion_school_app/features/students/domain/student.dart';

/// [nom] s'ecrit « prenom nom », comme `user_full_name` cote API, qui sert
/// les trois champs separement: la fiche porte les deux ordres.
Student _eleve({
  required int id,
  String nom = '',
  String matricule = '',
  String identifiant = '',
  String telephone = '',
  String telephoneParent = '',
}) {
  final morceaux = nom.split(' ');
  return Student.fromJson({
    'id': id,
    'user': id * 10,
    'user_full_name': nom,
    'user_first_name': morceaux.first,
    'user_last_name': morceaux.length > 1 ? morceaux.sublist(1).join(' ') : '',
    'user_username': identifiant,
    'user_phone': telephone,
    'parent_phone': telephoneParent,
    'matricule': matricule,
    'is_archived': false,
  });
}

void main() {
  final bagayoko = _eleve(
    id: 1,
    nom: 'Ousmane Bagayoko',
    matricule: 'IO1EM125E0028M',
    identifiant: 'ousmane.bagayoko',
    telephone: '76 11 22 33',
  );
  final traore = _eleve(
    id: 2,
    nom: 'Aissata Traore',
    matricule: 'IO1DB125E0011M',
    identifiant: 'aissata.traore',
  );

  test('un matricule entier designe son porteur', () {
    expect(
      eleveDesigneExactement([bagayoko, traore], 'IO1DB125E0011M')?.id,
      2,
    );
  });

  test('le matricule d_un voisin ne suffit pas a le designer', () {
    // Le fragment ramene les deux; aucun des deux n'est nomme.
    expect(eleveDesigneExactement([bagayoko, traore], 'IO1'), isNull);
  });

  test('la casse et les separateurs ne distinguent pas deux ecritures', () {
    expect(
      eleveDesigneExactement([bagayoko, traore], ' io1-db-125-e0011m ')?.id,
      2,
    );
  });

  test('un numero de telephone entier designe aussi', () {
    expect(
      eleveDesigneExactement([bagayoko, traore], '0761122 33')?.id,
      isNull,
    );
    expect(eleveDesigneExactement([bagayoko, traore], '76112233')?.id, 1);
  });

  test('le nom complet designe, dans les deux ordres', () {
    expect(
      eleveDesigneExactement([bagayoko, traore], 'Ousmane Bagayoko')?.id,
      1,
    );
    expect(
      eleveDesigneExactement([bagayoko, traore], 'Bagayoko Ousmane')?.id,
      1,
    );
  });

  test('un prefixe de nom ne designe personne', () {
    expect(eleveDesigneExactement([bagayoko, traore], 'Ousmane'), isNull);
  });

  test('deux enfants derriere le meme numero: on ne tranche pas', () {
    // Le numero du parent nomme une famille, pas un eleve. Choisir l'un des
    // deux serait exactement le defaut qu'on corrige.
    final aine = _eleve(id: 3, nom: 'Mariam Sangare', telephoneParent: '73658334');
    final cadet = _eleve(id: 4, nom: 'Adama Sangare', telephoneParent: '73658334');

    expect(eleveDesigneExactement([aine, cadet], '73 65 83 34'), isNull);
  });

  test('une recherche vide ne designe personne', () {
    expect(eleveDesigneExactement([bagayoko, traore], '   '), isNull);
  });

  test('un champ vide de la fiche n_attrape pas une recherche vide', () {
    // Sans le retrait des chaines vides, tout eleve sans telephone aurait
    // repondu a une recherche reduite a un espace.
    final sansRien = _eleve(id: 5, nom: 'Sans Contact');
    expect(eleveDesigneExactement([sansRien], ' '), isNull);
  });
}
