/// Le repère de l'année de travail, en tête de l'écran Académique.
///
/// L'information y arrivait noyée au milieu d'un bandeau — « Année active :
/// 2025-2026 » — sans ses dates ni où l'on en était dedans. Or c'est cet
/// écran qui ouvre, ferme et bascule les années.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/features/academics/data/annees_scolaires_repository.dart';
import 'package:gestion_school_app/features/academics/domain/annee_scolaire.dart';
import 'package:gestion_school_app/features/academics/presentation/annee_scolaire_controller.dart';
import 'package:gestion_school_app/features/academics/presentation/widgets/carte_annee_active.dart';

/// Une année en cours, calée sur la date du jour: l'avancement n'a de sens
/// qu'à l'intérieur de la période, et un test figé au calendrier serait faux
/// six mois plus tard.
AnneeScolaire _enCours() {
  final aujourdHui = DateTime.now();
  final debut = aujourdHui.subtract(const Duration(days: 90));
  final fin = aujourdHui.add(const Duration(days: 210));
  return AnneeScolaire(
    id: 2,
    nom: '2025-2026',
    debut: debut.toIso8601String().substring(0, 10),
    fin: fin.toIso8601String().substring(0, 10),
    estCourante: true,
  );
}

const _close = AnneeScolaire(
  id: 1,
  nom: '2024-2025',
  debut: '2024-09-01',
  fin: '2025-06-30',
  estCloturee: true,
);

class _FauxDepot extends AnneesScolairesRepository {
  final List<AnneeScolaire> annees;

  _FauxDepot(this.annees) : super(Dio());

  @override
  Future<List<AnneeScolaire>> fetchAnnees() async => annees;
}

Future<AnneeScolaireController> _controleur(List<AnneeScolaire> annees) async {
  FlutterSecureStorage.setMockInitialValues({});
  final controleur = AnneeScolaireController(TokenStorage(), _FauxDepot(annees));
  await controleur.hydrater();
  await controleur.charger();
  return controleur;
}

Future<void> _monter(
  WidgetTester tester,
  AnneeScolaireController controleur, {
  int classes = 0,
  int eleves = 0,
  VoidCallback? onOuvrirAnnee,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [anneeScolaireProvider.overrideWith((ref) => controleur)],
      child: MaterialApp(
        home: Scaffold(
          body: CarteAnneeActive(
            classes: classes,
            eleves: eleves,
            onOuvrirAnnee: onOuvrirAnnee,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('la carte nomme l_annee et sa periode', (tester) async {
    await _monter(tester, await _controleur([_enCours()]));

    expect(find.text('2025-2026'), findsOneWidget);
    expect(find.textContaining('→'), findsOneWidget);
  });

  testWidgets('l_avancement se montre sur une annee en cours', (tester) async {
    await _monter(tester, await _controleur([_enCours()]));

    expect(find.byKey(const Key('avancement-annee')), findsOneWidget);
    expect(find.textContaining('mois sur'), findsOneWidget);
  });

  testWidgets('hors de sa periode, aucune barre ne ment', (tester) async {
    // Une barre a 100 % se lirait comme une progression, alors qu'on est
    // simplement apres la fin.
    await _monter(tester, await _controleur([_close]));

    expect(find.byKey(const Key('avancement-annee')), findsNothing);
  });

  testWidgets('les effectifs rattaches sont affiches', (tester) async {
    await _monter(
      tester,
      await _controleur([_enCours()]),
      classes: 12,
      eleves: 215,
    );

    expect(find.text('12'), findsOneWidget);
    expect(find.text('classes'), findsOneWidget);
    expect(find.text('215'), findsOneWidget);
    expect(find.text('élèves'), findsOneWidget);
  });

  testWidgets('un seul element ne prend pas le pluriel', (tester) async {
    await _monter(
      tester,
      await _controleur([_enCours()]),
      classes: 1,
      eleves: 1,
    );

    expect(find.text('classe'), findsOneWidget);
    expect(find.text('élève'), findsOneWidget);
  });

  testWidgets('l_etat de l_annee porte sa pastille', (tester) async {
    await _monter(tester, await _controleur([_close]));

    expect(find.text('Clôturée'), findsOneWidget);
  });

  testWidgets('sans annee, la carte appelle a en ouvrir une', (tester) async {
    await _monter(tester, await _controleur([]));

    expect(find.text('Aucune année scolaire'), findsOneWidget);
  });

  testWidgets('le bouton d_ouverture remonte l_action', (tester) async {
    var ouvertures = 0;
    await _monter(
      tester,
      await _controleur([]),
      onOuvrirAnnee: () => ouvertures++,
    );

    await tester.tap(find.byKey(const Key('ouvrir-premiere-annee')));
    await tester.pump();

    expect(ouvertures, 1);
  });

  testWidgets('sans droit d_ecriture, aucune ouverture n_est proposee', (
    tester,
  ) async {
    await _monter(tester, await _controleur([_enCours()]));

    expect(find.byKey(const Key('ouvrir-annee-suivante')), findsNothing);
  });
}
