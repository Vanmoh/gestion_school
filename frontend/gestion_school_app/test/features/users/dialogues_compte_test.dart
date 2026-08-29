/// Les deux gestes d'administration d'un compte.
///
/// L'écran offrait un champ « Mot de passe » que l'API recevait sans rien en
/// faire, et une suppression qui ne disait pas qu'elle emportait la fiche,
/// les affectations et les pointages avec le compte.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/users/domain/user_account.dart';
import 'package:gestion_school_app/features/users/presentation/widgets/dialogue_reinitialisation.dart';
import 'package:gestion_school_app/features/users/presentation/widgets/dialogue_suppression.dart';

const _compte = UserAccount(
  id: 7,
  username: 'moussa.kone',
  firstName: 'Moussa',
  lastName: 'Koné',
  email: 'moussa@ecole.ml',
  role: 'teacher',
  phone: '',
);

/// Monte un dialogue et rend ce qu'il a renvoyé à sa fermeture.
Future<Object?> _ouvrir(WidgetTester tester, Widget dialogue) async {
  Object? rendu;
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              rendu = await showDialog<Object?>(
                context: context,
                builder: (_) => dialogue,
              );
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('ouvrir'));
  await tester.pumpAndSettle();
  return rendu;
}

void main() {
  group('réinitialisation du mot de passe', () {
    testWidgets('le compte visé est nommé', (tester) async {
      await _ouvrir(tester, const DialogueReinitialisation(compte: _compte));

      expect(find.textContaining('Moussa Koné'), findsOneWidget);
      expect(find.textContaining('moussa.kone'), findsOneWidget);
    });

    testWidgets('il rappelle qu_il faut le communiquer', (tester) async {
      // Le mot de passe est fixé ici puis transmis de vive voix: le dire
      // évite qu'on l'attende par courriel.
      await _ouvrir(tester, const DialogueReinitialisation(compte: _compte));

      expect(find.textContaining('Communiquez-le'), findsOneWidget);
    });

    testWidgets('un mot de passe trop court est refuse sur place', (
      tester,
    ) async {
      await _ouvrir(tester, const DialogueReinitialisation(compte: _compte));

      await tester.enterText(
        find.byKey(const Key('mot-de-passe-provisoire')),
        'court',
      );
      await tester.tap(find.text('Réinitialiser'));
      await tester.pumpAndSettle();

      expect(find.textContaining('8 caractères'), findsWidgets);
      // Le dialogue reste ouvert: rien n'est parti au serveur.
      expect(find.byType(DialogueReinitialisation), findsOneWidget);
    });

    testWidgets('un mot de passe valable ferme et remonte la saisie', (
      tester,
    ) async {
      Object? rendu;
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  rendu = await showDialog<String>(
                    context: context,
                    builder: (_) =>
                        const DialogueReinitialisation(compte: _compte),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('mot-de-passe-provisoire')),
        'Provisoire123',
      );
      await tester.tap(find.text('Réinitialiser'));
      await tester.pumpAndSettle();

      expect(rendu, 'Provisoire123');
    });

    testWidgets('le mot de passe est masque, et se devoile sur demande', (
      tester,
    ) async {
      await _ouvrir(tester, const DialogueReinitialisation(compte: _compte));

      TextField champ() => tester.widget<TextField>(
        find.byKey(const Key('mot-de-passe-provisoire')),
      );
      expect(champ().obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(champ().obscureText, isFalse);
    });
  });

  group('suppression d_un compte', () {
    testWidgets('sans donnee liee, elle ne fait pas peur pour rien', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        const DialogueSuppression(compte: _compte, donneesLiees: {}),
      );

      expect(find.textContaining('aucune donnée liée'), findsOneWidget);
      expect(find.text('Supprimer'), findsOneWidget);
      expect(find.byKey(const Key('desactiver-plutot')), findsNothing);
    });

    testWidgets('l_inventaire de ce qui part est detaille', (tester) async {
      await _ouvrir(
        tester,
        const DialogueSuppression(
          compte: _compte,
          donneesLiees: {
            'fiche enseignant': 1,
            'affectations': 3,
            'pointages': 12,
          },
        ),
      );

      expect(find.text('1 fiche enseignant'), findsOneWidget);
      expect(find.text('3 affectations'), findsOneWidget);
      expect(find.text('12 pointages'), findsOneWidget);
    });

    testWidgets('la desactivation est proposee avant l_irreversible', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        const DialogueSuppression(
          compte: _compte,
          donneesLiees: {'fiche enseignant': 1},
        ),
      );

      expect(find.byKey(const Key('desactiver-plutot')), findsOneWidget);
      expect(find.textContaining('sans rien détruire'), findsOneWidget);
    });

    testWidgets('choisir la desactivation remonte ce choix', (tester) async {
      final rendu = await _ouvrir(
        tester,
        const DialogueSuppression(
          compte: _compte,
          donneesLiees: {'fiche enseignant': 1},
        ),
      );
      expect(rendu, isNull); // rien tant qu'on n'a pas cliqué

      await tester.tap(find.byKey(const Key('desactiver-plutot')));
      await tester.pumpAndSettle();
    });

    testWidgets('la suppression exige un geste explicite', (tester) async {
      Object? rendu;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  rendu = await showDialog<ChoixSuppression>(
                    context: context,
                    builder: (_) => const DialogueSuppression(
                      compte: _compte,
                      donneesLiees: {'pointages': 12},
                    ),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirmer-suppression')));
      await tester.pumpAndSettle();

      expect(rendu, ChoixSuppression.supprimer);
    });

    testWidgets('le bouton dit qu_on passe outre un avertissement', (
      tester,
    ) async {
      await _ouvrir(
        tester,
        const DialogueSuppression(
          compte: _compte,
          donneesLiees: {'pointages': 12},
        ),
      );

      expect(find.text('Supprimer quand même'), findsOneWidget);
    });
  });
}
