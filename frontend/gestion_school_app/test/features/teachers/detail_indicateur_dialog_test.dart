/// Le detail derriere les indicateurs de la palette enseignant.
///
/// Les trois tuiles annoncaient des nombres sans jamais dire de quoi ils
/// etaient faits: « 8 creneaux » sans un jour ni une heure, « 2 retards » sans
/// une date. Ces vues montrent ce que la page avait deja charge.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/teachers/presentation/widgets/detail_indicateur_dialog.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget corps, {
  Size taille = const Size(1000, 900),
}) async {
  tester.view.physicalSize = taille;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: corps)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('DetailAffectations', () {
    testWidgets('groupe les matieres par classe', (tester) async {
      // La meme matiere revient dans plusieurs classes: c'est la classe qui
      // organise la lecture, pas la matiere.
      await _pump(
        tester,
        const DetailAffectations(
          affectations: [
            {
              'subject_name': 'Mathématiques',
              'subject_code': 'MATH',
              'classroom_name': '6e A',
            },
            {
              'subject_name': 'Physique',
              'subject_code': 'PHY',
              'classroom_name': '6e A',
            },
            {
              'subject_name': 'Mathématiques',
              'subject_code': 'MATH',
              'classroom_name': '5e B',
            },
          ],
        ),
      );

      expect(find.text('6E A'), findsOneWidget);
      expect(find.text('5E B'), findsOneWidget);
      expect(find.text('Mathématiques'), findsNWidgets(2));
      expect(find.text('Physique'), findsOneWidget);
    });

    testWidgets('sans affectation, il le dit', (tester) async {
      await _pump(tester, const DetailAffectations(affectations: []));

      expect(
        find.text('Aucune matière affectée à cet enseignant.'),
        findsOneWidget,
      );
    });

    testWidgets('une classe absente ne fait pas disparaitre la ligne', (
      tester,
    ) async {
      await _pump(
        tester,
        const DetailAffectations(
          affectations: [
            {'subject_name': 'Anglais', 'classroom_name': ''},
          ],
        ),
      );

      expect(find.text('CLASSE INCONNUE'), findsOneWidget);
      expect(find.text('Anglais'), findsOneWidget);
    });
  });

  group('DetailEmploiDuTemps', () {
    const creneaux = [
      {
        'assignment': 1,
        'day_of_week': 'WED',
        'start_time': '10:00:00',
        'end_time': '12:00:00',
        'classroom_name': '5e B',
        'subject_code': 'PHY',
        'room': 'B2',
      },
      {
        'assignment': 1,
        'day_of_week': 'MON',
        'start_time': '08:00:00',
        'end_time': '10:00:00',
        'classroom_name': '6e A',
        'subject_code': 'MATH',
        'room': 'A1',
      },
      {
        'assignment': 1,
        'day_of_week': 'MON',
        'start_time': '14:00:00',
        'end_time': '15:00:00',
        'classroom_name': '6e A',
        'subject_code': 'MATH',
        'room': '',
      },
    ];

    testWidgets('les jours sortent dans l_ordre de la semaine', (tester) async {
      await _pump(tester, const DetailEmploiDuTemps(creneaux: creneaux));

      final lundi = tester.getTopLeft(find.text('LUNDI')).dy;
      final mercredi = tester.getTopLeft(find.text('MERCREDI')).dy;
      expect(lundi, lessThan(mercredi));
    });

    testWidgets('les creneaux d_un jour sont ranges par heure', (tester) async {
      await _pump(tester, const DetailEmploiDuTemps(creneaux: creneaux));

      final matin = tester.getTopLeft(find.text('08:00 – 10:00')).dy;
      final apresMidi = tester.getTopLeft(find.text('14:00 – 15:00')).dy;
      expect(matin, lessThan(apresMidi));
    });

    testWidgets('l_heure se lit sans les secondes', (tester) async {
      await _pump(tester, const DetailEmploiDuTemps(creneaux: creneaux));

      expect(find.text('10:00 – 12:00'), findsOneWidget);
      expect(find.textContaining('10:00:00'), findsNothing);
    });

    testWidgets('la salle et la duree accompagnent la classe', (tester) async {
      await _pump(tester, const DetailEmploiDuTemps(creneaux: creneaux));

      expect(find.text('6e A · Salle A1 · 2h'), findsOneWidget);
      // Sans salle renseignee, la mention disparait au lieu d_afficher un
      // « Salle » vide.
      expect(find.text('6e A · 1h'), findsOneWidget);
    });

    testWidgets('le total hebdomadaire est donne', (tester) async {
      await _pump(tester, const DetailEmploiDuTemps(creneaux: creneaux));

      expect(find.text('Total : 5h par semaine'), findsOneWidget);
    });

    testWidgets('l_intitule de la matiere vient de l_affectation', (
      tester,
    ) async {
      // Le creneau ne porte que le code: l_intitule se retrouve par
      // l_affectation, deja chargee.
      await _pump(
        tester,
        const DetailEmploiDuTemps(
          creneaux: creneaux,
          affectations: [
            {'id': 1, 'subject_name': 'Mathématiques'},
          ],
        ),
      );

      expect(find.text('Mathématiques'), findsNWidgets(3));
    });

    testWidgets('sans affectation connue, le code tient lieu d_intitule', (
      tester,
    ) async {
      await _pump(tester, const DetailEmploiDuTemps(creneaux: creneaux));

      expect(find.text('MATH'), findsNWidgets(2));
      expect(find.text('PHY'), findsOneWidget);
    });

    testWidgets('un creneau incoherent ne fausse pas le total', (tester) async {
      // Fin avant debut: la ligne s_affiche, mais elle ne compte pas.
      await _pump(
        tester,
        const DetailEmploiDuTemps(
          creneaux: [
            {
              'day_of_week': 'MON',
              'start_time': '10:00:00',
              'end_time': '08:00:00',
              'classroom_name': '6e A',
            },
          ],
        ),
      );

      expect(find.textContaining('Total :'), findsNothing);
      expect(find.text('10:00 – 08:00'), findsOneWidget);
    });

    testWidgets('un creneau hors disponibilite se signale', (tester) async {
      await _pump(
        tester,
        const DetailEmploiDuTemps(
          creneaux: [
            {
              'day_of_week': 'MON',
              'start_time': '08:00:00',
              'end_time': '10:00:00',
              'classroom_name': '6e A',
              'off_availability_reason': 'Indisponible le matin',
            },
          ],
        ),
      );

      expect(
        find.text('Hors disponibilité : Indisponible le matin'),
        findsOneWidget,
      );
    });

    testWidgets('un jour inconnu passe en fin sans disparaitre', (
      tester,
    ) async {
      await _pump(
        tester,
        const DetailEmploiDuTemps(
          creneaux: [
            {
              'day_of_week': 'XXX',
              'start_time': '08:00:00',
              'end_time': '09:00:00',
            },
            {
              'day_of_week': 'MON',
              'start_time': '08:00:00',
              'end_time': '09:00:00',
            },
          ],
        ),
      );

      expect(find.text('XXX'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('LUNDI')).dy,
        lessThan(tester.getTopLeft(find.text('XXX')).dy),
      );
    });

    testWidgets('sans creneau, il le dit', (tester) async {
      await _pump(tester, const DetailEmploiDuTemps(creneaux: []));

      expect(
        find.text('Aucun créneau au planning de cet enseignant.'),
        findsOneWidget,
      );
    });
  });

  group('DetailEmargement', () {
    testWidgets('les pointages vont du plus recent au plus ancien', (
      tester,
    ) async {
      await _pump(
        tester,
        const DetailEmargement(
          pointages: [
            {'entry_date': '2026-03-10', 'check_in_time': '08:00:00'},
            {'entry_date': '2026-03-12', 'check_in_time': '08:05:00'},
          ],
        ),
      );

      expect(
        tester.getTopLeft(find.text('12/03/2026')).dy,
        lessThan(tester.getTopLeft(find.text('10/03/2026')).dy),
      );
    });

    testWidgets('un retard ressort avec ses minutes', (tester) async {
      await _pump(
        tester,
        const DetailEmargement(
          pointages: [
            {
              'entry_date': '2026-03-12',
              'check_in_time': '08:20:00',
              'check_out_time': '12:00:00',
              'late_minutes': 20,
            },
          ],
        ),
      );

      expect(find.text('Retard de 20 min'), findsOneWidget);
      expect(find.text('08:20 – 12:00'), findsOneWidget);
    });

    testWidgets('une sortie non pointee se dit au lieu de rester vide', (
      tester,
    ) async {
      // Sans cette mention, la ligne se lit comme une journee de travail
      // nulle.
      await _pump(
        tester,
        const DetailEmargement(
          pointages: [
            {'entry_date': '2026-03-12', 'check_in_time': '08:00:00'},
          ],
        ),
      );

      expect(find.text('08:00 – sortie non pointée'), findsOneWidget);
    });

    testWidgets('une fermeture automatique donne son motif', (tester) async {
      await _pump(
        tester,
        const DetailEmargement(
          pointages: [
            {
              'entry_date': '2026-03-12',
              'check_in_time': '08:00:00',
              'check_out_time': '18:00:00',
              'is_auto_closed': true,
              'auto_closed_reason': 'Sortie oubliée',
            },
          ],
        ),
      );

      expect(
        find.text('Fermeture automatique : Sortie oubliée'),
        findsOneWidget,
      );
    });

    testWidgets('une liste au plafond du serveur l_annonce', (tester) async {
      // Sans ce mot, la page passerait pour l'historique entier.
      await _pump(
        tester,
        DetailEmargement(
          pointages: List.generate(
            plafondPageServeur,
            (index) => {
              'entry_date': '2026-03-12',
              'check_in_time': '08:00:00',
            },
          ),
        ),
        taille: const Size(1000, 4000),
      );

      expect(
        find.textContaining('pointages les plus récents'),
        findsOneWidget,
      );
    });

    testWidgets('une liste courte n_affiche aucun avertissement', (
      tester,
    ) async {
      await _pump(
        tester,
        const DetailEmargement(
          pointages: [
            {'entry_date': '2026-03-12', 'check_in_time': '08:00:00'},
          ],
        ),
      );

      expect(find.textContaining('pointages les plus récents'), findsNothing);
    });

    testWidgets('sans pointage, il le dit', (tester) async {
      await _pump(tester, const DetailEmargement(pointages: []));

      expect(
        find.text('Aucun pointage enregistré pour cet enseignant.'),
        findsOneWidget,
      );
    });
  });

  group('formats', () {
    test('les horaires et durees se lisent comme sur un planning', () {
      expect(heureLisible('08:30:00'), '08:30');
      expect(heureLisible('08:30'), '08:30');
      expect(heureLisible(null), '');
      // Une valeur inattendue se rend telle quelle plutot que de disparaitre.
      expect(heureLisible('midi'), 'midi');

      expect(dureeLisible(120), '2h');
      expect(dureeLisible(90), '1h30');
      expect(dureeLisible(45), '45 min');
      expect(dureeLisible(0), '');

      expect(minutesDepuisMinuit('08:30:00'), 510);
      expect(minutesDepuisMinuit('bizarre'), isNull);

      expect(dateLisible('2026-03-12'), '12/03/2026');
      expect(dateLisible('pas-une-date'), 'pas-une-date');
    });
  });
}
