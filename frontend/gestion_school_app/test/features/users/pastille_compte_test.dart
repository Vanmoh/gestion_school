/// L'état d'un compte dans l'annuaire.
///
/// La liste ne le disait pas: on ne pouvait ni voir qui gardait un accès
/// après son départ, ni repérer les comptes créés puis jamais utilisés.
///
/// Elle ne disait pas non plus qui était là maintenant — « Actif » parlait du
/// compte, jamais de son titulaire. Et l'information venait d'un booléen posé
/// une fois pour toutes: un correspondant parti restait vert des jours durant.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/models/presence.dart';
import 'package:gestion_school_app/features/users/domain/user_account.dart';
import 'package:gestion_school_app/features/users/presentation/widgets/pastille_compte.dart';

UserAccount _compte({
  bool actif = true,
  DateTime? derniereConnexion,
  Presence presence = const Presence(),
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
    presence: presence,
  );
}

Future<void> _pump(WidgetTester tester, UserAccount compte) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: PastilleCompte(compte: compte))),
  );
  await tester.pump();
}

void main() {
  testWidgets('une personne presente est annoncee en ligne', (tester) async {
    await _pump(
      tester,
      _compte(presence: Presence(vuA: DateTime.now(), annonceEnLigne: true)),
    );

    expect(find.text('En ligne'), findsOneWidget);
  });

  testWidgets('un signe de vie trop vieux ne dit plus en ligne', (tester) async {
    // Le defaut signale: un socket mort sans prevenir laissait la pastille
    // verte indefiniment.
    await _pump(
      tester,
      _compte(
        presence: Presence(
          vuA: DateTime.now().subtract(const Duration(days: 3)),
          annonceEnLigne: true,
        ),
      ),
    );

    expect(find.text('En ligne'), findsNothing);
    expect(find.text('Il y a 3 jours'), findsOneWidget);
  });

  testWidgets('un compte coupe se voit', (tester) async {
    await _pump(
      tester,
      _compte(actif: false, derniereConnexion: DateTime.now()),
    );

    expect(find.text('Désactivé'), findsOneWidget);
  });

  testWidgets('un compte jamais utilise se signale', (tester) async {
    await _pump(tester, _compte());

    expect(find.text('Jamais connecté'), findsOneWidget);
  });

  testWidgets('la coupure prime sur tout le reste', (tester) async {
    // Qu'il soit devant son écran ou non ne change rien: il n'entre plus.
    await _pump(
      tester,
      _compte(actif: false, presence: Presence(vuA: DateTime.now())),
    );

    expect(find.text('Désactivé'), findsOneWidget);
    expect(find.text('En ligne'), findsNothing);
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

    test('l_etat de connexion donne l_heure a la minute', () {
      final compte = _compte(
        presence: Presence(
          vuA: DateTime.now().subtract(const Duration(days: 2)),
        ),
      );

      // La date seule ne departageait pas deux visites du meme jour.
      expect(compte.etatDeConnexion, matches(r'^Vu le \d{2}/\d{2}/\d{4} à \d{2}:\d{2}$'));
    });

    test('present, l_etat de connexion le dit sans detour', () {
      expect(
        _compte(presence: Presence(vuA: DateTime.now())).etatDeConnexion,
        'En ligne',
      );
    });

    test('une activite recente sort le compte des jamais connectes', () {
      // L'ancien serveur n'ecrivait pas `last_login`: tous les comptes
      // restaient marques « jamais connecte », y compris celui qui regardait
      // l'ecran.
      final compte = _compte(presence: Presence(vuA: DateTime.now()));

      expect(compte.jamaisConnecte, isFalse);
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

    test('la charge du serveur porte la presence', () {
      final compte = UserAccount.fromJson({
        'id': 4,
        'username': 'moussa',
        'online': true,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      });

      expect(compte.enLigne, isTrue);
      expect(compte.etatDeConnexion, 'En ligne');
    });
  });
}
