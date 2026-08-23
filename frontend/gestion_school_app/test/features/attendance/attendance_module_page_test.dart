/// Une entree de menu, deux emargements, deux cles de droits distinctes.
///
/// Les fondre en une seule cle aurait oblige a choisir quelle population
/// perdre: le parent lit les absences de son enfant mais rien de l'emargement
/// des enseignants, le comptable l'inverse, le surveillant saisit les absences
/// sans voir l'emargement.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/api_client.dart';
import 'package:gestion_school_app/core/permissions/module_permissions.dart';
import 'package:gestion_school_app/features/attendance/presentation/attendance_module_page.dart';

/// Les vues d'onglet chargent leurs donnees au montage. Ce test porte sur la
/// structure des onglets, pas sur leur contenu: un transport muet suffit, et
/// evite de laisser des minuteurs en suspens.
class _TransportMuet implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(const []),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ModulePermissions _droits({
  AccessLevel eleves = AccessLevel.none,
  AccessLevel enseignants = AccessLevel.none,
}) {
  return ModulePermissions(
    role: 'test',
    modules: {
      'attendance': ModulePermission(
        key: 'attendance',
        label: 'Absences',
        group: 'pedagogie',
        level: eleves,
        scoped: false,
      ),
      'teacher_timesheet': ModulePermission(
        key: 'teacher_timesheet',
        label: 'Emargement enseignants',
        group: 'pedagogie',
        level: enseignants,
        scoped: false,
      ),
    },
  );
}

Future<void> _pump(WidgetTester tester, ModulePermissions droits) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  FlutterSecureStorage.setMockInitialValues({});
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _TransportMuet();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentPermissionsProvider.overrideWithValue(droits),
        dioProvider.overrideWithValue(dio),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AttendanceModulePage()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('les deux droits ouvrent les deux onglets', (tester) async {
    await _pump(
      tester,
      _droits(eleves: AccessLevel.write, enseignants: AccessLevel.read),
    );

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Élèves'), findsOneWidget);
    expect(find.text('Enseignants'), findsOneWidget);
  });

  testWidgets('un seul droit affiche la vue sans barre d_onglets', (
    tester,
  ) async {
    // Le surveillant saisit les absences et n'a rien sur l'emargement: une
    // barre d'onglets a un seul onglet n'aurait rien a proposer.
    await _pump(tester, _droits(eleves: AccessLevel.write));

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Enseignants'), findsNothing);
  });

  testWidgets('le droit enseignant seul n_ouvre pas l_onglet eleves', (
    tester,
  ) async {
    // Cas du comptable: l'emargement le concerne pour la paie, pas les
    // absences des eleves.
    await _pump(tester, _droits(enseignants: AccessLevel.read));

    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Élèves'), findsNothing);
  });

  testWidgets('sans aucun droit, la page le dit au lieu de rester vide', (
    tester,
  ) async {
    await _pump(tester, _droits());

    expect(find.textContaining('n’accède à aucun émargement'), findsOneWidget);
  });

  testWidgets('l_onglet eleves precede celui des enseignants', (tester) async {
    await _pump(
      tester,
      _droits(eleves: AccessLevel.write, enseignants: AccessLevel.write),
    );

    final eleves = tester.getTopLeft(find.text('Élèves')).dx;
    final enseignants = tester.getTopLeft(find.text('Enseignants')).dx;
    expect(eleves, lessThan(enseignants));
  });
}
