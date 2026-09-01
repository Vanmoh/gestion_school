/// La paie enseignants, et qui l'atteint.
///
/// La matrice confie au censeur la validation de niveau 1 et donne a
/// l'enseignant sa propre fiche. Aucun des deux n'a de droit sur les finances
/// eleves -- et la paie vivait derriere leur chargement, dans le meme ecran.
/// Ils tombaient donc sur « Impossible de charger les frais eleves » au lieu
/// de la paie qu'ils venaient voir, et la double validation prevue (le censeur
/// genere, le comptable contresigne) ne pouvait pas avoir lieu.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/payments/presentation/payments_page.dart';

class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];

  /// Sert un reglement: sans donnee, un ecran de liste rend son message
  /// « aucun resultat » et ne prouve rien de la facon dont il presente les
  /// lignes.
  final bool avecReglement;

  _Transport({this.avecReglement = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);
    if (avecReglement && options.path.contains('/payments')) {
      return _json(const {
        'count': 1,
        'results': [
          {
            'id': 1,
            'fee': 7,
            'amount': '25000',
            'method': 'Especes',
            'reference': 'REC-001',
            'student_full_name': 'Awa Traoré',
            'student_matricule': 'M-001',
            'classroom_name': '6ème A',
            'fee_type': 'Scolarité',
            'created_at': '2026-08-31T10:15:00Z',
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

ModulePermission _module(
  String cle,
  AccessLevel niveau, {
  bool scoped = false,
}) {
  return ModulePermission(
    key: cle,
    label: cle,
    group: 'finances',
    level: niveau,
    scoped: scoped,
  );
}

/// Les deux droits qui decident de cet ecran, tels que le backend les sert.
ModulePermissions _droits({
  required AccessLevel finance,
  required AccessLevel payroll,
  bool financeScoped = false,
}) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'finance': _module('finance', finance, scoped: financeScoped),
      'payroll': _module('payroll', payroll),
    },
  );
}

Future<_Transport> _monter(
  WidgetTester tester,
  ModulePermissions droits, {
  Size taille = const Size(2600, 3400),
  bool avecReglement = false,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(avecReglement: avecReglement);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(droits),
      ],
      child: const MaterialApp(home: Scaffold(body: PaymentsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

void main() {
  testWidgets('le censeur atteint la paie sans droit sur les frais eleves', (
    tester,
  ) async {
    await _monter(
      tester,
      _droits(finance: AccessLevel.none, payroll: AccessLevel.write),
    );

    expect(find.text('Paie horaire enseignants'), findsOneWidget);
    expect(find.textContaining('Impossible de charger les frais'), findsNothing);
  });

  testWidgets('sans droit sur les finances, aucun frais n_est demande', (
    tester,
  ) async {
    // Le chargement partait quand meme et revenait en 403: l'ecran d'erreur
    // remplacait la page entiere, paie comprise.
    final transport = await _monter(
      tester,
      _droits(finance: AccessLevel.none, payroll: AccessLevel.write),
    );

    expect(
      transport.chemins.where((chemin) => chemin.contains('/fees')),
      isEmpty,
    );
  });

  testWidgets('la caisse de l_ecole reste fermee au censeur', (tester) async {
    // Les depenses pendaient au droit « payroll », faute de condition propre:
    // ouvrir la page au censeur pour la paie lui aurait montre la tresorerie.
    await _monter(
      tester,
      _droits(finance: AccessLevel.none, payroll: AccessLevel.write),
    );

    expect(find.textContaining('Dépenses & sorties'), findsNothing);
    expect(find.text('Tresorerie nette'), findsNothing);
  });

  testWidgets('l_enseignant voit sa paie en lecture', (tester) async {
    await _monter(
      tester,
      _droits(finance: AccessLevel.none, payroll: AccessLevel.read),
    );

    expect(find.text('Paie horaire enseignants'), findsOneWidget);
  });

  testWidgets('sans finances ni paie, l_ecran le dit', (tester) async {
    await _monter(
      tester,
      _droits(finance: AccessLevel.none, payroll: AccessLevel.none),
    );

    expect(
      find.text('Aucune section des finances ne vous est ouverte.'),
      findsOneWidget,
    );
  });

  testWidgets('le comptable garde les frais eleves et la paie', (tester) async {
    final transport = await _monter(
      tester,
      _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
    );


    expect(
      transport.chemins.where((chemin) => chemin.contains('/fees')),
      isNotEmpty,
    );
    expect(
      find.text('Aucune section des finances ne vous est ouverte.'),
      findsNothing,
    );
  });

  group('les onglets du module', () {
    testWidgets('le comptable ouvre les quatre onglets', (tester) async {
      await _monter(
        tester,
        _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
      );

      // On vise l'onglet et non le texte: « Encaissements » et « Dépenses »
      // nomment aussi des indicateurs dans le corps de la page.
      expect(find.widgetWithText(Tab, 'Encaissements'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Impayés & relances'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Dépenses'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Paie enseignants'), findsOneWidget);
    });

    testWidgets('on arrive sur les encaissements, pas ailleurs', (
      tester,
    ) async {
      // Le geste le plus frequent ouvre l'ecran: c'est ce qui remplace le
      // defilement du haut en bas.
      await _monter(
        tester,
        _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
      );

      expect(find.textContaining('Encaissements & entrees'), findsOneWidget);
      expect(find.textContaining('KPI par classe'), findsNothing);
    });

    testWidgets('un seul onglet ouvert, pas de barre', (tester) async {
      // Le censeur n'a que la paie: une barre a un seul onglet ne propose
      // rien et vole une ligne d'ecran.
      await _monter(
        tester,
        _droits(finance: AccessLevel.none, payroll: AccessLevel.write),
      );

      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Paie horaire enseignants'), findsOneWidget);
    });

    testWidgets('la famille n_a qu_un onglet: ses frais', (tester) async {
      // Elle recevait l'ecran du comptable: recherche de reglements,
      // indicateurs par classe, relances, classement des retards.
      await _monter(
        tester,
        _droits(
          finance: AccessLevel.read,
          payroll: AccessLevel.none,
          financeScoped: true,
        ),
      );

      expect(find.text('Ce qui reste à payer'), findsOneWidget);
      expect(find.text('Règlements effectués'), findsOneWidget);
      // Un seul onglet: la barre n'a rien a proposer.
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('la famille ne voit pas le tableau de bord comptable', (
      tester,
    ) async {
      await _monter(
        tester,
        _droits(
          finance: AccessLevel.read,
          payroll: AccessLevel.none,
          financeScoped: true,
        ),
      );

      expect(find.textContaining('KPI par classe'), findsNothing);
      expect(find.textContaining('Historique des relances'), findsNothing);
      expect(find.textContaining('Dépenses & sorties'), findsNothing);
      expect(find.text('Paie horaire enseignants'), findsNothing);
    });
  });

  group('la ligne de synthèse', () {
    testWidgets('l_état de la caisse se lit en haut', (tester) async {
      await _monter(
        tester,
        _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
      );

      expect(find.text('Montant encaissé'), findsOneWidget);
      expect(find.text('Impayés'), findsOneWidget);
      expect(find.text('Trésorerie nette'), findsOneWidget);
    });

    testWidgets('sans les dépenses, pas de trésorerie', (tester) async {
      // Le solde net n'a aucun sens pour qui ne voit pas ce qui sort.
      await _monter(
        tester,
        _droits(
          finance: AccessLevel.read,
          payroll: AccessLevel.none,
          financeScoped: true,
        ),
      );

      expect(find.text('Impayés'), findsOneWidget);
      expect(find.text('Trésorerie nette'), findsNothing);
    });

    testWidgets('elle survit au changement d_onglet', (tester) async {
      // C'est tout son interet: le chiffre ne se cherche pas, il est la.
      await _monter(
        tester,
        _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
      );

      await tester.tap(find.widgetWithText(Tab, 'Dépenses'));
      await tester.pumpAndSettle();

      expect(find.text('Montant encaissé'), findsOneWidget);
      expect(find.text('Impayés'), findsOneWidget);
    });

    testWidgets('chaque chiffre ne porte qu_un nom', (tester) async {
      // « Solde restant » et « Impayés totaux » designaient la meme somme a
      // deux hauteurs de page.
      await _monter(
        tester,
        _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
      );

      expect(find.text('Solde restant'), findsNothing);
      expect(find.text('Impayés totaux'), findsNothing);
    });
  });

  group('les listes selon la largeur', () {
    testWidgets('sur grand écran, le tableau', (tester) async {
      await _monter(
        tester,
        _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
        avecReglement: true,
      );

      expect(find.byType(DataTable), findsWidgets);
      expect(find.text('Awa Traoré'), findsWidgets);
    });

    testWidgets('sur écran étroit, plus de tableau à faire défiler', (
      tester,
    ) async {
      // Neuf colonnes sur un téléphone se parcouraient latéralement — un
      // geste que l'application ne demande nulle part ailleurs.
      await _monter(
        tester,
        _droits(finance: AccessLevel.admin, payroll: AccessLevel.write),
        taille: const Size(700, 2200),
        avecReglement: true,
      );

      // Le reglement est toujours la, mais en fiche.
      expect(find.text('Awa Traoré'), findsWidgets);
      expect(find.byType(DataTable), findsNothing);
    });
  });
}
