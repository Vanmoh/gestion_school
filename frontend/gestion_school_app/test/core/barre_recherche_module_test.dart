/// La barre de recherche partagee des modules, et son etat d'accueil.
///
/// Elle porte le motif des modules « Gestion des eleves » et « Enseignants »:
/// une grande barre, ses actions dessous, et trois etats qui ne doivent pas se
/// confondre -- on n'a rien demande, on cherche, on n'a rien trouve.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/widgets/barre_recherche_module.dart';

Future<TextEditingController> _pumpBarre(
  WidgetTester tester, {
  String texte = '',
  List<Widget> actions = const [],
  bool rechercheEnCours = false,
  bool compact = false,
  List<String>? frappes,
  VoidCallback? onEffacer,
}) async {
  final controller = TextEditingController(text: texte);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BarreRechercheModule(
            controller: controller,
            indication: 'Rechercher : nom, code, téléphone…',
            onChanged: (valeur) => frappes?.add(valeur),
            onEffacer: onEffacer ?? () {},
            actions: actions,
            rechercheEnCours: rechercheEnCours,
            compact: compact,
          ),
        ),
      ),
    ),
  );
  if (rechercheEnCours) {
    // Le rond de la pastille tourne sans fin: `pumpAndSettle` attendrait une
    // stabilisation qui ne vient jamais. Une image suffit pour l'observer.
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return controller;
}

void main() {
  group('BarreRechercheModule', () {
    testWidgets('annonce les criteres acceptes, pas juste « Rechercher »', (
      tester,
    ) async {
      await _pumpBarre(tester);

      expect(find.text('Rechercher : nom, code, téléphone…'), findsOneWidget);
    });

    testWidgets('remonte chaque frappe a la page', (tester) async {
      final frappes = <String>[];
      await _pumpBarre(tester, frappes: frappes);

      await tester.enterText(find.byType(TextField), 'Keita');
      await tester.pump();

      expect(frappes, ['Keita']);
    });

    testWidgets('le bouton effacer n\'existe que s\'il y a quoi effacer', (
      tester,
    ) async {
      await _pumpBarre(tester);
      expect(find.byTooltip('Effacer'), findsNothing);

      await _pumpBarre(tester, texte: 'Keita');
      expect(find.byTooltip('Effacer'), findsOneWidget);
    });

    testWidgets('effacer rend la main a la page', (tester) async {
      var efface = 0;
      await _pumpBarre(tester, texte: 'Keita', onEffacer: () => efface++);

      await tester.tap(find.byTooltip('Effacer'));
      await tester.pump();

      expect(efface, 1);
    });

    testWidgets('les actions se posent sous la barre', (tester) async {
      await _pumpBarre(
        tester,
        actions: [
          OutlinedButton(onPressed: () {}, child: const Text('Liste')),
        ],
      );

      expect(find.text('Liste'), findsOneWidget);
    });

    testWidgets('l\'attente du serveur se voit', (tester) async {
      // Chercher et n'avoir rien trouve se ressemblent a l'ecran: sans cette
      // pastille, une reponse lente passe pour une absence de resultat.
      await _pumpBarre(tester, rechercheEnCours: true);

      expect(find.text('Recherche...'), findsOneWidget);
    });

    testWidgets('sans action ni attente, aucune place perdue sous la barre', (
      tester,
    ) async {
      await _pumpBarre(tester);

      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('en compact, le clavier ne s\'ouvre pas tout seul', (
      tester,
    ) async {
      // Sur un telephone, le focus automatique masque la moitie de l'ecran
      // avant meme qu'on ait lu ce que la page propose.
      await _pumpBarre(tester, compact: true);

      final champ = tester.widget<TextField>(find.byType(TextField));
      expect(champ.autofocus, isFalse);
    });
  });

  group('EtatVideRecherche', () {
    Future<void> pump(WidgetTester tester, String recherche) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EtatVideRecherche(
              recherche: recherche,
              invitation: 'Recherchez un utilisateur pour ouvrir sa palette.',
              precision: 'Nom, identifiant, e-mail ou téléphone.',
              motAucun: 'Aucun utilisateur ne correspond à',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sans recherche, il invite au lieu d\'annoncer un vide', (
      tester,
    ) async {
      await pump(tester, '');

      expect(
        find.text('Recherchez un utilisateur pour ouvrir sa palette.'),
        findsOneWidget,
      );
      expect(find.text('Nom, identifiant, e-mail ou téléphone.'), findsOneWidget);
    });

    testWidgets('une recherche infructueuse cite ce qui a ete cherche', (
      tester,
    ) async {
      // « Aucun resultat » seul laisse douter de ce qui a ete envoye.
      await pump(tester, 'Zzz');

      expect(
        find.text('Aucun utilisateur ne correspond à « Zzz ».'),
        findsOneWidget,
      );
      expect(find.textContaining('Recherchez un utilisateur'), findsNothing);
    });

    testWidgets('des espaces seuls valent une recherche vide', (tester) async {
      await pump(tester, '   ');

      expect(
        find.text('Recherchez un utilisateur pour ouvrir sa palette.'),
        findsOneWidget,
      );
    });
  });
}
