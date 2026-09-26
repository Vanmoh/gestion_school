import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 9 — l'élève, et une clôture courte.
///
/// Ses écrans sont ceux de sa famille, réduits à lui-même : c'est ainsi que la
/// matrice les définit. Le chapitre est donc bref à dessein — le répéter en
/// long après celui du parent n'apprendrait rien.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre de l_eleve', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'student',
      identifiant: 'eleve1',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        pilote.journal.dire(
          'L\'élève a son propre tableau de bord.',
          duree: const Duration(seconds: 4),
        );
        await pilote.poser(duree: const Duration(seconds: 3));

        if (await pilote.ouvrirLeModule(
          'grades',
          sousTitre: 'Ses notes, sa moyenne, son rang.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'timetable',
          sousTitre: 'Son emploi du temps, une fois publié par la direction.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule('exams')) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
