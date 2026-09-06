/// L'écran d'envoi des bulletins aux familles.
///
/// Ce qu'il doit tenir n'est pas d'afficher une liste, c'est de ne jamais
/// laisser partir un bulletin qui ne doit pas partir : sans accord de la
/// famille, sans notes, ou une seconde fois par inadvertance. Ces tests
/// fixent surtout ces refus, et la façon dont l'écran les explique.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/reports/presentation/bulletin_whatsapp_page.dart';

const _canalUrlLauncher = MethodChannel('plugins.flutter.io/url_launcher');

class _Transport implements HttpClientAdapter {
  final List<String> chemins = [];
  final List<Map<String, dynamic>> corps = [];

  /// Nombre de préparations déjà acceptées: la seconde répond 409, comme le
  /// serveur le fait pour un bulletin déjà parti.
  int preparationsAcceptees;
  final bool refuseSecondEnvoi;

  /// Code d'erreur rendu a tout appel: sert a verifier que l'ecran dit ce
  /// qui ne va pas au lieu de rester vide.
  final int? codeDePanne;

  _Transport({this.refuseSecondEnvoi = false, this.codeDePanne})
    : preparationsAcceptees = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    chemins.add('${options.method} ${options.path}');
    if (options.data is Map) {
      corps.add(Map<String, dynamic>.from(options.data as Map));
    }

    if (codeDePanne != null) {
      throw DioException(
        requestOptions: options,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: codeDePanne,
        ),
      );
    }

    if (options.path.contains('/whatsapp/') && options.method == 'GET') {
      return _json(const {
        'classroom_id': 7,
        'classroom_name': '6ème A',
        'term': 'T1',
        'academic_year': '2025-2026',
        'ready_count': 1,
        'blocked_count': 2,
        'students': [
          {
            'student_id': 30,
            'student_name': 'Awa Traoré',
            'matricule': 'M-001',
            'classroom_name': '6ème A',
            'parent_id': 5,
            'parent_name': 'Fatoumata Traoré',
            'parent_consent': true,
            'phone': '+22376123456',
            'can_send': true,
            'blocked_reason': '',
            'last_status': '',
            'already_sent': false,
          },
          {
            'student_id': 31,
            'student_name': 'Moussa Diallo',
            'matricule': 'M-002',
            'parent_id': 6,
            'parent_name': 'Sekou Diallo',
            'parent_consent': false,
            'phone': '+22366742232',
            'can_send': false,
            'blocked_reason':
                "Le parent n'a pas donné son accord pour recevoir les "
                'bulletins par WhatsApp.',
            'already_sent': false,
          },
          {
            'student_id': 32,
            'student_name': 'Bakary Koné',
            'matricule': 'M-003',
            'parent_id': null,
            'parent_name': '',
            'phone': '',
            'can_send': false,
            'blocked_reason': 'Aucun parent rattaché à cet élève.',
            'already_sent': false,
          },
        ],
      });
    }

    if (options.path.contains('/whatsapp/') && options.method == 'POST') {
      final forcer =
          options.data is Map && (options.data as Map)['force'] == true;
      if (refuseSecondEnvoi && preparationsAcceptees > 0 && !forcer) {
        throw DioException(
          requestOptions: options,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 409,
            data: const {
              'detail': 'Ce bulletin a déjà été envoyé le 03/09/2026 à 10:00.',
              'already_sent': true,
            },
          ),
        );
      }
      preparationsAcceptees += 1;
      return _json(const {
        'delivery_id': 99,
        'student_id': 30,
        'student_name': 'Awa Traoré',
        'phone': '+22376123456',
        'whatsapp_url': 'https://wa.me/22376123456?text=Bonjour',
        'message': 'Bonjour, voici le bulletin de Awa Traoré (6ème A) — T1.',
        'download_url': 'http://test.local/api/reports/bulletin-partage/30/1/T1/1/abc/',
        'expires_at': '2026-09-06T10:00:00Z',
      });
    }

    if (options.path.contains('/parents/')) {
      return _json(const {'id': 6});
    }

    return _json(const {});
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

ModulePermissions _droits({AccessLevel eleves = AccessLevel.write}) {
  return ModulePermissions(
    role: 'director',
    modules: {
      'bulletin_whatsapp': const ModulePermission(
        key: 'bulletin_whatsapp',
        label: 'Envoi des bulletins aux familles',
        group: 'administration',
        level: AccessLevel.write,
        scoped: false,
      ),
      'students': ModulePermission(
        key: 'students',
        label: 'Élèves',
        group: 'pedagogie',
        level: eleves,
        scoped: false,
      ),
    },
    capabilities: const {},
  );
}

Future<_Transport> _monter(
  WidgetTester tester, {
  bool refuseSecondEnvoi = false,
  AccessLevel eleves = AccessLevel.write,
  int? codeDePanne,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport(
    refuseSecondEnvoi: refuseSecondEnvoi,
    codeDePanne: codeDePanne,
  );
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(eleves: eleves)),
      ],
      child: const MaterialApp(
        home: BulletinWhatsAppPage(
          classroomId: 7,
          classroomName: '6ème A',
          academicYearId: 1,
          term: 'T1',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

void main() {
  final ouvertures = <String>[];

  setUp(() {
    ouvertures.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalUrlLauncher, (call) async {
          if (call.method == 'launch') {
            ouvertures.add(
              (call.arguments as Map)['url']?.toString() ?? '',
            );
            return true;
          }
          if (call.method == 'canLaunch') return true;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalUrlLauncher, null);
  });

  testWidgets('l_écran dit qui est joignable et qui ne l_est pas', (
    tester,
  ) async {
    await _monter(tester);

    expect(find.text('1 joignable(s)'), findsOneWidget);
    expect(find.text('2 à corriger'), findsOneWidget);
    expect(find.text('Awa Traoré'), findsOneWidget);
  });

  testWidgets('un refus est affiché avec son motif, pas seulement barré', (
    tester,
  ) async {
    // Une ligne grisée sans explication renvoie l'école chercher la cause
    // dans un autre écran, et l'envoi est abandonné.
    await _monter(tester);

    expect(
      find.textContaining("n'a pas donné son accord"),
      findsOneWidget,
    );
    expect(find.text('Aucun parent rattaché à cet élève.'), findsOneWidget);
  });

  testWidgets('seuls les élèves joignables offrent le bouton d_envoi', (
    tester,
  ) async {
    await _monter(tester);

    // Un seul des trois élèves peut recevoir son bulletin.
    expect(find.widgetWithText(FilledButton, 'Envoyer'), findsOneWidget);
  });

  testWidgets('l_envoi prépare le lien puis ouvre WhatsApp', (tester) async {
    final transport = await _monter(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      transport.chemins.any(
        (chemin) =>
            chemin.startsWith('POST') && chemin.contains('/whatsapp/'),
      ),
      isTrue,
    );
    expect(ouvertures.single, 'https://wa.me/22376123456?text=Bonjour');

    // L'application ne voit pas le message partir: elle demande à l'école de
    // le confirmer plutôt que d'afficher un envoi qu'elle n'a pas constaté.
    expect(find.text('Message envoyé'), findsOneWidget);
    expect(find.text('Je n\'ai pas pu envoyer'), findsOneWidget);
  });

  testWidgets('un second envoi demande confirmation avant de repartir', (
    tester,
  ) async {
    // Reprendre une classe le lendemain ne doit pas renvoyer trente fois le
    // même bulletin aux mêmes familles.
    final transport = await _monter(tester, refuseSecondEnvoi: true);

    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Confirmer le premier départ ramène le bouton d'envoi sur la ligne.
    await tester.tap(find.text('Message envoyé'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.widgetWithText(TextButton, 'Envoyer à nouveau'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Bulletin déjà envoyé'), findsOneWidget);
    expect(find.textContaining('déjà été envoyé le'), findsOneWidget);

    // Le bouton du dialogue, et non celui resté sur la ligne.
    await tester.tap(find.widgetWithText(FilledButton, 'Envoyer à nouveau'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(transport.corps.any((corps) => corps['force'] == true), isTrue);
  });

  testWidgets('quand le serveur tombe, l_écran le dit et propose de réessayer', (
    tester,
  ) async {
    // Un écran vide laisse croire à une classe sans élève, et l'école
    // renonce à l'envoi au lieu de rappeler l'administrateur.
    await _monter(tester, codeDePanne: 500);

    expect(find.text('Chargement impossible'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('sans droit sur les élèves, le contact ne se corrige pas ici', (
    tester,
  ) async {
    // Le bouton s'affichait pour tous et n'échouait qu'à l'enregistrement.
    await _monter(tester, eleves: AccessLevel.read);

    expect(find.text('Corriger le contact'), findsNothing);
  });

  testWidgets('le contact d_un parent se corrige sans quitter la liste', (
    tester,
  ) async {
    final transport = await _monter(tester);

    // Le premier élève bloqué a un parent rattaché: son contact est
    // corrigeable. Le second n'en a pas, et n'offre donc pas le bouton.
    expect(find.text('Corriger le contact'), findsOneWidget);

    await tester.tap(find.text('Corriger le contact'));
    await tester.pumpAndSettle();

    expect(find.text('Contact de Sekou Diallo'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '76 12 34 56');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      transport.chemins.any((chemin) => chemin.contains('/parents/6/')),
      isTrue,
    );
    // Le numéro part tel qu'il a été tapé: la mise au format international
    // vit côté serveur, seul endroit où cette règle existe.
    final envoi = transport.corps.firstWhere(
      (corps) => corps.containsKey('whatsapp_phone'),
    );
    expect(envoi['whatsapp_phone'], '76 12 34 56');
    expect(envoi['whatsapp_consent'], isTrue);
  });
}
