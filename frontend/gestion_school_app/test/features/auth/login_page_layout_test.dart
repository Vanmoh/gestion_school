import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/auth/presentation/login_page.dart';

/// Un etablissement au nom long, comme celui qui a fait apparaitre le
/// debordement en conditions reelles.
const _etablissementJson = {
  'id': 4,
  'name': 'Complexe Scolaire Omar Bah (CSOB)',
  'address': 'LTOB (1er etage)',
  'phone': '78 32 59 13 / 66 74 22 32',
};

Future<void> _pumpLoginPage(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: LoginPage()),
    ),
  );
  // hydrate() lit le stockage securise de facon asynchrone.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'selected_etablissement': jsonEncode(_etablissementJson),
    });
  });

  testWidgets('ne deborde pas sur une fenetre courte en mode deux colonnes', (
    tester,
  ) async {
    // 1052x600: la taille exacte qui produisait
    // "A RenderFlex overflowed by 24 pixels on the bottom".
    await _pumpLoginPage(tester, const Size(1052, 600));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ne deborde pas sur une fenetre haute', (tester) async {
    await _pumpLoginPage(tester, const Size(1440, 900));

    expect(tester.takeException(), isNull);
  });

  testWidgets('ne deborde pas en colonne unique etroite', (tester) async {
    await _pumpLoginPage(tester, const Size(600, 520));

    expect(tester.takeException(), isNull);
  });
}
