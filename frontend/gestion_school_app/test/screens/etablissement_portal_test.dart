import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/models/etablissement.dart';
import 'package:gestion_school_app/screens/etablissement_details_screen.dart';
import 'package:gestion_school_app/screens/etablissement_selection_screen.dart';
import 'package:gestion_school_app/widgets/etablissement_identity.dart';

final _etablissements = [
  Etablissement(id: 1, name: 'Alpha College', address: 'Rue 1'),
  Etablissement(id: 2, name: 'Beta Lycee', address: 'Rue 2'),
  Etablissement(id: 3, name: 'Gamma Institut', address: 'Rue 3'),
];

/// pumpAndSettle est inutilisable sur cet ecran: le fond ambiant et le badge
/// "Securise" bouclent indefiniment, l'arbre ne se stabilise jamais. On avance
/// donc un nombre fixe de frames, assez pour terminer la cascade d'apparition.
Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _pumpPortal(
  WidgetTester tester, {
  Etablissement? resume,
  bool reduceMotion = false,
  Size size = const Size(1280, 900),
  List<Etablissement>? etablissements,
  String? loadError,
  Future<void> Function()? onRetry,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final provider = EtablissementProvider(TokenStorage());
  provider.setEtablissements(etablissements ?? _etablissements);
  if (resume != null) {
    await provider.selectEtablissement(resume);
  }

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [etablissementProvider.overrideWith((ref) => provider)],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: reduceMotion),
          child: EtablissementSelectionScreen(
            onSelected: (_) async {},
            loadError: loadError,
            onRetry: onRetry,
          ),
        ),
      ),
    ),
  );
  await _advance(tester);
}

void main() {
  testWidgets('affiche chaque etablissement une seule fois', (tester) async {
    await _pumpPortal(tester);

    for (final etab in _etablissements) {
      expect(find.text(etab.name), findsOneWidget);
    }
  });

  testWidgets('la pastille vole de la tuile vers la fiche', (tester) async {
    await _pumpPortal(tester, resume: _etablissements.first);

    // Un tag en double sur le meme ecran fait planter la transition: la carte
    // "Reprendre" et la grille ne doivent jamais montrer le meme etablissement.
    final tags = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((hero) => hero.tag)
        .toList();
    expect(tags.toSet().length, tags.length);
    expect(tags, contains(etabIdentityHeroTag(_etablissements.first)));

    // Ouverture de la fiche: le vol n'a lieu que si la destination porte le
    // meme tag que la tuile de depart.
    await tester.longPress(find.text(_etablissements.last.name));
    await _advance(tester);

    expect(find.byType(EtablissementDetailsScreen), findsOneWidget);
    final arrivee = tester
        .widgetList<Hero>(find.byType(Hero))
        .map((hero) => hero.tag);
    expect(arrivee, contains(etabIdentityHeroTag(_etablissements.last)));
  });

  testWidgets('la cascade laisse le contenu pleinement visible', (
    tester,
  ) async {
    await _pumpPortal(tester);

    // Regression: avec un Timer pour retarder chaque tuile, un arbre rendu
    // sans frame suivante restait bloque a l'opacite 0, donc une grille vide.
    //
    // On ne regarde que les Opacity au-dessus du nom: la tuile en contient une
    // autre pour le bouton de details, volontairement transparente hors survol.
    for (final etab in _etablissements) {
      final opacities = tester.widgetList<Opacity>(
        find.ancestor(
          of: find.text(etab.name),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacities, isNotEmpty);
      for (final opacity in opacities) {
        expect(opacity.opacity, moreOrLessEquals(1.0, epsilon: 0.001));
      }
    }
  });

  testWidgets('la carte Reprendre porte sa pastille et n_est pas dupliquee', (
    tester,
  ) async {
    await _pumpPortal(tester, resume: _etablissements[1]);

    expect(find.text('Reprendre'), findsOneWidget);
    expect(find.text('Dernier établissement utilisé'), findsOneWidget);
    // L'etablissement reprend sa place en haut, sans rester dans la grille.
    expect(find.text('Beta Lycee'), findsOneWidget);
  });

  testWidgets('les etablissements sont presentes en grille de tuiles', (
    tester,
  ) async {
    await _pumpPortal(tester);

    expect(find.byType(GridView), findsOneWidget);
    // Une action d'acces par etablissement, la carte de demande d'acces
    // n'en portant pas.
    expect(find.text('Accéder'), findsNWidgets(_etablissements.length));
    expect(
      find.text("Demander l'accès à un autre établissement"),
      findsOneWidget,
    );
  });

  testWidgets('la carte de demande d_acces ouvre la marche a suivre', (
    tester,
  ) async {
    await _pumpPortal(tester);

    await tester.tap(find.text("Demander l'accès à un autre établissement"));
    await _advance(tester);

    expect(find.text('Demander un accès'), findsOneWidget);
    // Le portail ne connait aucune API d'inscription: il oriente vers un
    // contact au lieu de promettre une action.
    expect(find.textContaining('contactez son administrateur'), findsOneWidget);
  });

  testWidgets('le titre, le sigle et l_etiquette derivent du nom', (
    tester,
  ) async {
    await _pumpPortal(
      tester,
      etablissements: [
        Etablissement(id: 7, name: 'Complexe Scolaire Omar Bah (CSOB)'),
        Etablissement(id: 8, name: 'Établissement Démo', address: 'Quartier'),
      ],
    );

    // Le sigle quitte le titre pour le sous-titre, ou il distingue les
    // homonymes; sans adresse, la nature de l'etablissement complete.
    expect(find.text('Complexe Scolaire Omar Bah'), findsOneWidget);
    expect(find.text('CSOB · Établissement scolaire'), findsOneWidget);
    expect(find.text('COMPLEXE'), findsOneWidget);

    // "Etablissement Demo" contient aussi "etablissement": l'etiquette DEMO
    // doit gagner sur le libelle generique.
    expect(find.text('Établissement Démo'), findsOneWidget);
    expect(find.text('Quartier'), findsOneWidget);
    expect(find.text('DEMO'), findsOneWidget);
  });

  testWidgets('la grille suit l_ordre alphabetique, accents compris', (
    tester,
  ) async {
    await _pumpPortal(
      tester,
      etablissements: [
        Etablissement(id: 1, name: 'Lycee Technique'),
        Etablissement(id: 2, name: 'Établissement Démo'),
        Etablissement(id: 3, name: 'Alpha College'),
      ],
    );

    double leftOf(String name) => tester.getTopLeft(find.text(name)).dx;
    double topOf(String name) => tester.getTopLeft(find.text(name)).dy;

    // Compare sur les codes UTF-16, "Établissement" tomberait apres "Lycee":
    // le tri doit ignorer l'accent.
    expect(topOf('Alpha College'), moreOrLessEquals(topOf('Lycee Technique')));
    expect(leftOf('Alpha College'), lessThan(leftOf('Établissement Démo')));
    expect(leftOf('Établissement Démo'), lessThan(leftOf('Lycee Technique')));
  });

  testWidgets('mouvement reduit: aucune opacite ni echelle animee', (
    tester,
  ) async {
    await _pumpPortal(tester, reduceMotion: true);

    for (final etab in _etablissements) {
      expect(find.text(etab.name), findsOneWidget);
    }
    // Le reveal se retire entierement du sous-arbre.
    expect(find.byType(AnimatedSwitcher), findsNothing);
    for (final scale in tester.widgetList<AnimatedScale>(
      find.byType(AnimatedScale),
    )) {
      expect(scale.scale, 1.0);
    }
  });

  testWidgets('la recherche filtre la liste', (tester) async {
    await _pumpPortal(tester);

    await tester.enterText(find.byType(TextField), 'gamma');
    await _advance(tester);

    expect(find.text('Gamma Institut'), findsOneWidget);
    expect(find.text('Alpha College'), findsNothing);
  });

  testWidgets('une recherche sans resultat affiche l_etat vide', (
    tester,
  ) async {
    await _pumpPortal(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await _advance(tester);

    expect(find.text('Aucun résultat pour "zzzz"'), findsOneWidget);
  });

  testWidgets('une base vide n_accuse pas le reseau', (tester) async {
    await _pumpPortal(tester, etablissements: []);

    expect(find.text('Aucun établissement disponible'), findsOneWidget);
    // Rien a reessayer: l'appel a abouti, la reponse etait vide.
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('un serveur injoignable se distingue d_une base vide', (
    tester,
  ) async {
    await _pumpPortal(
      tester,
      etablissements: [],
      loadError: 'Serveur injoignable.\nhttp://192.168.1.25:8000/api',
      onRetry: () async {},
    );

    // Regression: les deux cas portaient le meme texte, ce qui envoyait
    // chercher une panne de reseau quand la base etait simplement vide.
    expect(find.text('Impossible de joindre le serveur'), findsOneWidget);
    expect(find.text('Aucun établissement disponible'), findsNothing);
    // L'adresse reellement appelee est lisible a l'ecran: c'est elle qui
    // trahit une URL d'API figee a la compilation.
    expect(find.textContaining('192.168.1.25:8000'), findsOneWidget);
  });

  testWidgets('le bouton Reessayer relance le chargement', (tester) async {
    var appels = 0;
    await _pumpPortal(
      tester,
      etablissements: [],
      loadError: 'Serveur injoignable.',
      onRetry: () async => appels++,
    );

    await tester.tap(find.text('Réessayer'));
    await _advance(tester);

    // Sans lui, seul un rechargement complet de la page sortait de cet ecran.
    expect(appels, 1);
  });

  testWidgets('une recherche sans resultat n_offre pas de reessai', (
    tester,
  ) async {
    await _pumpPortal(
      tester,
      loadError: 'Serveur injoignable.',
      onRetry: () async {},
    );

    await tester.enterText(find.byType(TextField), 'zzzz');
    await _advance(tester);

    // La liste chargee est bien la: c'est le filtre qui ne rend rien.
    expect(find.text('Aucun résultat pour "zzzz"'), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
  });

  testWidgets('le contenu reste dans une bande centree sur grand ecran', (
    tester,
  ) async {
    await _pumpPortal(tester, size: const Size(1920, 1000));

    final row = tester.getRect(find.text('Alpha College'));
    // Sans plafond de largeur, la ligne s'etirait jusqu'aux bords.
    expect(row.left, greaterThan(400));
    expect(row.right, lessThan(1520));
  });
}
