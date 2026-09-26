import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 8 — la famille, qui ne voit que son enfant.
///
/// Trois écrans lui sont propres : ses examens, ses absences, sa discipline.
/// Ce ne sont pas les écrans de l'administration réduits par un filtre, ce sont
/// d'autres écrans — et c'est ce que le chapitre montre.
///
/// Il n'a pas « Gestion des élèves » : la matrice l'en exclut. Il a « Dossier
/// élève », qui ne lui rend que ses enfants.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre du parent', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'parent',
      identifiant: 'parent1',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        pilote.journal.dire(
          'La famille arrive sur ce qui concerne son enfant.',
          duree: const Duration(seconds: 4),
        );
        await pilote.poser(duree: const Duration(seconds: 3));

        if (await pilote.ouvrirLeModule(
          'student_lookup',
          sousTitre: 'Le dossier de son enfant, et de lui seul.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'exams',
          sousTitre:
              'Les résultats publiés, et rien avant leur publication.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
        }

        if (await pilote.ouvrirLeModule(
          'attendance',
          sousTitre: 'Absences et retards, avec leur motif.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule('discipline')) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule(
          'finance',
          sousTitre: 'Ce qui a été versé, ce qui reste dû.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule(
          'communication',
          sousTitre: 'Les annonces qui s\'adressent aux familles.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
