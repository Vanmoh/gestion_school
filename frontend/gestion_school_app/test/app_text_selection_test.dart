// Le texte de l'application doit pouvoir etre selectionne et copie.
//
// Les `Text` de Flutter ne le sont pas par defaut: un matricule, un numero de
// telephone ou un message d'erreur affiche a l'ecran ne pouvait etre que
// recopie a la main. Le montage tient a deux details qui cassent en silence:
// l'enveloppe `SelectionArea`, et l'`Overlay` sans lequel la premiere
// selection leve « No Overlay widget found » au lieu de selectionner.
//
// Les scenarios de selection montent `selectableTextLayer` — la fonction meme
// que MaterialApp utilise — plutot que l'application entiere: celle-ci
// n'affiche rien en test, son ecran d'accueil attendant un stockage securise
// qui ne repond pas. Un dernier scenario verifie que l'application s'en sert
// bien, ce que les deux premiers ne peuvent pas voir.

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/app.dart';

const _matricule = 'LTOB10E0042';

Widget _ecranAvecTexte() => MaterialApp(
  builder: selectableTextLayer,
  home: const Scaffold(body: Center(child: Text(_matricule))),
);

/// Glisse la souris d'un bord a l'autre du widget vise.
///
/// Au toucher, le meme geste fait defiler sans rien selectionner: le pointeur
/// souris est celui du web, ou la demande a ete faite.
Future<void> _glisserSur(WidgetTester tester, Finder cible) async {
  final rect = tester.getRect(cible);
  final geste = await tester.startGesture(
    rect.centerLeft,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 250));
  await geste.moveTo(rect.centerRight);
  await tester.pump();
  await geste.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('selectionner du texte ne manque pas d_Overlay', (tester) async {
    await tester.pumpWidget(_ecranAvecTexte());

    await _glisserSur(tester, find.text(_matricule));

    expect(
      tester.takeException(),
      isNull,
      reason: "l'Overlay a disparu: la selection leve une exception",
    );
  });

  testWidgets('le texte selectionne part dans le presse-papiers', (
    tester,
  ) async {
    String? copie;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copie = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_ecranAvecTexte());
    await _glisserSur(tester, find.text(_matricule));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(copie, _matricule, reason: 'Ctrl+C n_a pas copie la selection');
  });

  testWidgets('l_application monte bien cette couche', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GestionSchoolApp()));
    await tester.pump();

    expect(
      find.byType(SelectionArea),
      findsOneWidget,
      reason: 'MaterialApp.builder ne pose plus la zone de selection',
    );
  });
}
