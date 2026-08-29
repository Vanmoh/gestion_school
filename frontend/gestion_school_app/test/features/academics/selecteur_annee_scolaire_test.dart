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

/// Une annee passee mais encore ouverte: ni active, ni close. C'est le cas
/// que rien ne signalait -- on y saisissait sans le savoir.
const _consultee = AnneeScolaire(
  id: 3,
  nom: '2023-2024',
  debut: '2023-09-01',
  fin: '2024-06-30',
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
      // une annee close sans le savoir. Il se lit desormais sur une
      // pastille et non plus entre parentheses dans le libelle.
      expect(find.text('2024-2025'), findsWidgets);
      expect(find.text('Clôturée'), findsOneWidget);
      expect(find.text('Active'), findsWidgets);
    });

    testWidgets('choisir une annee la retient', (tester) async {
      final controleur = await _controleur([_passee, _courante]);
      await _monter(tester, controleur, const SelecteurAnneeScolaire());

      await tester.tap(find.byKey(const Key('selecteur-annee')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clôturée'));
      await tester.pumpAndSettle();

      expect(controleur.selectionnee?.id, _passee.id);
    });

    testWidgets('sans aucune annee, il le dit au lieu de disparaitre', (
      tester,
    ) async {
      // Il rendait un `SizedBox.shrink()`: l'utilisateur ne savait alors pas
      // s'il travaillait sur une annee, ni laquelle.
      final controleur = await _controleur([]);
      await _monter(tester, controleur, const SelecteurAnneeScolaire());

      expect(find.byKey(const Key('annee-absente')), findsOneWidget);
      expect(find.text('Aucune année'), findsOneWidget);
    });

    testWidgets('en version etendue, il montre la periode', (tester) async {
      final controleur = await _controleur([_courante]);
      await _monter(
        tester,
        controleur,
        const SelecteurAnneeScolaire(etendu: true),
      );

      expect(find.text('1 sept. 2025 → 30 juin 2026'), findsOneWidget);
    });

    testWidgets('la pastille nomme l_etat de l_annee affichee', (tester) async {
      final controleur = await _controleur([_courante]);
      await _monter(tester, controleur, const SelecteurAnneeScolaire());

      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('une annee consultee porte sa propre pastille', (tester) async {
      final controleur = await _controleur([_consultee, _courante]);
      controleur.selectionner(_consultee);
      await _monter(tester, controleur, const SelecteurAnneeScolaire());

      expect(find.text('Consultée'), findsWidgets);
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

    testWidgets('il previent aussi sur une annee passee non close', (
      tester,
    ) async {
      // Le bandeau ne se levait que sur une annee cloturee: consulter une
      // annee passee mais ouverte ne declenchait rien, et la saisie y
      // partait sans que rien ne le signale.
      final controleur = await _controleur([_consultee, _courante]);
      controleur.selectionner(_consultee);
      await _monter(tester, controleur, const BandeauAnneeCloturee());

      expect(
        find.byKey(const Key('bandeau-annee-cloturee')),
        findsOneWidget,
      );
      expect(find.textContaining('n’est pas l’année en cours'), findsOneWidget);
    });

    testWidgets('il offre de revenir a l_annee en cours', (tester) async {
      final controleur = await _controleur([_consultee, _courante]);
      controleur.selectionner(_consultee);
      await _monter(tester, controleur, const BandeauAnneeCloturee());

      await tester.tap(find.byKey(const Key('retour-annee-courante')));
      await tester.pumpAndSettle();

      expect(controleur.selectionnee?.id, _courante.id);
    });

    testWidgets('sans annee en cours, il n_offre pas de retour', (
      tester,
    ) async {
      final controleur = await _controleur([_passee]);
      await _monter(tester, controleur, const BandeauAnneeCloturee());

      expect(find.byKey(const Key('retour-annee-courante')), findsNothing);
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
