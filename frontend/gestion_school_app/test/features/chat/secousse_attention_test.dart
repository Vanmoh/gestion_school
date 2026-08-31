/// La secousse qui accompagne un appel d'attention.
///
/// Elle doit se voir — une fenêtre qui surgit sans bouger passe inaperçue sur
/// un écran chargé — et surtout s'arrêter : une fenêtre qui tremble sans fin
/// empêche de lire ce qu'elle contient et d'y répondre, soit l'inverse du but.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/chat/presentation/widgets/secousse_attention.dart';

/// Le décalage horizontal appliqué à l'enfant à cet instant.
double _decalage(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.ancestor(
      of: find.byKey(const Key('contenu')),
      matching: find.byType(Transform),
    ).first,
  );
  return transform.transform.getTranslation().x;
}

bool _secoue(WidgetTester tester) {
  final transforms = find.ancestor(
    of: find.byKey(const Key('contenu')),
    matching: find.byType(Transform),
  );
  if (transforms.evaluate().isEmpty) return false;
  return _decalage(tester).abs() > 0.01;
}

Future<void> _monter(WidgetTester tester, int declencheur) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SecousseAttention(
        declencheur: declencheur,
        child: const SizedBox(
          key: Key('contenu'),
          width: 100,
          height: 100,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('sans appel, rien ne bouge', (tester) async {
    await _monter(tester, 0);
    await tester.pump(const Duration(milliseconds: 300));

    expect(_secoue(tester), isFalse);
  });

  testWidgets('un appel secoue la fenêtre', (tester) async {
    await _monter(tester, 1);
    await tester.pump(const Duration(milliseconds: 300));

    expect(_secoue(tester), isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('la secousse s_arrete d_elle-meme', (tester) async {
    await _monter(tester, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_secoue(tester), isTrue, reason: 'elle devait démarrer');

    // Au-delà de sa durée, la fenêtre doit être immobile: on doit pouvoir
    // lire et répondre.
    await tester.pump(SecousseAttention.duree);
    await tester.pumpAndSettle();
    expect(_secoue(tester), isFalse);
  });

  testWidgets('l_amplitude decroit au lieu de s_interrompre net', (
    tester,
  ) async {
    await _monter(tester, 1);

    // Le décalage oscille: comparer deux instants pris au hasard ne prouve
    // rien. On mesure la plus grande amplitude atteinte sur le premier tiers,
    // puis sur le dernier, ce qui suit l'enveloppe et non l'oscillation.
    Future<double> creteSur(Duration duree) async {
      var maxi = 0.0;
      final pas = const Duration(milliseconds: 16);
      for (var t = Duration.zero; t < duree; t += pas) {
        await tester.pump(pas);
        final d = _decalage(tester).abs();
        if (d > maxi) maxi = d;
      }
      return maxi;
    }

    final debut = await creteSur(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 900));
    final fin = await creteSur(const Duration(milliseconds: 700));

    expect(debut, greaterThan(4), reason: 'la secousse doit être visible');
    expect(
      fin,
      lessThan(debut / 2),
      reason: 'elle doit s’épuiser, pas s’arrêter net',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('un second appel relance la secousse', (tester) async {
    await _monter(tester, 1);
    await tester.pump(SecousseAttention.duree);
    await tester.pumpAndSettle();
    expect(_secoue(tester), isFalse);

    // Chaque clic doit rappeler l'attention: c'est l'arbitrage retenu, il n'y
    // a pas de délai d'attente entre deux appels.
    await _monter(tester, 2);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_secoue(tester), isTrue);
    await tester.pumpAndSettle();
  });
}
