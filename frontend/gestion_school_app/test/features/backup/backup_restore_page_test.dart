/// L'écran de sauvegarde : ce qu'il embarque, ce qu'il montre, ce qu'il efface.
///
/// Le module archivait tout le dossier des médias sans rien dire du volume,
/// sans montrer d'avancement, et sans offrir de retirer une archive. Sur une
/// base dont la bibliothèque pèse plusieurs giga-octets, cela donnait une
/// opération interminable, muette, et un disque qui se remplit.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/backup/presentation/backup_restore_page.dart';

class _Transport implements HttpClientAdapter {
  _Transport({this.archives = const []});

  final List<Map<String, dynamic>> archives;
  final List<RequestOptions> envoyees = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    envoyees.add(options);

    if (options.path.contains('/volumes/')) {
      return _json(const {
        'media_hors_bibliotheque_octets': 7340032,
        'bibliotheque_octets': 6227702579,
        'media_total_octets': 6235042611,
        'archives_nombre': 2,
        'archives_octets': 2048,
      });
    }
    if (options.path.contains('/purge/')) {
      return _json(const {
        'supprimees': 2,
        'octets_liberes': 2048,
        'conservees': 1,
      });
    }
    if (options.method == 'DELETE') {
      return _json(const {}, code: 204);
    }
    if (options.method == 'POST') {
      return _json(const {'id': 99, 'status': 'pending'}, code: 202);
    }
    return _json({'results': archives});
  }

  ResponseBody _json(Object data, {int code = 200}) => ResponseBody.fromString(
    jsonEncode(data),
    code,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

ModulePermissions _droits(AccessLevel niveau) => ModulePermissions(
  role: 'super_admin',
  modules: {
    'backup_restore': ModulePermission(
      key: 'backup_restore',
      label: 'Backup & Restore',
      group: 'administration',
      level: niveau,
      scoped: false,
    ),
  },
);

Future<_Transport> _monter(
  WidgetTester tester, {
  List<Map<String, dynamic>> archives = const [],
  AccessLevel niveau = AccessLevel.admin,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1400, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(archives: archives);
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
      ],
      child: const MaterialApp(home: Scaffold(body: BackupRestorePage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

Map<String, dynamic> _archive({
  int id = 1,
  String status = 'completed',
  String buildPhase = 'Terminee',
  int buildProgress = 100,
  int bytesDone = 0,
  int bytesTotal = 0,
  String? buildStartedAt,
  String restorePhase = '',
}) => {
  'id': id,
  'filename': 'backup_global_$id.zip',
  'file_path': '/tmp/backup_global_$id.zip',
  'scope': 'global',
  'status': status,
  'file_size_bytes': 1024,
  'created_at': '2026-09-01T10:00:00Z',
  'build_phase': buildPhase,
  'build_progress': buildProgress,
  'bytes_done': bytesDone,
  'bytes_total': bytesTotal,
  'build_started_at': buildStartedAt,
  'restore_phase': restorePhase,
  'restore_progress': 0,
  'restore_log': '',
};

void main() {
  group('le choix de ce qu on emporte', () {
    testWidgets('la bibliothèque est décochée au départ', (tester) async {
      // C'est elle qui pèse : cochée par défaut, chaque sauvegarde emportait
      // des giga-octets d'annales réimportables.
      await _monter(tester);

      final bascule = tester.widget<SwitchListTile>(
        find.byKey(const Key('inclure-bibliotheque')),
      );
      expect(bascule.value, isFalse);
    });

    testWidgets('l écran annonce le volume de chaque part', (tester) async {
      await _monter(tester);

      expect(find.textContaining('7.0 Mo'), findsOneWidget);
      expect(find.textContaining('5.8 Go'), findsOneWidget);
    });

    testWidgets('sans médias, la bibliothèque ne se coche pas', (tester) async {
      await _monter(tester);

      await tester.tap(find.text('Inclure les médias'));
      await tester.pump();

      final bascule = tester.widget<SwitchListTile>(
        find.byKey(const Key('inclure-bibliotheque')),
      );
      expect(bascule.onChanged, isNull);
    });

    testWidgets('la demande porte le choix de la bibliothèque', (tester) async {
      final transport = await _monter(tester);

      await tester.tap(find.text('Lancer la sauvegarde'));
      await tester.pump(const Duration(milliseconds: 600));

      final creation = transport.envoyees.firstWhere(
        (options) => options.method == 'POST',
      );
      expect(creation.data['include_library_documents'], isFalse);
      expect(creation.data['include_media'], isTrue);
    });
  });

  group('l avancement', () {
    testWidgets('il montre le pourcentage, le volume et le reste', (
      tester,
    ) async {
      // Une barre sans chiffres ne dit pas s'il reste dix secondes ou dix
      // minutes : c'est précisément ce qu'on veut savoir.
      final depart = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 10))
          .toIso8601String();
      await _monter(
        tester,
        archives: [
          _archive(
            status: 'running',
            buildPhase: 'Medias (12/40)',
            buildProgress: 42,
            bytesDone: 4194304,
            bytesTotal: 10485760,
            buildStartedAt: depart,
          ),
        ],
      );

      expect(find.text('42%'), findsOneWidget);
      expect(find.textContaining('4.0 Mo sur 10 Mo'), findsOneWidget);
      expect(find.textContaining('Medias (12/40)'), findsOneWidget);
      expect(find.textContaining('reste'), findsOneWidget);
    });

    testWidgets('une restauration reste annoncée comme telle', (tester) async {
      // Les deux opérations ont leurs propres champs : sans distinction,
      // l'écran afficherait l'avancement de l'écriture pendant une
      // restauration.
      await _monter(
        tester,
        archives: [
          _archive(
            status: 'running',
            restorePhase: 'Import des données',
          ),
        ],
      );

      expect(
        find.textContaining('Restauration • Import des données'),
        findsOneWidget,
      );
    });
  });

  group('le ménage', () {
    testWidgets('une archive terminée se supprime, après confirmation', (
      tester,
    ) async {
      final transport = await _monter(tester, archives: [_archive()]);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer cette archive ?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirmer-suppression-archive')));
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        transport.envoyees.any((options) => options.method == 'DELETE'),
        isTrue,
      );
    });

    testWidgets('une sauvegarde en cours ne se supprime pas', (tester) async {
      await _monter(
        tester,
        archives: [_archive(status: 'running', buildProgress: 30)],
      );

      final bouton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_outline),
          matching: find.byType(IconButton),
        ),
      );
      expect(bouton.onPressed, isNull);
    });

    testWidgets('le nettoyage groupé apparaît dès deux archives', (
      tester,
    ) async {
      await _monter(tester, archives: [_archive(id: 1), _archive(id: 2)]);

      expect(find.byKey(const Key('nettoyer-historique')), findsOneWidget);
    });

    testWidgets('une seule archive ne se nettoie pas', (tester) async {
      // Un ménage qui viderait l'historique n'est pas un ménage.
      await _monter(tester, archives: [_archive()]);

      expect(find.byKey(const Key('nettoyer-historique')), findsNothing);
    });

    testWidgets('la direction ne voit ni suppression ni nettoyage', (
      tester,
    ) async {
      await _monter(
        tester,
        archives: [_archive(id: 1), _archive(id: 2)],
        niveau: AccessLevel.read,
      );

      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byKey(const Key('nettoyer-historique')), findsNothing);
    });
  });
}
