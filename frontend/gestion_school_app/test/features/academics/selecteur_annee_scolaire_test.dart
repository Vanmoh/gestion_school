/// La bascule d'annee dans l'application.
///
/// « Notes », « Examens » et « Academique » avaient chacune son selecteur,
/// et rien ne les accordait: on pouvait saisir sur une annee tout en
/// consultant l'emploi du temps d'une autre. L'annee vit desormais dans la
/// coquille, et voyage dans l'en-tete pose par le client HTTP.
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
import 'package:gestion_school_app/features/academics/presentation/widgets/selecteur_annee_scolaire.dart';

const _courante = AnneeScolaire(
  id: 2,
  nom: '2025-2026',
  debut: '2025-09-01',
  fin: '2026-06-30',
  estCourante: true,
);

const _passee = AnneeScolaire(
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
  final controleur = AnneeScolaireController(
    TokenStorage(),
    _FauxDepot(annees),
  );
  await controleur.hydrater();
  await controleur.charger();
  return controleur;
}

Future<void> _monter(
  WidgetTester tester,
  AnneeScolaireController controleur,
  Widget enfant,
) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [anneeScolaireProvider.overrideWith((ref) => controleur)],
      child: MaterialApp(home: Scaffold(body: enfant)),
    ),
  );
  await tester.pump();
}

void main() {
  group('AnneeScolaireController', () {
    test('au chargement, il retient l_annee en cours', () async {
      final controleur = await _controleur([_passee, _courante]);

      expect(controleur.selectionnee?.id, _courante.id);
      expect(controleur.consulteUneAnneeCloturee, isFalse);
    });

    test('sans annee en cours, il prend la premiere servie', () async {
      // Le serveur trie par date decroissante: la premiere est la plus
      // recente, et c'est celle qu'on veut regarder par defaut.
      final controleur = await _controleur([_passee]);

      expect(controleur.selectionnee?.id, _passee.id);
    });

    test('choisir une annee cloturee le signale', () async {
      final controleur = await _controleur([_passee, _courante]);
      await controleur.selectionner(_passee);

      expect(controleur.consulteUneAnneeCloturee, isTrue);
    });

    test('une liste vide ne selectionne rien', () async {
      final controleur = await _controleur(const []);

      expect(controleur.selectionnee, isNull);
      expect(controleur.consulteUneAnneeCloturee, isFalse);
    });
  });

  group('SelecteurAnneeScolaire', () {
    testWidgets('avec plusieurs annees, il ouvre un choix', (tester) async {
      final controleur = await _controleur([_passee, _courante]);
      await _monter(tester, controleur, const SelecteurAnneeScolaire());

      expect(find.byKey(const Key('selecteur-annee')), findsOneWidget);
      expect(find.text('2025-2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('selecteur-annee')));
      await tester.pumpAndSettle();

      // L'etat de chaque annee se lit dans la liste: on ne bascule pas sur
      // une annee close sans le savoir.
      expect(find.text('2024-2025 (clôturée)'), findsOneWidget);
      expect(find.text('2025-2026 (en cours)'), findsOneWidget);
    });

    testWidgets('choisir une annee la retient', (tester) async {
      final controleur = await _controleur([_passee, _courante]);
      await _monter(tester, controleur, const SelecteurAnneeScolaire());

      await tester.tap(find.byKey(const Key('selecteur-annee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2024-2025 (clôturée)'));
      await tester.pumpAndSettle();

      expect(controleur.selectionnee?.id, _passee.id);
    });

    testWidgets('une seule annee s_affiche sans menu', (tester) async {
      // Proposer une bascule entre une seule option promettrait un choix
      // qui n'existe pas.
      final controleur = await _controleur([_courante]);
      await _monter(tester, controleur, const SelecteurAnneeScolaire());

      expect(find.byKey(const Key('selecteur-annee')), findsNothing);
      expect(find.byKey(const Key('annee-unique')), findsOneWidget);
    });
  });

  group('BandeauAnneeCloturee', () {
    testWidgets('il previent quand l_annee consultee est close', (
      tester,
    ) async {
      final controleur = await _controleur([_passee, _courante]);
      await controleur.selectionner(_passee);
      await _monter(tester, controleur, const BandeauAnneeCloturee());

      expect(find.byKey(const Key('bandeau-annee-cloturee')), findsOneWidget);
      expect(find.textContaining('clôturée'), findsOneWidget);
      expect(find.textContaining('direction'), findsOneWidget);
    });

    testWidgets('il se tait sur l_annee en cours', (tester) async {
      final controleur = await _controleur([_passee, _courante]);
      // Choix explicite: le stockage simule survit d'un test a l'autre, et
      // l'annee retenue par le precedent reviendrait ici.
      await controleur.selectionner(_courante);
      await _monter(tester, controleur, const BandeauAnneeCloturee());

      expect(find.byKey(const Key('bandeau-annee-cloturee')), findsNothing);
    });
  });
}
