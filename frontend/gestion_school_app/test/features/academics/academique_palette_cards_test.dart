/// Les palettes du module Academique: une classe, ou une matiere.
///
/// Le module ne montrait que deux tableaux pagines: savoir ce que portait une
/// classe demandait de lire sa ligne, puis de chercher ses matieres dans
/// l'autre tableau, une par une.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/academics/presentation/widgets/academique_palette_cards.dart';

Map<String, dynamic> _classe({
  String nom = '6e A',
  dynamic effectif = 32,
}) => {
  'id': 7,
  'name': nom,
  'academic_year': 3,
  'student_count': effectif,
};

Map<String, dynamic> _matiere({
  String nom = 'Mathématiques',
  String code = 'MATH',
  dynamic coefficient = '2.00',
}) => {
  'id': 11,
  'name': nom,
  'code': code,
  'coefficient': coefficient,
  'classroom': 7,
  'classroom_name': '6e A',
};

Future<void> _pump(
  WidgetTester tester,
  Widget palette, {
  Size taille = const Size(1280, 900),
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: palette)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ClassePaletteCard', () {
    testWidgets('montre la classe, son annee et son effectif', (tester) async {
      await _pump(
        tester,
        ClassePaletteCard(classe: _classe(), anneeNom: '2025-2026'),
      );

      expect(find.text('6e A'), findsWidgets);
      expect(find.text('2025-2026'), findsWidgets);
      expect(find.text('32 élèves'), findsOneWidget);
    });

    testWidgets('un seul eleve ne prend pas de pluriel', (tester) async {
      await _pump(
        tester,
        ClassePaletteCard(classe: _classe(effectif: 1), anneeNom: '2025-2026'),
      );

      expect(find.text('1 élève'), findsOneWidget);
    });

    testWidgets('une classe vide affiche zero, pas un blanc', (tester) async {
      // Une classe vide et une classe dont le compte manque ne demandent pas
      // la meme chose.
      await _pump(
        tester,
        ClassePaletteCard(classe: _classe(effectif: 0), anneeNom: '2025-2026'),
      );

      expect(find.text('0 élève'), findsOneWidget);
    });

    testWidgets('un effectif rendu en chaine reste un nombre', (tester) async {
      // JSON n'a qu'un type numerique, mais une annotation peut revenir en
      // chaine selon le pilote.
      await _pump(
        tester,
        ClassePaletteCard(
          classe: _classe(effectif: '32'),
          anneeNom: '2025-2026',
        ),
      );

      expect(find.text('32 élèves'), findsOneWidget);
    });

    testWidgets('les matieres de la classe sont listees', (tester) async {
      await _pump(
        tester,
        ClassePaletteCard(
          classe: _classe(),
          anneeNom: '2025-2026',
          matieres: [_matiere(), _matiere(nom: 'Français', code: 'FR')],
        ),
      );

      expect(find.text('Mathématiques · MATH'), findsOneWidget);
      expect(find.text('Français · FR'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('une classe sans matiere le dit', (tester) async {
      await _pump(
        tester,
        ClassePaletteCard(classe: _classe(), anneeNom: '2025-2026'),
      );

      expect(
        find.text('Aucune matière rattachée à cette classe.'),
        findsOneWidget,
      );
    });

    testWidgets('une matiere de la liste ouvre sa palette', (tester) async {
      final ouvertes = <String>[];
      await _pump(
        tester,
        ClassePaletteCard(
          classe: _classe(),
          anneeNom: '2025-2026',
          matieres: [_matiere()],
          onOuvrirMatiere: (m) => ouvertes.add(m['name'].toString()),
        ),
      );

      await tester.tap(find.text('Mathématiques · MATH'));
      await tester.pump();

      expect(ouvertes, ['Mathématiques']);
    });

    testWidgets('le retour aux resultats n\'existe que s\'il y en a', (
      tester,
    ) async {
      await _pump(
        tester,
        ClassePaletteCard(classe: _classe(), anneeNom: '2025-2026'),
      );
      expect(find.text('Résultats'), findsNothing);

      await _pump(
        tester,
        ClassePaletteCard(
          classe: _classe(),
          anneeNom: '2025-2026',
          onClear: () {},
        ),
      );
      expect(find.text('Résultats'), findsOneWidget);
    });
  });

  group('MatierePaletteCard', () {
    testWidgets('montre l\'intitule, le code et sa classe', (tester) async {
      await _pump(
        tester,
        MatierePaletteCard(matiere: _matiere(), classeNom: '6e A'),
      );

      expect(find.text('Mathématiques'), findsWidgets);
      expect(find.text('MATH'), findsWidgets);
      expect(find.text('6e A'), findsWidgets);
    });

    testWidgets('un coefficient rond se lit sans decimales', (tester) async {
      // « 2.00 » est un detail de stockage; le bulletin, lui, dit « 2 ».
      await _pump(
        tester,
        MatierePaletteCard(matiere: _matiere(), classeNom: '6e A'),
      );

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('un coefficient fractionnaire garde sa precision', (
      tester,
    ) async {
      await _pump(
        tester,
        MatierePaletteCard(
          matiere: _matiere(coefficient: '1.50'),
          classeNom: '6e A',
        ),
      );

      expect(find.text('1.5'), findsOneWidget);
    });

    testWidgets('un coefficient absent ne casse pas la palette', (
      tester,
    ) async {
      await _pump(
        tester,
        MatierePaletteCard(
          matiere: _matiere(coefficient: null),
          classeNom: '6e A',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Non renseigné'), findsOneWidget);
    });

    testWidgets('on remonte a la classe de rattachement', (tester) async {
      var clics = 0;
      await _pump(
        tester,
        MatierePaletteCard(
          matiere: _matiere(),
          classeNom: '6e A',
          onOuvrirClasse: () => clics++,
        ),
      );

      await tester.tap(find.text('Ouvrir la classe 6e A'));
      await tester.pump();

      expect(clics, 1);
    });

    testWidgets('sans classe connue, aucun bouton ne mene nulle part', (
      tester,
    ) async {
      await _pump(
        tester,
        MatierePaletteCard(
          matiere: _matiere(),
          classeNom: '',
          onOuvrirClasse: () {},
        ),
      );

      expect(find.textContaining('Ouvrir la classe'), findsNothing);
    });

    testWidgets('sur un ecran etroit, la palette tient sans deborder', (
      tester,
    ) async {
      await _pump(
        tester,
        MatierePaletteCard(matiere: _matiere(), classeNom: '6e A'),
        taille: const Size(420, 900),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('coefficientLisible', () {
    test('rend les cas limites sans exception', () {
      expect(MatierePaletteCard.coefficientLisible('2.00'), '2');
      expect(MatierePaletteCard.coefficientLisible('1.50'), '1.5');
      expect(MatierePaletteCard.coefficientLisible(3), '3');
      expect(MatierePaletteCard.coefficientLisible(null), '');
      // Une valeur illisible se rend telle quelle plutot que de disparaitre.
      expect(MatierePaletteCard.coefficientLisible('abc'), 'abc');
    });
  });
}
