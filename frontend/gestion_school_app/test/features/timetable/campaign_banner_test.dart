import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/timetable/domain/availability.dart';
import 'package:gestion_school_app/features/timetable/presentation/widgets/campaign_banner.dart';

/// Le bandeau de collecte.
///
/// La collecte n'avait ni debut, ni fin, ni compte de repondants: personne ne
/// savait si elle etait encore ouverte, ni qui manquait a l'appel.
AvailabilityCampaign _campagne({
  bool ouverte = true,
  int total = 10,
  int repondu = 4,
  int joursRestants = 5,
  String instructions = '',
}) {
  final aujourdHui = DateTime.now();
  return AvailabilityCampaign(
    id: 1,
    label: 'Rentrée 2025-2026',
    academicYearName: '2025-2026',
    opensOn: aujourdHui.subtract(const Duration(days: 3)),
    closesOn: DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day)
        .add(Duration(days: joursRestants)),
    status: ouverte ? 'open' : 'closed',
    statusLabel: ouverte ? 'Ouverte' : 'Close',
    isOpen: ouverte,
    instructions: instructions,
    teachersTotal: total,
    teachersAnswered: repondu,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  AvailabilityCampaign? campagne,
  bool vueEnseignant = false,
  bool dejaRendu = false,
  VoidCallback? onRendre,
  VoidCallback? onRelancer,
  VoidCallback? onVoirLesReponses,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CampaignBanner(
            campagne: campagne,
            vueEnseignant: vueEnseignant,
            dejaRendu: dejaRendu,
            onRendre: onRendre,
            onRelancer: onRelancer,
            onVoirLesReponses: onVoirLesReponses,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('sans campagne, l_ecran le dit sans crier a la panne', (
    tester,
  ) async {
    await _pump(tester, campagne: null);

    expect(find.text('Aucune campagne de collecte'), findsOneWidget);
    expect(
      find.textContaining('restent enregistrées'),
      findsOneWidget,
    );
  });

  testWidgets('la collecte ouverte annonce son echeance', (tester) async {
    await _pump(tester, campagne: _campagne(joursRestants: 5));

    expect(find.text('Collecte ouverte'), findsOneWidget);
    expect(find.textContaining('encore 5 jours'), findsOneWidget);
  });

  testWidgets('le dernier jour se distingue du reste', (tester) async {
    await _pump(tester, campagne: _campagne(joursRestants: 0));

    expect(find.textContaining('dernier jour'), findsOneWidget);
  });

  testWidgets('une collecte close porte son statut', (tester) async {
    await _pump(tester, campagne: _campagne(ouverte: false));

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Collecte ouverte'), findsNothing);
  });

  group('vue administration', () {
    testWidgets('le taux de reponse est chiffre', (tester) async {
      await _pump(tester, campagne: _campagne(total: 10, repondu: 4));

      expect(find.text('4 / 10 enseignants ont répondu'), findsOneWidget);
    });

    testWidgets('la relance nomme le nombre de manquants', (tester) async {
      await _pump(
        tester,
        campagne: _campagne(total: 10, repondu: 4),
        onRelancer: () {},
      );

      expect(find.text('Relancer 6 manquants'), findsOneWidget);
    });

    testWidgets('sans manquant, aucune relance n_est proposee', (tester) async {
      await _pump(
        tester,
        campagne: _campagne(total: 10, repondu: 10),
        onRelancer: () {},
      );

      expect(find.textContaining('Relancer'), findsNothing);
    });

    testWidgets('relancer remonte l_action', (tester) async {
      var relances = 0;
      await _pump(
        tester,
        campagne: _campagne(),
        onRelancer: () => relances++,
      );

      await tester.tap(find.textContaining('Relancer'));
      await tester.pump();

      expect(relances, 1);
    });

    testWidgets('le suivi des reponses reste accessible', (tester) async {
      var ouvertures = 0;
      await _pump(
        tester,
        campagne: _campagne(),
        onVoirLesReponses: () => ouvertures++,
      );

      await tester.tap(find.text('Suivi des réponses'));
      await tester.pump();

      expect(ouvertures, 1);
    });
  });

  group('vue enseignant', () {
    testWidgets('le taux de reponse des collegues ne le regarde pas', (
      tester,
    ) async {
      await _pump(tester, campagne: _campagne(), vueEnseignant: true);

      expect(find.textContaining('ont répondu'), findsNothing);
      expect(find.textContaining('Relancer'), findsNothing);
    });

    testWidgets('il peut rendre ses disponibilites', (tester) async {
      var rendus = 0;
      await _pump(
        tester,
        campagne: _campagne(),
        vueEnseignant: true,
        onRendre: () => rendus++,
      );

      await tester.tap(find.text('J’ai terminé mes disponibilités'));
      await tester.pump();

      expect(rendus, 1);
    });

    testWidgets('une fois rendu, le bouton cede la place a la confirmation', (
      tester,
    ) async {
      await _pump(
        tester,
        campagne: _campagne(),
        vueEnseignant: true,
        dejaRendu: true,
      );

      expect(find.text('J’ai terminé mes disponibilités'), findsNothing);
      expect(find.textContaining('ont été transmises'), findsOneWidget);
    });

    testWidgets('collecte close, on ne rend plus rien', (tester) async {
      await _pump(
        tester,
        campagne: _campagne(ouverte: false),
        vueEnseignant: true,
        onRendre: () {},
      );

      final bouton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'J’ai terminé mes disponibilités'),
      );
      expect(bouton.onPressed, isNull);
    });
  });

  testWidgets('les consignes de la direction s_affichent', (tester) async {
    await _pump(
      tester,
      campagne: _campagne(instructions: 'Merci de déclarer avant le conseil.'),
    );

    expect(find.text('Merci de déclarer avant le conseil.'), findsOneWidget);
  });

  test('sans enseignant, le taux ne vaut pas zero pour cent', () {
    // « 0 % » sur une ecole sans enseignant se lirait comme un manquement.
    expect(_campagne(total: 0, repondu: 0).tauxReponse, isNull);
  });
}
