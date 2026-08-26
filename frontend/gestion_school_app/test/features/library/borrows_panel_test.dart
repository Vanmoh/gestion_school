import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/library/domain/book.dart';
import 'package:gestion_school_app/features/library/presentation/widgets/borrows_panel.dart';

/// Le suivi des prets.
///
/// Aucun retour n'etait possible avant: `returned_at` n'etait ecrit nulle
/// part et un pret durait indefiniment. Le bouton « Rendre » et la lecture
/// du retard sont ce que ces tests retiennent.
final _enCours = Borrow(
  id: 10,
  studentId: 1,
  bookId: 1,
  bookTitle: 'Algebre 1',
  studentFullName: 'Awa Traore',
  studentMatricule: 'M-001',
  borrowedAt: DateTime(2026, 8, 1),
  dueDate: DateTime(2026, 8, 15),
  returnedAt: null,
  isReturned: false,
  daysLate: 0,
  penaltyAmount: 0,
  penaltyDue: 0,
);

final _enRetard = Borrow(
  id: 11,
  studentId: 2,
  bookId: 1,
  bookTitle: 'Geometrie',
  studentFullName: 'Moussa Kone',
  studentMatricule: 'M-002',
  borrowedAt: DateTime(2026, 7, 1),
  dueDate: DateTime(2026, 7, 10),
  returnedAt: null,
  isReturned: false,
  daysLate: 3,
  penaltyAmount: 0,
  penaltyDue: 750,
);

final _rendu = Borrow(
  id: 12,
  studentId: 3,
  bookId: 2,
  bookTitle: 'Histoire du Mali',
  studentFullName: 'Fatou Sissoko',
  studentMatricule: 'M-003',
  borrowedAt: DateTime(2026, 6, 1),
  dueDate: DateTime(2026, 6, 15),
  returnedAt: DateTime(2026, 6, 18),
  isReturned: true,
  daysLate: 3,
  penaltyAmount: 750,
  penaltyDue: 750,
);

Future<void> _pump(
  WidgetTester tester, {
  List<Borrow>? emprunts,
  String filtre = '',
  ValueChanged<String>? onFiltreChanged,
  void Function(Borrow)? onRendre,
  void Function(Borrow)? onSupprimer,
  bool masquerEmprunteur = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BorrowsPanel(
            emprunts: emprunts ?? [_enCours, _enRetard, _rendu],
            filtre: filtre,
            onFiltreChanged: onFiltreChanged ?? (_) {},
            onRendre: onRendre,
            onSupprimer: onSupprimer,
            masquerEmprunteur: masquerEmprunteur,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('un retard annonce ses jours et ce qu_il coute', (tester) async {
    await _pump(tester);

    expect(find.textContaining('3 jour(s) de retard'), findsOneWidget);
    expect(find.textContaining('750 F dus'), findsOneWidget);
  });

  testWidgets('un pret rendu porte sa date et sa penalite', (tester) async {
    await _pump(tester);

    expect(find.textContaining('rendu le 18/06/2026'), findsOneWidget);
    expect(find.textContaining('pénalité 750 F'), findsOneWidget);
  });

  testWidgets('seuls les prets en cours proposent le retour', (tester) async {
    await _pump(tester, onRendre: (_) {});

    // Deux prets en cours sur trois lignes: le rendu n'a pas de bouton.
    expect(find.text('Rendre'), findsNWidgets(2));
  });

  testWidgets('sans droit d_ecriture, aucun retour n_est propose', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Rendre'), findsNothing);
  });

  testWidgets('rendre remonte le pret vise', (tester) async {
    Borrow? recu;
    await _pump(tester, emprunts: [_enRetard], onRendre: (pret) => recu = pret);

    await tester.tap(find.text('Rendre'));
    await tester.pump();

    expect(recu?.id, 11);
  });

  testWidgets('choisir un etat remonte son code', (tester) async {
    String? recu;
    await _pump(tester, onFiltreChanged: (valeur) => recu = valeur);

    await tester.tap(find.text('En retard'));
    await tester.pump();

    expect(recu, 'late');
  });

  testWidgets('l_ecran « mes emprunts » tait l_emprunteur', (tester) async {
    await _pump(tester, emprunts: [_enCours], masquerEmprunteur: true);

    expect(find.textContaining('M-001'), findsNothing);
    expect(find.text('Algebre 1'), findsOneWidget);
  });

  testWidgets('l_emprunteur est nomme dans la vue d_ensemble', (tester) async {
    await _pump(tester, emprunts: [_enCours]);

    expect(find.textContaining('M-001 • Awa Traore'), findsOneWidget);
  });
}
