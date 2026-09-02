/// La vue discipline des familles, montee de bout en bout.
///
/// Seule la logique de regroupement etait testee. La page, elle, lisait le
/// JSON de l'API a la main et ne prenait que la premiere reponse: rien ne
/// verifiait qu'elle affichait ce que le depot lui remettait.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/discipline/data/discipline_repository.dart';
import 'package:gestion_school_app/features/discipline/domain/discipline_incident.dart';
import 'package:gestion_school_app/features/discipline/presentation/discipline_controller.dart';
import 'package:gestion_school_app/features/discipline/presentation/parent_discipline_page.dart';

class _FauxDepot extends DisciplineRepository {
  final List<DisciplineIncident> incidents;
  final Object? erreur;

  _FauxDepot({this.incidents = const [], this.erreur}) : super(Dio());

  @override
  Future<List<DisciplineIncident>> fetchIncidents({
    String search = '',
    String status = '',
    String severity = '',
  }) async {
    if (erreur != null) throw erreur!;
    return incidents;
  }
}

Future<void> _monter(WidgetTester tester, _FauxDepot depot) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [disciplineRepositoryProvider.overrideWithValue(depot)],
      child: const MaterialApp(home: Scaffold(body: ParentDisciplinePage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

DioException _refus(int code) {
  final options = RequestOptions(path: '/discipline-incidents/');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: code),
  );
}

void main() {
  testWidgets('les incidents sont groupes par enfant', (tester) async {
    await _monter(
      tester,
      _FauxDepot(
        incidents: const [
          DisciplineIncident(
            id: 1,
            studentId: 3,
            studentFullName: 'Awa Traoré',
            studentMatricule: 'MAT-003',
            incidentDate: '2026-01-17',
            category: 'indiscipline',
            categoryLabel: 'Indiscipline',
            description: 'Bavardage répété.',
          ),
          DisciplineIncident(
            id: 2,
            studentId: 4,
            studentFullName: 'Bala Traoré',
            studentMatricule: 'MAT-004',
            incidentDate: '2026-01-12',
            category: 'retard',
            categoryLabel: 'Retard',
            description: 'Trois retards.',
            status: 'resolved',
            resolvedAt: '2026-01-15T10:00:00Z',
            sanction: 'Avertissement oral',
            parentNotified: true,
          ),
        ],
      ),
    );

    expect(find.text('Awa Traoré'), findsOneWidget);
    expect(find.text('Bala Traoré'), findsOneWidget);
    // Le libelle du referentiel, pas le code brut stocke en base.
    expect(find.text('Indiscipline'), findsOneWidget);
    expect(find.text('Retard'), findsOneWidget);
    expect(find.text('2 enfants concernes'), findsOneWidget);
    expect(find.text('1 en cours'), findsWidgets);
  });

  testWidgets('un incident clos annonce sa date de traitement', (tester) async {
    // « Traite » ne disait pas quand: pour une famille, c'est ce qui
    // distingue un dossier suivi d'un dossier range sans suite.
    await _monter(
      tester,
      _FauxDepot(
        incidents: const [
          DisciplineIncident(
            id: 2,
            studentId: 4,
            studentFullName: 'Bala Traoré',
            incidentDate: '2026-01-12',
            category: 'retard',
            categoryLabel: 'Retard',
            description: 'Trois retards.',
            status: 'resolved',
            resolvedAt: '2026-01-15T10:00:00Z',
          ),
        ],
      ),
    );

    expect(find.text('Traite le 15 janvier 2026'), findsOneWidget);
  });

  testWidgets('un refus de droits annonce les droits, pas une panne', (
    tester,
  ) async {
    await _monter(tester, _FauxDepot(erreur: _refus(403)));

    expect(
      find.text(
        'Le suivi disciplinaire n\'est pas accessible avec vos droits actuels.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Impossible de charger le suivi disciplinaire pour le moment.'),
      findsNothing,
    );
  });

  testWidgets('une panne serveur annonce une panne, pas un refus', (
    tester,
  ) async {
    await _monter(tester, _FauxDepot(erreur: _refus(500)));

    expect(
      find.text('Impossible de charger le suivi disciplinaire pour le moment.'),
      findsOneWidget,
    );
  });

  testWidgets('sans incident, la page rassure au lieu de rester vide', (
    tester,
  ) async {
    await _monter(tester, _FauxDepot());

    expect(
      find.text('Aucun incident disciplinaire enregistré. Rien a signaler.'),
      findsOneWidget,
    );
  });
}
