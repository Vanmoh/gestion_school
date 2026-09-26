/// Les écrans qui n'avaient aucun test d'interface.
///
/// Communication, Stock, Journal d'activité, Sauvegarde : quatre modules que
/// rien ne surveillait. Ce n'est pas une question d'hygiène — un remplacement
/// automatique y a récemment altéré des clés d'API sans que personne ne le
/// voie, parce qu'aucun test n'ouvrait ces écrans.
///
/// Ce fichier fixe le minimum vital pour chacun : il s'affiche, il survit à un
/// refus de droits sur une source annexe, et il dit ce qui ne va pas quand le
/// serveur tombe vraiment.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/activity_logs/presentation/activity_logs_page.dart';
import 'package:gestion_school_app/features/backup/presentation/backup_restore_page.dart';
import 'package:gestion_school_app/features/communication/presentation/communication_module_page.dart';
import 'package:gestion_school_app/features/stock/presentation/stock_page.dart';

class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];
  final Set<String> refusees;
  final int? codeDePanne;

  _Transport({this.refusees = const {}, this.codeDePanne});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add(options.path);

    if (codeDePanne != null) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: codeDePanne,
        ),
      );
    }
    if (refusees.any(options.path.contains)) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(requestOptions: options, statusCode: 403),
      );
    }
    return _json(const {'count': 0, 'results': []});
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

ModulePermissions _droits(Map<String, AccessLevel> niveaux) {
  return ModulePermissions(
    role: 'test',
    modules: {
      for (final entree in niveaux.entries)
        entree.key: ModulePermission(
          key: entree.key,
          label: entree.key,
          group: 'administration',
          level: entree.value,
          scoped: false,
        ),
    },
  );
}

Future<_Transport> _monter(
  WidgetTester tester,
  Widget ecran,
  Map<String, AccessLevel> niveaux, {
  Set<String> refusees = const {},
  int? codeDePanne,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1700, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(refusees: refusees, codeDePanne: codeDePanne);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(niveaux)),
      ],
      child: MaterialApp(home: Scaffold(body: ecran)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

void main() {
  group('Communication', () {
    /// Les onglets ne chargent qu'à leur ouverture.
    ///
    /// C'est voulu: la coque n'appelle pas les trois registres au montage,
    /// seulement celui qu'on regarde. Les tests doivent donc ouvrir l'onglet
    /// dont ils parlent, comme l'utilisateur le fait.
    /// On vise le `Tab` et non le texte: « Notifications » nomme aussi un
    /// indicateur de l'en-tête, et `find.text` en trouverait deux.
    Future<void> ouvrir(WidgetTester tester, String onglet) async {
      await tester.tap(find.widgetWithText(Tab, onglet));
      await tester.pumpAndSettle();
    }

    testWidgets('la passerelle SMS n_est ni offerte ni demandée sans droit', (
      tester,
    ) async {
      // Sept profils sur neuf n'ont pas cette clé: l'appeler pour eux ferait
      // tomber l'écran sur un 403. L'onglet lui-même n'apparaît pas — un
      // onglet visible mais vide se lit comme une panne.
      final transport = await _monter(
        tester,
        const CommunicationModulePage(),
        {'communication': AccessLevel.read, 'sms_config': AccessLevel.none},
      );

      expect(find.widgetWithText(Tab, 'Passerelle SMS'), findsNothing);
      expect(
        transport.chemins.where((chemin) => chemin.contains('/sms-providers')),
        isEmpty,
      );
      expect(find.textContaining('Erreur'), findsNothing);
    });

    testWidgets('elle est offerte et demandée à qui la configure', (
      tester,
    ) async {
      final transport = await _monter(
        tester,
        const CommunicationModulePage(),
        {'communication': AccessLevel.admin, 'sms_config': AccessLevel.admin},
      );

      expect(find.widgetWithText(Tab, 'Passerelle SMS'), findsOneWidget);
      await ouvrir(tester, 'Passerelle SMS');

      expect(
        transport.chemins.where((chemin) => chemin.contains('/sms-providers')),
        isNotEmpty,
      );
    });

    testWidgets('l_annuaire est demandé pour choisir un destinataire', (
      tester,
    ) async {
      // Il est ouvert à tout compte connecté, sans quoi aucun profil ne
      // pourrait désigner qui il veut joindre.
      final transport = await _monter(
        tester,
        const CommunicationModulePage(),
        {'communication': AccessLevel.admin, 'sms_config': AccessLevel.none},
      );

      await ouvrir(tester, 'Notifications');

      expect(
        transport.chemins.where(
          (chemin) => chemin.contains('/auth/users/directory'),
        ),
        isNotEmpty,
      );
    });

    testWidgets('les annonces sont demandées dès l_ouverture', (tester) async {
      final transport = await _monter(
        tester,
        const CommunicationModulePage(),
        {'communication': AccessLevel.read, 'sms_config': AccessLevel.none},
      );

      expect(
        transport.chemins.where((chemin) => chemin.contains('/announcements')),
        isNotEmpty,
      );
    });
  });

  group('Stock', () {
    testWidgets('l_écran s_affiche', (tester) async {
      await _monter(tester, const StockPage(), {'stock': AccessLevel.admin});

      expect(find.textContaining('Erreur'), findsNothing);
    });

    testWidgets('ses quatre sources sont demandées', (tester) async {
      final transport = await _monter(tester, const StockPage(), {
        'stock': AccessLevel.admin,
      });

      for (final route in [
        '/suppliers',
        '/stock-items',
        '/stock-movements',
        '/stock-items/low_stock',
      ]) {
        expect(
          transport.chemins.where((chemin) => chemin.contains(route)),
          isNotEmpty,
          reason: '$route aurait dû être demandée',
        );
      }
    });
  });

  group('Journal d_activité', () {
    testWidgets('l_écran s_affiche', (tester) async {
      await _monter(tester, const ActivityLogsPage(), {
        'activity_logs': AccessLevel.read,
      });

      expect(find.textContaining('Erreur chargement'), findsNothing);
    });

    testWidgets('le journal est demandé au serveur', (tester) async {
      final transport = await _monter(tester, const ActivityLogsPage(), {
        'activity_logs': AccessLevel.read,
      });

      expect(
        transport.chemins.where((chemin) => chemin.contains('/activity-logs')),
        isNotEmpty,
      );
    });
  });

  group('Sauvegarde', () {
    testWidgets('l_écran s_affiche', (tester) async {
      await _monter(tester, const BackupRestorePage(), {
        'backup_restore': AccessLevel.admin,
      });

      expect(find.textContaining('Erreur chargement'), findsNothing);
    });

    testWidgets('les archives sont demandées', (tester) async {
      final transport = await _monter(tester, const BackupRestorePage(), {
        'backup_restore': AccessLevel.admin,
      });

      expect(
        transport.chemins.where(
          (chemin) => chemin.contains('backup-archives'),
        ),
        isNotEmpty,
      );
    });
  });
}
