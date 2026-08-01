import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/models/etablissement.dart';
import 'package:gestion_school_app/screens/etablissement_details_screen.dart';

final _complet = Etablissement(
  id: 3,
  name: 'Institut de Formation Professionnelle Oumar Bah (IFP-OBK)',
  address: 'Quartier Almamya, Conakry',
  phone: '+224 620 00 00 00',
  email: 'contact@ifp-obk.org',
);

final _vide = Etablissement(id: 4, name: 'Lycee Sans Coordonnees');

/// Le fond ambiant boucle indefiniment: pumpAndSettle ne rend jamais la main.
/// On avance donc un nombre fixe de frames, assez pour terminer la cascade.
Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _pumpDetails(
  WidgetTester tester,
  Etablissement etab, {
  Size size = const Size(1000, 900),
  void Function(Etablissement)? onSelect,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      // Theme neutre: AppTheme passe par google_fonts, indisponible en test.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF123D68)),
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: EtablissementDetailsScreen(
          etablissement: etab,
          onSelect: onSelect,
        ),
      ),
    ),
  );
  await _advance(tester);
}

/// Fiche empilee sur une page d'accueil: seule facon de verifier qu'elle se
/// retire avant de rendre la main a l'appelant.
Future<void> _pushDetails(
  WidgetTester tester,
  Etablissement etab, {
  required void Function(Etablissement) onSelect,
}) async {
  const size = Size(1000, 900);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF123D68)),
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EtablissementDetailsScreen(
                    etablissement: etab,
                    onSelect: onSelect,
                  ),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('ouvrir'));
  await _advance(tester);
}

void main() {
  testWidgets('le titre reprend le nom sans son sigle, affiche a part', (
    tester,
  ) async {
    await _pumpDetails(tester, _complet);

    // Deux fois: le rappel de la barre haute et le titre de l'en-tete.
    expect(
      find.text('Institut de Formation Professionnelle Oumar Bah'),
      findsNWidgets(2),
    );
    expect(find.text('IFP-OBK'), findsOneWidget);
    // Etiquette de nature deduite du nom, comme sur les tuiles du portail.
    expect(find.text('INSTITUT'), findsOneWidget);
  });

  testWidgets('chaque coordonnee renseignee est affichee et copiable', (
    tester,
  ) async {
    await _pumpDetails(tester, _complet);

    for (final value in [
      'Quartier Almamya, Conakry',
      '+224 620 00 00 00',
      'contact@ifp-obk.org',
    ]) {
      expect(find.text(value), findsWidgets);
    }
    expect(find.byIcon(Icons.copy_rounded), findsNWidgets(3));
    // Sans faux gestionnaire, le canal plateforme ne repond jamais en test et
    // le await de la copie reste suspendu: pas de confirmation affichee.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.tap(find.byIcon(Icons.copy_rounded).last);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(copied, 'contact@ifp-obk.org');
    expect(find.text('E-mail copié'), findsOneWidget);
  });

  testWidgets('une coordonnee absente reste listee, marquee non renseignee', (
    tester,
  ) async {
    await _pumpDetails(tester, _vide);

    expect(find.text('Non renseigné'), findsNWidgets(3));
    // Rien a copier tant qu'aucune valeur n'existe.
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });

  testWidgets('la fiche garde les reperes du portail', (tester) async {
    await _pumpDetails(tester, _complet);

    expect(find.text('COORDONNÉES'), findsOneWidget);
    expect(find.text('IDENTITÉ VISUELLE'), findsOneWidget);
    expect(
      find.text('Connexion chiffrée — vos données sont protégées'),
      findsOneWidget,
    );
    expect(find.byTooltip('Retour'), findsOneWidget);
  });

  testWidgets('sans action fournie, la fiche reste une consultation', (
    tester,
  ) async {
    await _pumpDetails(tester, _complet);

    expect(find.byIcon(Icons.login_rounded), findsNothing);
  });

  testWidgets('le bouton d_acces ferme la fiche et transmet l_etablissement', (
    tester,
  ) async {
    Etablissement? choisi;
    await _pushDetails(tester, _complet, onSelect: (etab) => choisi = etab);

    expect(
      find.text('Accéder à Institut de Formation Professionnelle Oumar Bah'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.login_rounded));
    await _advance(tester);

    expect(choisi, same(_complet));
    // La fiche ne doit pas rester empilee derriere la suite du parcours.
    expect(find.byType(EtablissementDetailsScreen), findsNothing);
    expect(find.text('ouvrir'), findsOneWidget);
  });
}
