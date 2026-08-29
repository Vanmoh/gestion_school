/// La palette d'un compte utilisateur.
///
/// La fiche qu'elle remplace tenait en six pastilles grises: l'etat du compte
/// -- coupe, jamais utilise -- n'y apparaissait nulle part, alors que c'est
/// ce qu'on vient verifier quand quelqu'un quitte l'etablissement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/users/domain/user_account.dart';
import 'package:gestion_school_app/features/users/presentation/widgets/user_palette_card.dart';

UserAccount _compte({
  String firstName = 'Aminata',
  String lastName = 'Keita',
  String username = 'a.keita',
  String email = 'a.keita@ltob.ml',
  String phone = '78785913',
  String role = 'teacher',
  String roleLabel = 'Enseignant',
  String etablissement = 'IFP-OBK',
  bool isActive = true,
  DateTime? lastLogin,
  DateTime? dateJoined,
}) {
  return UserAccount(
    id: 1,
    username: username,
    firstName: firstName,
    lastName: lastName,
    email: email,
    role: role,
    roleLabel: roleLabel,
    phone: phone,
    etablissementName: etablissement,
    isActive: isActive,
    lastLogin: lastLogin,
    dateJoined: dateJoined,
  );
}

Future<void> _pump(
  WidgetTester tester,
  UserAccount compte, {
  List<Widget> actions = const [],
  VoidCallback? onClear,
  Size taille = const Size(1280, 900),
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UserPaletteCard(
            compte: compte,
            actions: actions,
            onClear: onClear,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('UserPaletteCard', () {
    testWidgets('montre l\'identite, l\'acces et les contacts', (tester) async {
      await _pump(tester, _compte());

      expect(find.text('Aminata Keita'), findsWidgets);
      expect(find.text('a.keita'), findsOneWidget);
      expect(find.text('Enseignant'), findsWidgets);
      expect(find.text('a.keita@ltob.ml'), findsOneWidget);
      expect(find.text('78785913'), findsOneWidget);
      expect(find.text('IFP-OBK'), findsWidgets);
    });

    testWidgets('un champ vide se dit, il ne laisse pas un blanc', (
      tester,
    ) async {
      // Date de creation fournie: seuls l'email et le telephone manquent, ce
      // qui isole les deux replis attendus.
      await _pump(
        tester,
        _compte(email: '', phone: '', dateJoined: DateTime(2025, 9, 1)),
      );

      // Un blanc laisse croire a un defaut d'affichage plutot qu'a une
      // information absente.
      expect(find.text(UserPaletteCard.nonRenseigne), findsNWidgets(2));
    });

    testWidgets('un compte desactive l\'annonce des l\'en-tete', (tester) async {
      await _pump(tester, _compte(isActive: false));

      expect(find.text('Désactivé'), findsNWidgets(2));
    });

    testWidgets('un compte actif ne porte pas la pastille de coupure', (
      tester,
    ) async {
      await _pump(tester, _compte());

      expect(find.text('Désactivé'), findsNothing);
      expect(find.text('Actif'), findsOneWidget);
    });

    testWidgets('un compte jamais utilise se signale', (tester) async {
      // Soit il ne sert a personne, soit son titulaire n'a jamais recu ses
      // acces: les deux demandent une action.
      await _pump(tester, _compte(lastLogin: null));

      expect(find.text(UserPaletteCard.jamaisConnecte), findsOneWidget);
    });

    testWidgets('les dates sortent au format d\'ici', (tester) async {
      await _pump(
        tester,
        _compte(
          lastLogin: DateTime(2026, 3, 12),
          dateJoined: DateTime(2025, 9, 1),
        ),
      );

      expect(find.text('12/03/2026'), findsOneWidget);
      expect(find.text('01/09/2025'), findsOneWidget);
    });

    testWidgets('les actions se posent sous le nom', (tester) async {
      var clics = 0;
      await _pump(
        tester,
        _compte(),
        actions: [
          FilledButton(
            onPressed: () => clics++,
            child: const Text('Modifier'),
          ),
        ],
      );

      await tester.tap(find.text('Modifier'));
      await tester.pump();

      expect(clics, 1);
    });

    testWidgets('le retour aux resultats n\'existe que s\'il y en a', (
      tester,
    ) async {
      await _pump(tester, _compte());
      expect(find.text('Résultats'), findsNothing);

      await _pump(tester, _compte(), onClear: () {});
      expect(find.text('Résultats'), findsOneWidget);
    });

    testWidgets('sans nom, l\'identifiant tient lieu de titre', (tester) async {
      // Un compte de service n'a ni prenom ni nom: la palette doit rester
      // lisible plutot que d'afficher un titre vide.
      await _pump(tester, _compte(firstName: '', lastName: ''));

      expect(find.text('a.keita'), findsWidgets);
    });

    testWidgets('sans libelle de role, le code technique reste affiche', (
      tester,
    ) async {
      await _pump(tester, _compte(roleLabel: ''));

      expect(find.text('teacher'), findsWidgets);
    });

    testWidgets('sur un ecran etroit, la palette tient sans deborder', (
      tester,
    ) async {
      await _pump(tester, _compte(), taille: const Size(420, 900));

      expect(tester.takeException(), isNull);
      expect(find.text('a.keita'), findsOneWidget);
    });
  });
}
