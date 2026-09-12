/// L'inscription conditionnée au paiement, telle que l'écran la lit.
///
/// La règle ne bloque pas la création de l'élève: un paiement s'accroche à un
/// frais, et un frais à un élève. L'élève existe donc toujours, et c'est la
/// délivrance du bulletin et de la carte qui attend le règlement.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/students/domain/student.dart';

Map<String, dynamic> _brut({
  String statut = 'validee',
  Object? reste = '0',
  bool bloque = false,
  String motif = '',
  String par = '',
}) => {
  'id': 12,
  'user': 40,
  'matricule': 'M-012',
  'user_full_name': 'Awa Traoré',
  'is_archived': false,
  'inscription_status': statut,
  'inscription_reste_a_payer': reste,
  'inscription_bloque_documents': bloque,
  'inscription_exempted_reason': motif,
  'inscription_exempted_by_display': par,
};

void main() {
  test('un élève à jour ne porte aucune pastille', () {
    final eleve = Student.fromJson(_brut());

    expect(eleve.inscriptionEnAttente, isFalse);
    expect(eleve.inscriptionDispensee, isFalse);
  });

  test('un élève en attente annonce ce qu_il reste à régler', () {
    // Le montant, et pas seulement « non réglée »: la secrétaire doit
    // pouvoir dire au parent combien apporter sans ouvrir un autre écran.
    final eleve = Student.fromJson(
      _brut(statut: 'en_attente', reste: '15000.00', bloque: true),
    );

    expect(eleve.inscriptionEnAttente, isTrue);
    expect(eleve.inscriptionResteAPayer, 15000.0);
  });

  test('la dispense se lit, avec son motif et son auteur', () {
    final eleve = Student.fromJson(
      _brut(
        statut: 'exemptee',
        bloque: false,
        motif: 'Boursière de l\'État',
        par: 'Mme Diallo',
      ),
    );

    expect(eleve.inscriptionDispensee, isTrue);
    expect(eleve.inscriptionEnAttente, isFalse);
    expect(eleve.inscriptionMotifDispense, 'Boursière de l\'État');
    expect(eleve.inscriptionDispensePar, 'Mme Diallo');
  });

  test('une école qui n_applique pas la règle ne bloque personne', () {
    // Le serveur renvoie le statut, mais c'est « bloque_documents » qui
    // décide: lui seul tient compte du réglage de l'école.
    final eleve = Student.fromJson(
      _brut(statut: 'en_attente', reste: '25000.00', bloque: false),
    );

    expect(eleve.inscriptionEnAttente, isFalse);
  });

  test('un serveur plus ancien ne fait pas tomber l_écran', () {
    // Les champs absents valent « à jour »: une application à jour contre un
    // backend qui ne l'est pas encore ne doit pas fermer tous les bulletins.
    final eleve = Student.fromJson(const {
      'id': 5,
      'user': 9,
      'matricule': 'M-005',
      'user_full_name': 'Modibo Keita',
      'is_archived': false,
    });

    expect(eleve.inscriptionStatus, 'validee');
    expect(eleve.inscriptionEnAttente, isFalse);
    expect(eleve.inscriptionResteAPayer, 0);
  });

  test('un montant en nombre est lu comme un montant en chaîne', () {
    // Le serveur sérialise le décimal en chaîne; un cache ou un test peut
    // rendre un nombre. Les deux doivent donner le même reste.
    expect(
      Student.fromJson(_brut(reste: 7500)).inscriptionResteAPayer,
      7500.0,
    );
    expect(
      Student.fromJson(_brut(reste: '7500.00')).inscriptionResteAPayer,
      7500.0,
    );
  });
}
