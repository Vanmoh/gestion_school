/// Le garde-fou qui protège une saisie en cours.
///
/// Changer d'établissement ou d'année recharge tout l'écran. Le faire
/// pendant qu'un formulaire est rempli laisserait la saisie en place avec
/// les données d'une autre école — ce qui s'enregistrerait au mauvais
/// endroit sans que rien ne le signale.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/providers/saisie_en_cours.dart';

/// Monte un widget dans un scope dont on peut lire le compteur.
Future<ProviderContainer> _monter(WidgetTester tester, Widget enfant) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: enfant)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('déclaration d_une saisie', () {
    testWidgets('un formulaire monté se déclare', (tester) async {
      final container = await _monter(
        tester,
        const SaisieEnCours(child: Text('formulaire')),
      );

      expect(container.read(saisieEnCoursProvider), 1);
    });

    testWidgets('un formulaire fermé rend la main', (tester) async {
      final container = await _monter(
        tester,
        const SaisieEnCours(child: Text('formulaire')),
      );
      expect(container.read(saisieEnCoursProvider), 1);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Text('rien'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(saisieEnCoursProvider), 0);
    });

    testWidgets('deux formulaires ouverts se comptent tous les deux', (
      tester,
    ) async {
      // Un compteur et non un booléen: le premier refermé ne doit pas lever
      // la garde du second.
      final container = await _monter(
        tester,
        const Column(
          children: [
            SaisieEnCours(child: Text('un')),
            SaisieEnCours(child: Text('deux')),
          ],
        ),
      );

      expect(container.read(saisieEnCoursProvider), 2);
    });

    testWidgets('un formulaire vide ne monte pas la garde', (tester) async {
      // On ne garde que ce qui serait réellement perdu.
      final container = await _monter(
        tester,
        const SaisieEnCours(active: false, child: Text('vide')),
      );

      expect(container.read(saisieEnCoursProvider), 0);
    });

    testWidgets('la garde suit l_état du formulaire', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Widget avec(bool active) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SaisieEnCours(active: active, child: const Text('champ')),
          ),
        ),
      );

      await tester.pumpWidget(avec(false));
      await tester.pumpAndSettle();
      expect(container.read(saisieEnCoursProvider), 0);

      // L'utilisateur commence à taper.
      await tester.pumpWidget(avec(true));
      await tester.pumpAndSettle();
      expect(container.read(saisieEnCoursProvider), 1);
    });
  });

  group('confirmation avant bascule', () {
    /// Monte un bouton qui demande la confirmation et retient sa réponse.
    Future<bool?> demander(WidgetTester tester, {required int saisies}) async {
      bool? reponse;
      final container = ProviderContainer(
        overrides: [saisieEnCoursProvider.overrideWith((ref) => saisies)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    reponse = await confirmerChangementDeContexte(
                      context,
                      ref,
                      quoi: 'd’établissement',
                    );
                  },
                  child: const Text('changer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('changer'));
      await tester.pumpAndSettle();
      return reponse;
    }

    testWidgets('sans saisie, la bascule passe sans rien demander', (
      tester,
    ) async {
      final reponse = await demander(tester, saisies: 0);

      expect(reponse, isTrue);
      expect(find.byKey(const Key('confirmer-changement-contexte')), findsNothing);
    });

    testWidgets('avec une saisie, elle demande d_abord', (tester) async {
      await demander(tester, saisies: 1);

      expect(
        find.byKey(const Key('confirmer-changement-contexte')),
        findsOneWidget,
      );
      expect(find.textContaining('sera perdu'), findsOneWidget);
    });

    testWidgets('« Rester ici » annule la bascule', (tester) async {
      bool? reponse;
      final container = ProviderContainer(
        overrides: [saisieEnCoursProvider.overrideWith((ref) => 1)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    reponse = await confirmerChangementDeContexte(
                      context,
                      ref,
                      quoi: 'd’année scolaire',
                    );
                  },
                  child: const Text('changer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('changer'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rester ici'));
      await tester.pumpAndSettle();

      expect(reponse, isFalse);
    });

    testWidgets('« Changer quand même » laisse passer', (tester) async {
      bool? reponse;
      final container = ProviderContainer(
        overrides: [saisieEnCoursProvider.overrideWith((ref) => 1)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () async {
                    reponse = await confirmerChangementDeContexte(
                      context,
                      ref,
                      quoi: 'd’établissement',
                    );
                  },
                  child: const Text('changer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('changer'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('changer-quand-meme')));
      await tester.pumpAndSettle();

      expect(reponse, isTrue);
    });

    testWidgets('le message nomme ce qui change', (tester) async {
      await demander(tester, saisies: 1);

      expect(find.textContaining('d’établissement'), findsOneWidget);
    });
  });
}
