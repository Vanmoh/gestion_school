/// L'etagere numerique: series, matieres repliees, documents.
///
/// La rubrique « Bibliotheque » ne connaissait que l'ouvrage physique. Le
/// fonds documentaire -- annales et brochures rangees par serie -- n'avait
/// aucun ecran.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/library/domain/library_collection.dart';
import 'package:gestion_school_app/features/library/domain/library_document.dart';
import 'package:gestion_school_app/features/library/presentation/widgets/library_document_tree.dart';

List<LibraryCollection> _series() => const [
  LibraryCollection(
    id: 1,
    code: 'TSExp',
    label: 'Terminale Sciences Expérimentales',
    documentCount: 3,
    categories: [
      LibraryCategory(id: 11, name: 'Mathematiques', documentCount: 2),
      LibraryCategory(id: 12, name: 'Philosophie', documentCount: 1),
    ],
  ),
  LibraryCollection(
    id: 2,
    code: 'TLL',
    label: 'Terminale Lettres-Langues',
    documentCount: 1,
    categories: [LibraryCategory(id: 21, name: 'Litterature', documentCount: 1)],
  ),
];

List<LibraryDocument> _documents() => const [
  LibraryDocument(
    id: 101,
    title: 'Suites-numeriques',
    categoryId: 11,
    categoryName: 'Mathematiques',
    sizeBytes: 3 * 1024 * 1024,
    isDownloaded: true,
    importError: '',
  ),
  LibraryDocument(
    id: 102,
    title: 'BAC-2019-corrige',
    categoryId: 11,
    categoryName: 'Mathematiques',
    sizeBytes: 0,
    isDownloaded: false,
    importError: '',
  ),
  LibraryDocument(
    id: 103,
    title: 'Le-desir',
    categoryId: 12,
    categoryName: 'Philosophie',
    sizeBytes: 0,
    isDownloaded: false,
    importError: 'HTTPError: 401',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  String recherche = '',
  int? documentEnCours,
  double? progressionEnCours,
  void Function(LibraryCollection)? onCollectionChanged,
  void Function(LibraryDocument)? onOuvrir,
  List<LibraryDocument>? documents,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LibraryDocumentTree(
            collections: _series(),
            selectedCollectionId: 1,
            documents: documents ?? _documents(),
            recherche: recherche,
            documentEnCours: documentEnCours,
            progressionEnCours: progressionEnCours,
            onCollectionChanged: onCollectionChanged ?? (_) {},
            onOuvrir: onOuvrir ?? (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('chaque serie porte son compteur', (tester) async {
    await _pump(tester);

    expect(
      find.text('Terminale Sciences Expérimentales (3)'),
      findsOneWidget,
    );
    expect(find.text('Terminale Lettres-Langues (1)'), findsOneWidget);
  });

  testWidgets('les matieres s_affichent repliees', (tester) async {
    await _pump(tester);

    expect(find.text('Mathematiques'), findsOneWidget);
    expect(find.text('2 documents'), findsOneWidget);
    expect(find.text('1 document'), findsOneWidget);
    // 322 documents deroules d'entree noieraient le premier regard.
    expect(find.text('Suites-numeriques'), findsNothing);
  });

  testWidgets('ouvrir une matiere montre ses documents', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Mathematiques'));
    await tester.pumpAndSettle();

    expect(find.text('Suites-numeriques'), findsOneWidget);
    expect(find.text('BAC-2019-corrige', skipOffstage: false), findsOneWidget);
    expect(find.text('3.0 Mo'), findsOneWidget);
  });

  testWidgets('un document mort a la source ne s_ouvre pas', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Philosophie'));
    await tester.pumpAndSettle();

    expect(find.textContaining('indisponible à la source'), findsOneWidget);
    final bouton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.open_in_new),
        matching: find.byType(IconButton),
      ),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('un clic remonte le document a ouvrir', (tester) async {
    LibraryDocument? demande;
    await _pump(tester, onOuvrir: (document) => demande = document);

    await tester.tap(find.text('Mathematiques'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suites-numeriques'));
    await tester.pump();

    expect(demande?.id, 101);
  });

  testWidgets('changer de serie remonte le choix', (tester) async {
    LibraryCollection? choisie;
    await _pump(tester, onCollectionChanged: (serie) => choisie = serie);

    await tester.tap(find.text('Terminale Lettres-Langues (1)'));
    await tester.pump();

    expect(choisie?.code, 'TLL');
  });

  testWidgets('une recherche traverse les matieres', (tester) async {
    await _pump(tester, recherche: 'desir', documents: [_documents().last]);

    // Liste plate: ranger le resultat dans un dossier replie le cacherait.
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text('Le-desir'), findsOneWidget);
    expect(find.textContaining('Philosophie'), findsOneWidget);
  });

  testWidgets('une recherche sans resultat le dit', (tester) async {
    await _pump(tester, recherche: 'introuvable', documents: const []);

    expect(find.text('Aucun document ne porte ces mots.'), findsOneWidget);
  });

  testWidgets('le document en cours d_ouverture montre son attente', (
    tester,
  ) async {
    await _pump(tester, documentEnCours: 101);

    await tester.tap(find.text('Mathematiques'));
    // Pas de pumpAndSettle: la roue d'attente tourne sans fin, le test
    // n'atteindrait jamais l'immobilite.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('sans taille connue, l_attente reste indeterminee', (
    tester,
  ) async {
    await _pump(tester, documentEnCours: 101);

    await tester.tap(find.text('Mathematiques'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final rond = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    // value null: la roue tourne sans fin, seul affichage honnete tant que le
    // poids total n'a pas ete annonce.
    expect(rond.value, isNull);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('des que la taille est connue, l_attente se chiffre', (
    tester,
  ) async {
    // Le fonds va de 50 Ko a 127 Mo: une roue identique dans les deux cas ne
    // dit pas au lecteur s'il attend une seconde ou une minute.
    await _pump(tester, documentEnCours: 101, progressionEnCours: 0.42);

    await tester.tap(find.text('Mathematiques'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final rond = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(rond.value, closeTo(0.42, 0.001));
    expect(find.text('42 %'), findsOneWidget);
  });

  testWidgets('la progression ne s_affiche que sur le document ouvert', (
    tester,
  ) async {
    LibraryDocument? demande;
    await _pump(
      tester,
      documentEnCours: 101,
      progressionEnCours: 0.42,
      onOuvrir: (document) => demande = document,
    );

    await tester.tap(find.text('Mathematiques'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 102 est dans la meme matiere, donc affiche juste a cote: un pourcentage
    // qui deborderait sur ses voisins laisserait croire que toute la matiere
    // se telecharge.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('42 %'), findsOneWidget);

    final voisin = find.ancestor(
      of: find.text('BAC-2019-corrige'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: voisin, matching: find.byIcon(Icons.open_in_new)),
      findsOneWidget,
    );

    // Et il s'ouvre toujours: le telechargement d'un document n'immobilise
    // pas l'etagere.
    await tester.tap(voisin);
    await tester.pump();
    expect(demande?.id, 102);
  });
}
