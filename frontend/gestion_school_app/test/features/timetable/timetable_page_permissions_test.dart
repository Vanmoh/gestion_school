/// Qui peut publier un emploi du temps, et qui ne le peut pas.
///
/// L'ecran melait deux sources: sept gardes d'action lisaient la matrice,
/// mais le mode lecture seule du rendu tenait sur `role == 'teacher'`. La
/// matrice met aussi le promoteur, le comptable et le surveillant en
/// lecture seule sur l'emploi du temps: tous trois recevaient des boutons
/// de publication actifs, pour un 403 au clic.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/timetable/presentation/timetable_page.dart';

class _Transport implements HttpClientAdapter {
  /// Les chemins appelés, pour vérifier qu'une question est bien posée au
  /// serveur — et non seulement qu'un bouton existe.
  final List<RequestOptions> appels = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    appels.add(options);
    final chemin = options.path;
    if (chemin.contains('for-planning')) {
      return _json(const {
        'day_of_week': 'MON',
        'day_label': 'Lundi',
        'start_time': '08:00',
        'end_time': '09:00',
        'preferred': [
          {'teacher': 40, 'teacher_name': 'Moussa Diallo', 'note': '', 'declared_start': '08:00', 'declared_end': '10:00'},
        ],
        'possible': [],
        'undeclared': [
          {'teacher': 41, 'teacher_name': 'Awa Traore', 'note': '', 'declared_start': null, 'declared_end': null},
        ],
        'unavailable': [],
      });
    }
    if (chemin.contains('/classrooms/')) {
      return _json({
        'results': [
          {'id': 10, 'name': '6A', 'academic_year': 1},
        ],
      });
    }
    if (chemin.contains('/subjects/')) {
      return _json({
        'results': [
          {'id': 20, 'name': 'Mathematiques', 'classroom': 10},
        ],
      });
    }
    if (chemin.contains('/teachers/')) {
      return _json({
        'results': [
          {'id': 40, 'user': 1, 'user_full_name': 'Moussa Diallo'},
        ],
      });
    }
    if (chemin.contains('/teacher-assignments/')) {
      return _json({
        'results': [
          {'id': 50, 'teacher': 40, 'subject': 20, 'classroom': 10},
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
      'timetable': ModulePermission(
        key: 'timetable',
        label: 'Emploi du temps',
        group: 'academique',
        level: niveau,
        scoped: false,
      ),
    },
  );
}

Future<_Transport> _monter(WidgetTester tester, AccessLevel niveau) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1600, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final transport = _Transport();
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = transport;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        currentPermissionsProvider.overrideWithValue(_droits(niveau)),
      ],
      child: const MaterialApp(home: Scaffold(body: TimetablePage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return transport;
}

/// Etat actif du bouton portant ce libelle.
bool? _onPressedDe(WidgetTester tester, String libelle) {
  final bouton = find.ancestor(
    of: find.text(libelle),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  if (bouton.evaluate().isEmpty) return null;
  return (tester.widget(bouton.first) as ButtonStyleButton).onPressed != null;
}

void main() {
  testWidgets('un profil en lecture seule ne peut pas publier', (tester) async {
    await _monter(tester, AccessLevel.read);

    for (final libelle in [
      'Publier + verrouiller',
      'Publier sans verrou',
      'Repasser brouillon',
    ]) {
      final actif = _onPressedDe(tester, libelle);
      if (actif != null) {
        expect(actif, isFalse, reason: '« $libelle » doit rester inerte');
      }
    }
  });

  testWidgets('la page se monte pour un profil en ecriture', (tester) async {
    // Le rendu complet est la garantie que le retrait du telechargement du
    // schema OpenAPI n'a pas casse la detection de l'API planning.
    await _monter(tester, AccessLevel.admin);

    expect(find.byType(TimetablePage), findsOneWidget);
  });

  group('qui est disponible sur ce créneau', () {
    // Le serveur savait répondre depuis longtemps; personne ne le lui
    // demandait. La collecte des disponibilités s'arrêtait à elle-même, et
    // celui qui posait un cours à la main plaçait à l'aveugle.

    /// Ouvre le dialogue d'ajout et renseigne le créneau.
    ///
    /// Les heures sont vides à l'ouverture, et le bouton refuse alors
    /// d'interroger le serveur: on ne demande pas qui est libre « de rien
    /// à rien ».
    Future<void> ouvrirEtRenseignerLesHeures(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final debut = find.widgetWithText(TextField, 'Heure début (HH:MM)');
      final fin = find.widgetWithText(TextField, 'Heure fin (HH:MM)');
      if (debut.evaluate().isEmpty || fin.evaluate().isEmpty) {
        fail('Le dialogue d\'ajout d\'horaire ne s\'est pas ouvert.');
      }
      await tester.enterText(debut, '08:00');
      await tester.enterText(fin, '09:00');
      await tester.pump();
    }

    testWidgets('des heures effacées ne posent aucune question', (
      tester,
    ) async {
      // Le dialogue arrive avec un créneau par défaut; ce test l'efface pour
      // éprouver le garde-fou: on ne demande pas qui est libre « de rien à
      // rien ».
      final transport = await _monter(tester, AccessLevel.admin);
      transport.appels.clear();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.widgetWithText(TextField, 'Heure début (HH:MM)'),
        '',
      );
      await tester.pump();
      await tester.tap(find.text('Qui est disponible sur ce créneau ?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        transport.appels.where((a) => a.path.contains('for-planning')),
        isEmpty,
      );
      // Le refus s'affiche par un bandeau qui s'efface au bout de trois
      // secondes: on le laisse partir, sinon son minuteur survit au test.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('la question part vraiment au serveur', (tester) async {
      final transport = await _monter(tester, AccessLevel.admin);
      transport.appels.clear();

      await ouvrirEtRenseignerLesHeures(tester);
      await tester.tap(find.text('Qui est disponible sur ce créneau ?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final demande = transport.appels
          .where((appel) => appel.path.contains('for-planning'))
          .toList();
      expect(demande, isNotEmpty, reason: 'la disponibilité doit être demandée');
      expect(demande.first.queryParameters['day'], isNotNull);
      expect(demande.first.queryParameters['start'], '08:00:00');
      expect(demande.first.queryParameters['end'], '09:00:00');
    });

    testWidgets('les quatre groupes sont montrés, silencieux compris', (
      tester,
    ) async {
      await _monter(tester, AccessLevel.admin);

      await ouvrirEtRenseignerLesHeures(tester);
      await tester.tap(find.text('Qui est disponible sur ce créneau ?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // « Sans réponse » est un groupe à part entière: ne rien avoir déclaré
      // n'est ni un oui ni un non.
      expect(find.textContaining('Volontaires'), findsOneWidget);
      expect(find.textContaining('Possibles'), findsOneWidget);
      expect(find.textContaining('Sans réponse'), findsOneWidget);
      expect(find.textContaining('Indisponibles'), findsOneWidget);
      expect(find.textContaining('Moussa Diallo'), findsWidgets);
    });
  });
}
