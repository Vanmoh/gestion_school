/// L'état d'un compte dans l'annuaire.
///
/// La liste ne le disait pas: on ne pouvait ni voir qui gardait un accès
/// après son départ, ni repérer les comptes créés puis jamais utilisés.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/users/domain/user_account.dart';
import 'package:gestion_school_app/features/users/presentation/widgets/pastille_compte.dart';

UserAccount _compte({
  bool actif = true,
  DateTime? derniereConnexion,
}) {
  return UserAccount(
    id: 1,
    username: 'awa.traore',
    firstName: 'Awa',
    lastName: 'Traoré',
    email: 'awa@ecole.ml',
    role: 'accountant',
    phone: '',
    isActive: actif,
    lastLogin: derniereConnexion,
  );
}

Future<void> _pump(WidgetTester tester, UserAccount compte) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: PastilleCompte(compte: compte))),
  );
  await tester.pump();
}

void main() {
  testWidgets('un compte utilise est annonce actif', (tester) async {
    await _pump(tester, _compte(derniereConnexion: DateTime.now()));

    expect(find.text('Actif'), findsOneWidget);
  });

  testWidgets('un compte coupe se voit', (tester) async {
    await _pump(tester, _compte(actif: false, derniereConnexion: DateTime.now()));

    expect(find.text('Désactivé'), findsOneWidget);
  });

  testWidgets('un compte jamais utilise se signale', (tester) async {
    await _pump(tester, _compte());

    expect(find.text('Jamais connecté'), findsOneWidget);
  });

  testWidgets('la coupure prime sur l_absence de connexion', (tester) async {
    // Qu'il se soit connecté ou non ne change rien: il n'entre plus.
    await _pump(tester, _compte(actif: false));

    expect(find.text('Désactivé'), findsOneWidget);
    expect(find.text('Jamais connecté'), findsNothing);
  });

  group('UserAccount', () {
    test('sans connexion, la derniere activite le dit', () {
      expect(_compte().derniereActivite, 'Jamais connecté');
      expect(_compte().jamaisConnecte, isTrue);
    });

    test('la derniere activite se raconte en clair', () {
      final hier = DateTime.now().subtract(const Duration(days: 1));
      expect(_compte(derniereConnexion: hier).derniereActivite, 'Hier');

      final semaine = DateTime.now().subtract(const Duration(days: 5));
      expect(
        _compte(derniereConnexion: semaine).derniereActivite,
        'Il y a 5 jours',
      );
    });

    test('le nom complet retombe sur l_identifiant', () {
      const sansNom = UserAccount(
        id: 2,
        username: 'compte.technique',
        firstName: '',
        lastName: '',
        email: '',
        role: 'accountant',
        phone: '',
      );

      expect(sansNom.fullName, 'compte.technique');
    });

    test('un serveur muet sur l_etat ne coupe pas le compte a tort', () {
      // Mieux vaut l'afficher ouvert que barre par erreur.
      final compte = UserAccount.fromJson({'id': 3, 'username': 'x'});

      expect(compte.isActive, isTrue);
    });
  });
}
