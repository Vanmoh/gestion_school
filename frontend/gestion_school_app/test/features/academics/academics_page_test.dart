/// Le socle academique et ses droits d'ecriture.
///
/// L'ecran ne lisait aucun droit: la matrice met le promoteur et
/// l'enseignant en lecture seule sur l'academique, et tous deux recevaient
/// les boutons « Creer annee », « Creer matiere » et « Creer classe », pour
/// se faire refuser au clic.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/core/network/token_storage.dart';
import 'package:gestion_school_app/features/academics/presentation/academics_page.dart';
import 'package:gestion_school_app/models/etablissement.dart';

class _Transport implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/academic-years/')) {
      return _json({
        'results': [
          {'id': 1, 'name': '2025-2026', 'is_active': true},
        ],
      });
    }
    if (options.path.contains('/classrooms/')) {
      return _json({
        'results': [
          {
            'id': 7,
            'name': '6e A',
            'academic_year': 1,
            'student_count': 32,
          },
          {
            'id': 8,
            'name': '5e B',
            'academic_year': 1,
            'student_count': 28,
          },
        ],
      });
    }
    if (options.path.contains('/subjects/')) {
      return _json({
        'results': [
          {
            'id': 11,
            'name': 'Mathématiques',
            'code': 'MATH',
            'coefficient': '2.00',
            'classroom': 7,
            'classroom_name': '6e A',
          },
        ],
      });
    }
    return _json(const {'results': []});
  }

  ResponseBody _json(Object data) => ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

ModulePermissions _droits(AccessLevel niveau) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'academics': ModulePermission(
        key: 'academics',
        label: 'Academique',
        group: 'academique',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<void> _monter(WidgetTester tester, AccessLevel niveau) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _Transport();

  // Sans etablissement actif, la page ne charge ni classe ni matiere: la
  // recherche n'aurait alors rien a trouver.
  final etablissements = EtablissementProvider(TokenStorage(), dio);
  final actif = Etablissement(id: 3, name: 'LTOB');
  etablissements.setEtablissements([actif]);
  await etablissements.selectEtablissement(actif);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
        etablissementProvider.overrideWith((ref) => etablissements),
      ],
      child: const MaterialApp(home: Scaffold(body: AcademicsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('un profil en lecture seule n_obtient aucune creation', (
    tester,
  ) async {
    await _monter(tester, AccessLevel.read);

    expect(find.byKey(const Key('creer-annee')), findsNothing);
    expect(find.byKey(const Key('creer-matiere')), findsNothing);
    expect(find.byKey(const Key('creer-classe')), findsNothing);
    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsOneWidget,
    );
  });

  testWidgets('la direction dispose des trois creations', (tester) async {
    await _monter(tester, AccessLevel.admin);

    expect(find.byKey(const Key('creer-annee')), findsOneWidget);
    expect(find.byKey(const Key('creer-matiere')), findsOneWidget);
    expect(find.byKey(const Key('creer-classe')), findsOneWidget);
    expect(
      find.text('Mode lecture seule: consultation uniquement pour ce profil.'),
      findsNothing,
    );
  });

  testWidgets('actualiser reste offert a tous', (tester) async {
    // Recharger n'est pas ecrire: le retirer aurait laisse les profils en
    // consultation devant une page qu'ils ne peuvent pas rafraichir.
    await _monter(tester, AccessLevel.read);

    final bouton = find.ancestor(
      of: find.text('Actualiser'),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(bouton, findsWidgets);
    expect((tester.widget(bouton.first) as ButtonStyleButton).onPressed, isNotNull);
  });

  group('recherche unifiée', () {
    Future<void> chercher(WidgetTester tester, String terme) async {
      await tester.enterText(find.byType(TextField).first, terme);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('sans recherche, la page invite au lieu d_ouvrir une palette', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.admin);

      expect(
        find.text(
          'Recherchez une classe ou une matière pour ouvrir sa palette.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('une classe trouvee seule ouvre sa palette', (tester) async {
      // Une reponse unique n_a pas a etre confirmee d_un clic, comme chez les
      // eleves.
      await _monter(tester, AccessLevel.admin);
      await chercher(tester, '5e B');

      expect(find.text('28 élèves'), findsOneWidget);
    });

    testWidgets('la palette d_une classe liste ses matieres', (tester) async {
      await _monter(tester, AccessLevel.admin);
      await chercher(tester, '6e A');

      // « 6e A » ramene la classe et sa matiere: deux resultats, donc un choix.
      // On vise la tuile par son icone: le libelle « 6e A » sert aussi de
      // sous-titre a la matiere, et de nom de colonne dans le tableau du bas.
      final tuileClasse = find.ancestor(
        of: find.byIcon(Icons.meeting_room_outlined),
        matching: find.byType(ListTile),
      );
      await tester.tap(tuileClasse.first);
      await tester.pump();

      expect(find.text('Mathématiques · MATH'), findsOneWidget);
    });

    testWidgets('une matiere se trouve par son code', (tester) async {
      await _monter(tester, AccessLevel.admin);
      await chercher(tester, 'MATH');

      expect(find.text('Matière'), findsWidgets);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('une recherche infructueuse cite ce qui a ete cherche', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.admin);
      await chercher(tester, 'Zzz');

      expect(find.text('Rien ne correspond à « Zzz ».'), findsOneWidget);
    });

    testWidgets('un profil en lecture seule ne peut pas modifier', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.read);
      await chercher(tester, '5e B');

      final modifier = find.ancestor(
        of: find.text('Modifier'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(modifier, findsOneWidget);
      expect(
        (tester.widget(modifier.first) as ButtonStyleButton).onPressed,
        isNull,
      );
    });
  });
}
