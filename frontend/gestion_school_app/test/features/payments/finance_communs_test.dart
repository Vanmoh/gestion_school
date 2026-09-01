/// Ce que la page des finances et son dialogue partagent désormais.
///
/// Les deux écrans avaient chacun leur mise en forme des montants — l'une par
/// expression régulière, l'autre par une boucle. Elles donnaient le même
/// résultat sur les cas courants, et rien ne garantissait qu'elles le
/// donneraient encore après la première correction.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/payments/presentation/widgets/finance_communs.dart';

void main() {
  group('montantEnFrancs', () {
    test('les milliers se séparent', () {
      expect(montantEnFrancs(125000), '125 000 FCFA');
      expect(montantEnFrancs(1500), '1 500 FCFA');
      expect(montantEnFrancs(1250000), '1 250 000 FCFA');
    });

    test('en deçà de mille, aucune séparation', () {
      expect(montantEnFrancs(0), '0 FCFA');
      expect(montantEnFrancs(750), '750 FCFA');
    });

    test('un solde négatif garde son signe et ses groupes', () {
      // Une trésorerie nette peut être négative: c'est même le cas qu'on
      // regarde en premier.
      expect(montantEnFrancs(-45000), '-45 000 FCFA');
      expect(montantEnFrancs(-999), '-999 FCFA');
    });

    test('les centimes sont arrondis, pas tronqués', () {
      expect(montantEnFrancs(1499.6), '1 500 FCFA');
      expect(montantEnFrancs(1499.4), '1 499 FCFA');
    });
  });

  group('dates', () {
    final quand = DateTime(2026, 8, 31, 14, 32);

    test('une échéance se lit au jour', () {
      expect(dateEnJour(quand), '31/08/2026');
    });

    test('un encaissement porte son heure', () {
      // Deux règlements du même jour ne se départagent que par là.
      expect(dateEnJourEtHeure(quand), '31/08/2026 14:32');
    });

    test('les rangs sont complétés', () {
      expect(dateEnJour(DateTime(2026, 1, 5)), '05/01/2026');
      expect(dateEnJourEtHeure(DateTime(2026, 1, 5, 8, 7)), '05/01/2026 08:07');
    });
  });

  group('IndicateurFinance', () {
    testWidgets('le libellé annonce, la valeur ressort', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: IndicateurFinance(libelle: 'Impayés', valeur: '45 000 FCFA'),
          ),
        ),
      );

      expect(find.text('Impayés'), findsOneWidget);
      expect(find.text('45 000 FCFA'), findsOneWidget);
    });

    testWidgets('la bordure suit le thème sombre', (tester) async {
      // Elle était figée en noir: sur fond sombre, la pastille perdait son
      // contour.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: const Scaffold(
            body: IndicateurFinance(libelle: 'Trésorerie', valeur: '0 FCFA'),
          ),
        ),
      );

      final contenant = tester.widget<Container>(
        find.ancestor(
          of: find.text('Trésorerie'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = contenant.decoration as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.border!.top.color, isNot(Colors.black12));
    });
  });
}
