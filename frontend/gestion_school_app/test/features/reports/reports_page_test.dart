/// Les rapports, et ce que chaque profil peut en charger.
///
/// L'écran passe d'abord par une route unique, `/reports/context/`, qui rend
/// élèves, années et encaissements d'un coup sous le seul droit « rapports ».
/// Cette route portait en plus sa propre liste de rôles, écrite à la main et
/// plus étroite que la matrice : promoteur, censeur, surveillant et enseignant
/// voyaient l'entrée dans leur menu et l'écran leur était refusé. La liste a
/// été retirée — la matrice décide seule — et ce qu'ils y trouvent reste borné
/// côté serveur : ses classes pour l'enseignant, aucun encaissement pour qui
/// n'a pas les finances.
///
/// Il garde un chemin de repli — un appel par source — pour le jour où cette
/// route manquerait. C'est celui-là qui réclamait les encaissements, fermés au
/// censeur, au surveillant et à l'enseignant : le repli les aurait laissés
/// devant un écran mort. Il est désormais tolérant, et ces tests fixent les
/// deux chemins.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/reports/presentation/reports_page.dart';

class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];
  final Set<String> refusees;

  /// Simule un serveur sans la route agrégée: l'écran bascule alors sur ses
  /// appels séparés.
  final bool contextAbsente;

  _Transport({this.refusees = const {}, this.contextAbsente = false});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);

    if (refusees.any(options.path.contains)) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(requestOptions: options, statusCode: 403),
      );
    }

    if (options.path.contains('/reports/context')) {
      if (contextAbsente) {
        throw DioException(
          requestOptions: options,
          response: Response<dynamic>(requestOptions: options, statusCode: 404),
        );
      }
      return _json(const {
        'students': [
          {
            'id': 30,
            'matricule': 'M-001',
            'user_full_name': 'Awa Traoré',
            'classroom_name': '6ème A',
          },
        ],
        'academic_years': [],
        'payments': [],
      });
    }
    if (options.path.contains('/students')) {
      return _json(const {
        'results': [
          {
            'id': 30,
            'matricule': 'M-001',
            'user_full_name': 'Awa Traoré',
            'classroom_name': '6ème A',
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

ModulePermissions _droits({
  AccessLevel reports = AccessLevel.read,
  bool exports = false,
}) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'reports': ModulePermission(
        key: 'reports',
        label: 'Rapports',
        group: 'administration',
        level: reports,
        scoped: false,
      ),
    },
    capabilities: {Capacites.exportsSensibles: exports},
  );
}

Future<_Transport> _monter(
  WidgetTester tester, {
  Set<String> refusees = const {},
  bool contextAbsente = false,
  bool exports = false,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(
    refusees: refusees,
    contextAbsente: contextAbsente,
  );
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(exports: exports)),
      ],
      child: const MaterialApp(home: Scaffold(body: ReportsPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

void main() {
  testWidgets('la route unique suffit et sert tout le monde', (tester) async {
    final transport = await _monter(tester);

    expect(find.textContaining('Erreur chargement'), findsNothing);
    expect(find.text('Awa Traoré'), findsWidgets);
    // Elle porte le seul droit « rapports »: aucun appel séparé n'est requis.
    expect(
      transport.chemins.where((chemin) => chemin.contains('/payments')),
      isEmpty,
    );
  });

  testWidgets('sans droit sur les encaissements, l_écran tient debout', (
    tester,
  ) async {
    // Sur le chemin de repli, le censeur, le surveillant et l'enseignant
    // butaient sur les encaissements — fermés pour eux.
    await _monter(
      tester,
      refusees: {'/payments'},
      contextAbsente: true,
    );

    expect(find.textContaining('Erreur chargement'), findsNothing);
    expect(find.text('Awa Traoré'), findsWidgets);
  });

  testWidgets('sans le référentiel scolaire non plus', (tester) async {
    // Le parent et l'élève n'ont pas les années scolaires.
    await _monter(
      tester,
      refusees: {'/academic-years'},
      contextAbsente: true,
    );

    expect(find.textContaining('Erreur chargement'), findsNothing);
  });

  testWidgets('sans droit d_export, le bouton ne s_affiche pas', (
    tester,
  ) async {
    // Il s'affichait pour tous et ne refusait qu'au clic: le promoteur, le
    // censeur et le surveillant lisent les rapports sans pouvoir en sortir
    // un fichier nominatif.
    await _monter(tester);

    expect(find.text('Exporter Excel'), findsNothing);
    expect(
      find.textContaining('réservé à la direction'),
      findsOneWidget,
      reason: 'le motif du retrait se dit, sinon le bouton semble avoir disparu',
    );
  });

  testWidgets('avec le droit d_export, le bouton revient', (tester) async {
    await _monter(tester, exports: true);

    expect(find.text('Exporter Excel'), findsOneWidget);
  });

  testWidgets('les élèves sont demandés dans tous les cas', (tester) async {
    final transport = await _monter(
      tester,
      refusees: {'/payments'},
      contextAbsente: true,
    );

    expect(
      transport.chemins.where((chemin) => chemin.contains('/students')),
      isNotEmpty,
    );
  });
}
