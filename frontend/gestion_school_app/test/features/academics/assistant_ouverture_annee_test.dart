/// L'ecran qui ouvre une annee scolaire.
///
/// Preparer une rentree demandait de ressaisir a la main les classes, leurs
/// matieres, les affectations et l'emploi du temps -- pres de quatre cents
/// lignes pour une structure qui change peu d'une annee sur l'autre.
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
import 'package:gestion_school_app/features/academics/presentation/widgets/assistant_ouverture_annee.dart';

const _courante = AnneeScolaire(
  id: 2,
  nom: '2025-2026',
  debut: '2025-09-01',
  fin: '2026-06-30',
  estCourante: true,
);

class _FauxDepot extends AnneesScolairesRepository {
  final Object? erreur;
  Map<String, dynamic>? dernierAppel;

  _FauxDepot({this.erreur}) : super(Dio());

  @override
  Future<List<AnneeScolaire>> fetchAnnees() async => const [_courante];

  @override
  Future<Map<String, dynamic>> ouvrirAnnee({
    required String nom,
    required String debut,
    required String fin,
    int? sourceId,
    bool dupliquerClasses = true,
    bool dupliquerMatieres = true,
    bool dupliquerAffectations = true,
    bool dupliquerEmploiDuTemps = true,
    bool activer = false,
    bool cloturerSource = false,
  }) async {
    dernierAppel = {
      'nom': nom,
      'debut': debut,
      'fin': fin,
      'classes': dupliquerClasses,
      'matieres': dupliquerMatieres,
      'affectations': dupliquerAffectations,
      'edt': dupliquerEmploiDuTemps,
      'activer': activer,
      'cloturer': cloturerSource,
    };
    if (erreur != null) throw erreur!;
    return {
      'id': 3,
      'name': nom,
      'reprise': {
        'classes': 15,
        'matieres': 31,
        'affectations': 31,
        'creneaux': 14,
      },
    };
  }
}

Future<_FauxDepot> _monter(WidgetTester tester, {Object? erreur}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final depot = _FauxDepot(erreur: erreur);
  final controleur = AnneeScolaireController(TokenStorage(), depot);
  await controleur.hydrater();
  await controleur.charger();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        anneesScolairesRepositoryProvider.overrideWithValue(depot),
        anneeScolaireProvider.overrideWith((ref) => controleur),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AssistantOuvertureAnnee()),
      ),
    ),
  );
  await tester.pump();
  return depot;
}

void main() {
  testWidgets('l_annee suivante est proposee d_emblee', (tester) async {
    // « 2025-2026 » appelle « 2026-2027 »: laisser l'ecran vide obligerait
    // a retaper ce que le serveur sait deja.
    await _monter(tester);

    final champ = tester.widget<TextField>(
      find.byKey(const Key('ouverture-nom')),
    );
    expect(champ.controller?.text, '2026-2027');
    expect(find.text('2026-09-01'), findsOneWidget);
    expect(find.text('2027-06-30'), findsOneWidget);
  });

  testWidgets('l_ecran annonce que les eleves ne bougent pas', (tester) async {
    await _monter(tester);

    expect(
      find.textContaining('Les élèves ne sont pas déplacés'),
      findsOneWidget,
    );
  });

  testWidgets('ouvrir transmet les choix et affiche le compte rendu', (
    tester,
  ) async {
    final depot = await _monter(tester);

    await tester.tap(find.byKey(const Key('ouverture-activer')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ouverture-valider')));
    await tester.pumpAndSettle();

    expect(depot.dernierAppel!['nom'], '2026-2027');
    expect(depot.dernierAppel!['activer'], isTrue);
    expect(depot.dernierAppel!['cloturer'], isFalse);

    // Le detail plutot qu'un « operation reussie » qui ne dirait pas si les
    // quinze classes attendues sont bien la.
    expect(find.byKey(const Key('ouverture-compte-rendu')), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('31'), findsNWidgets(2));
    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('decocher les classes ferme les niveaux suivants', (
    tester,
  ) async {
    // Une matiere tient a sa classe, une affectation a sa matiere: laisser
    // cocher des cases sans effet tromperait sur ce qui sera repris.
    await _monter(tester);

    await tester.tap(find.byKey(const Key('ouverture-classes')));
    await tester.pump();

    for (final cle in ['ouverture-matieres', 'ouverture-affectations', 'ouverture-edt']) {
      final case_ = tester.widget<CheckboxListTile>(find.byKey(Key(cle)));
      expect(case_.value, isFalse, reason: cle);
      expect(case_.onChanged, isNull, reason: cle);
    }
  });

  testWidgets('un refus du serveur est explique, pas recopie', (tester) async {
    final options = RequestOptions(path: '/academic-years/ouvrir/');
    await _monter(
      tester,
      erreur: DioException(
        requestOptions: options,
        response: Response(
          requestOptions: options,
          statusCode: 403,
          data: {'detail': 'refuse'},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('ouverture-valider')));
    await tester.pumpAndSettle();

    expect(
      find.text('L\'ouverture d\'une année est réservée à la direction.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ouverture-compte-rendu')), findsNothing);
  });

  testWidgets('sans nom, rien ne part vers le serveur', (tester) async {
    final depot = await _monter(tester);

    await tester.enterText(find.byKey(const Key('ouverture-nom')), '');
    await tester.tap(find.byKey(const Key('ouverture-valider')));
    await tester.pump();

    expect(depot.dernierAppel, isNull);
    expect(find.byKey(const Key('ouverture-erreur')), findsOneWidget);
  });
}
