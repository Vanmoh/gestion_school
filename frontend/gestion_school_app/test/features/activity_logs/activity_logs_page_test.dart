/// Le journal d'audit, et les deux questions qu'on lui pose vraiment.
///
/// « Qui a fait ça » et « qu'est-ce qui s'est passé dans les paiements »
/// n'étaient pas posables: l'écran n'offrait que la méthode HTTP, le succès et
/// les dates, alors que le serveur filtre depuis toujours sur l'auteur, le
/// rôle et le module. Ces tests tiennent les trois filtres qui manquaient, et
/// le fait qu'ils partent au serveur plutôt que de trier la page en mémoire.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/activity_logs/data/activity_logs_repository.dart';
import 'package:gestion_school_app/features/activity_logs/domain/activity_log_models.dart';
import 'package:gestion_school_app/features/activity_logs/presentation/activity_logs_controller.dart';
import 'package:gestion_school_app/features/activity_logs/presentation/activity_logs_page.dart';

const _acceptee = LigneDuJournal(
  id: 1,
  quand: '2026-01-12T08:30:00Z',
  auteur: 'Awa Traore',
  role: 'accountant',
  action: 'Encaissement',
  methode: 'POST',
  module: 'payments',
  chemin: '/api/payments/',
  cible: '',
  statutHttp: 201,
  reussi: true,
  adresseIp: '10.0.0.4',
  details: '',
  etablissement: 'Lycee Oumar Bah',
);

const _refusee = LigneDuJournal(
  id: 2,
  quand: '2026-01-12T09:15:00Z',
  auteur: 'Moussa Diallo',
  role: 'teacher',
  action: 'Suppression de note',
  methode: 'DELETE',
  module: 'grades',
  chemin: '/api/grades/12/',
  cible: '12',
  statutHttp: 403,
  reussi: false,
  adresseIp: '10.0.0.9',
  details: 'Periode deja validee',
  etablissement: 'Lycee Oumar Bah',
);

class _FauxDepot extends ActivityLogsRepository {
  /// Les requêtes que l'écran a réellement adressées au serveur.
  final List<Map<String, dynamic>> requetes = [];
  final List<String> exports = [];

  _FauxDepot() : super(Dio());

  @override
  Future<List<LigneDuJournal>> fetchLignes(
    FiltreDuJournal filtre, {
    CancelToken? annulation,
  }) async {
    requetes.add(filtre.enRequete());
    return const [_acceptee, _refusee];
  }

  @override
  Future<RepertoireDuJournal> fetchRepertoire() async {
    return const RepertoireDuJournal(
      modules: ['grades', 'payments', 'students'],
      auteurs: [
        AuteurDuJournal(id: 4, nom: 'Awa Traore', role: 'accountant'),
        AuteurDuJournal(id: 9, nom: 'Moussa Diallo', role: 'teacher'),
      ],
    );
  }

  @override
  Future<List<int>> exporter({
    required FiltreDuJournal filtre,
    required bool enExcel,
  }) async {
    exports.add('${enExcel ? 'excel' : 'pdf'}:${filtre.enRequete()}');
    return const [1, 2, 3];
  }
}

Future<_FauxDepot> _monter(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(2000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final depot = _FauxDepot();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [activityLogsRepositoryProvider.overrideWithValue(depot)],
      child: const MaterialApp(home: Scaffold(body: ActivityLogsPage())),
    ),
  );
  await tester.pumpAndSettle();
  return depot;
}

/// Choisit une entrée dans l'un des filtres déroulants.
Future<void> _choisir(
  WidgetTester tester,
  String cle,
  String entree,
) async {
  await tester.tap(find.byKey(Key(cle)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entree).last);
  await tester.pumpAndSettle();
}

void main() {
  group('Les filtres qui manquaient', () {
    testWidgets('« qui a fait ça » se demande au serveur', (tester) async {
      final depot = await _monter(tester);

      await _choisir(tester, 'filtre-auteur', 'Moussa Diallo — Enseignant');

      expect(
        depot.requetes.any((requete) => requete['user'] == 9),
        isTrue,
        reason: 'le filtre d\'auteur devait partir au serveur',
      );
    });

    testWidgets('« que s_est-il passé dans ce module » aussi', (tester) async {
      final depot = await _monter(tester);

      await _choisir(tester, 'filtre-module', 'payments');

      expect(
        depot.requetes.any((requete) => requete['module'] == 'payments'),
        isTrue,
      );
    });

    testWidgets('le rôle se filtre par son nom, pas par son code', (
      tester,
    ) async {
      // L'écran affichait « accountant » là où l'école dit « Comptable ».
      final depot = await _monter(tester);

      await _choisir(tester, 'filtre-role', 'Comptable');

      expect(
        depot.requetes.any((requete) => requete['role'] == 'accountant'),
        isTrue,
      );
    });

    testWidgets('les modules proposés viennent du journal, pas d_une liste', (
      tester,
    ) async {
      await _monter(tester);

      await tester.tap(find.byKey(const Key('filtre-module')));
      await tester.pumpAndSettle();

      for (final module in ['grades', 'payments', 'students']) {
        expect(find.text(module).last, findsOneWidget);
      }
    });

    testWidgets('on revient à la liste entière d_un geste', (tester) async {
      // Le bouton n'apparaît qu'une fois un filtre posé, et disparaît quand
      // il n'y a plus rien à réinitialiser: c'est ce qui dit à l'utilisateur
      // qu'il voit bien le journal entier.
      final depot = await _monter(tester);

      expect(find.byKey(const Key('reinitialiser-filtres')), findsNothing);

      await _choisir(tester, 'filtre-module', 'payments');
      expect(find.byKey(const Key('reinitialiser-filtres')), findsOneWidget);

      await tester.tap(find.byKey(const Key('reinitialiser-filtres')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reinitialiser-filtres')), findsNothing);
      // La requête sans filtre était déjà servie et reste en cache: on vérifie
      // qu'elle a bien été posée sans module, non qu'elle reparte.
      expect(depot.requetes.first.containsKey('module'), isFalse);
    });
  });

  group('Ce que l_écran donne à voir', () {
    testWidgets('les refus se comptent sans lire le tableau', (tester) async {
      // Un journal d'audit se lit d'abord par ses échecs.
      await _monter(tester);

      expect(find.text('Refusés'), findsOneWidget);
      expect(find.text('Événements'), findsOneWidget);
    });

    testWidgets('le rôle se lit en clair dans le tableau', (tester) async {
      await _monter(tester);

      expect(find.text('Comptable'), findsWidgets);
      expect(find.text('Enseignant'), findsWidgets);
    });

    testWidgets('le détail d_un refus dit pourquoi', (tester) async {
      await _monter(tester);

      await tester.tap(find.byKey(const ValueKey('detail-2')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Periode deja validee'), findsOneWidget);
      expect(find.text('403'), findsWidgets);
    });
  });

  group('Les exports', () {
    testWidgets('ils reprennent exactement les filtres affichés', (
      tester,
    ) async {
      // Un journal exporté plus large que ce qu'on regardait ne prouve rien.
      final depot = await _monter(tester);

      await _choisir(tester, 'filtre-module', 'payments');
      await tester.tap(find.byKey(const Key('export-excel')));
      // Pas de `pumpAndSettle` ici: la barre de progression de l'export
      // s'anime en boucle et l'attente ne se stabiliserait jamais.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));

      expect(depot.exports.single, contains('payments'));
      expect(depot.exports.single, startsWith('excel'));
    });
  });
}
