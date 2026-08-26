import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/library/domain/book.dart';
import 'package:gestion_school_app/features/library/presentation/widgets/books_panel.dart';

/// Le catalogue papier tel que l'ecran le montre.
///
/// L'ancien affichait « 18/20 » d'apres une colonne saisie a la main qui ne
/// bougeait jamais: la pastille ment tant que le serveur ne derive pas la
/// disponibilite, et ces tests protegent ce qu'elle raconte.
const _livres = [
  Book(
    id: 1,
    title: 'Algebre 1',
    author: 'A. Diallo',
    isbn: '978-2-1234-5680-3',
    quantityTotal: 5,
    quantityAvailable: 3,
    quantityBorrowed: 2,
  ),
  Book(
    id: 2,
    title: 'Exemplaire unique',
    author: 'M. Keita',
    isbn: '978-2-1234-5681-0',
    quantityTotal: 1,
    quantityAvailable: 0,
    quantityBorrowed: 1,
    subject: 'Physique',
    publisher: 'Donniya',
    publishedYear: 2019,
    shelfLocation: 'B3',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<Book> livres = _livres,
  String recherche = '',
  String filtre = '',
  ValueChanged<String>? onRechercheChanged,
  ValueChanged<String>? onFiltreChanged,
  void Function(Book)? onModifier,
  void Function(Book)? onSupprimer,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BooksPanel(
            livres: livres,
            recherche: recherche,
            filtreDisponibilite: filtre,
            onRechercheChanged: onRechercheChanged ?? (_) {},
            onFiltreChanged: onFiltreChanged ?? (_) {},
            onModifier: onModifier,
            onSupprimer: onSupprimer,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('la pastille montre le rayon sur le fonds total', (tester) async {
    await _pump(tester);

    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
  });

  testWidgets('les exemplaires sortis sont annonces', (tester) async {
    await _pump(tester);

    expect(find.textContaining('2 exemplaire(s) emprunté(s)'), findsOneWidget);
  });

  testWidgets('les complements renseignes s_affichent, les vides se taisent', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.textContaining('Physique • Donniya • 2019 • rayon B3'),
      findsOneWidget,
    );
    // Le premier ouvrage n'en porte aucun: pas de ligne vide ni de
    // separateurs orphelins sous son titre.
    expect(find.textContaining('•  •'), findsNothing);
  });

  testWidgets('une recherche remonte le terme saisi', (tester) async {
    String? recu;
    await _pump(tester, onRechercheChanged: (valeur) => recu = valeur);

    await tester.enterText(find.byKey(const Key('books-search')), 'algebre');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(recu, 'algebre');
  });

  testWidgets('choisir un filtre remonte son code', (tester) async {
    String? recu;
    await _pump(tester, onFiltreChanged: (valeur) => recu = valeur);

    await tester.tap(find.text('Disponibles'));
    await tester.pump();

    expect(recu, 'available');
  });

  testWidgets('sans droit d_ecriture, aucune action n_est proposee', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('le droit d_ecriture seul n_ouvre pas la suppression', (
    tester,
  ) async {
    await _pump(tester, onModifier: (_) {});

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();

    expect(find.text('Modifier'), findsOneWidget);
    expect(find.text('Supprimer'), findsNothing);
  });

  testWidgets('modifier remonte l_ouvrage vise', (tester) async {
    Book? recu;
    await _pump(tester, onModifier: (livre) => recu = livre);

    await tester.tap(find.byIcon(Icons.more_vert).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    expect(recu?.id, 1);
  });

  testWidgets('un catalogue vide le dit selon le filtre', (tester) async {
    await _pump(tester, livres: const []);
    expect(find.text('Aucun ouvrage enregistré.'), findsOneWidget);

    await _pump(tester, livres: const [], recherche: 'zzz');
    expect(find.text('Aucun ouvrage ne correspond.'), findsOneWidget);
  });
}
