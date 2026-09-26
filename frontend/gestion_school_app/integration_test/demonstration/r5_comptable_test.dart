import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 5 — le comptable, et la fin de la double validation.
///
/// Il vise au niveau deux la fiche que le censeur a visée au chapitre
/// précédent : c'est le seul endroit de la démonstration où deux rôles
/// accomplissent ensemble un geste qu'aucun ne peut accomplir seul.
///
/// Il n'a ni les notes, ni la discipline, ni les absences des élèves. Ce qu'il
/// n'a pas est aussi instructif que ce qu'il a.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre du comptable', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'accountant',
      identifiant: 'comptable',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        pilote.journal.dire(
          'La caisse du jour, et ce qui reste à recouvrer.',
          duree: const Duration(seconds: 4),
        );
        await pilote.poser(duree: const Duration(seconds: 3));

        if (await pilote.ouvrirLeModule(
          'finance',
          sousTitre: 'Encaisser, éditer le reçu, puis viser la paie.',
        )) {
          await pilote.poser(duree: const Duration(seconds: 4));
          pilote.journal.dire(
            'Le second visa de la paie : celui que le censeur ne peut pas donner.',
            duree: const Duration(seconds: 5),
          );
          await pilote.poser(duree: const Duration(seconds: 3));
        }

        if (await pilote.ouvrirLeModule(
          'reports',
          sousTitre: 'Reçus page par page, journal de caisse, exports.',
        )) {
          await pilote.soulignerLaCle(
            'export-journal-caisse',
            texte: 'Le journal de caisse, que rien n\'atteignait avant.',
          );
        }

        if (await pilote.ouvrirLeModule('canteen')) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }
        if (await pilote.ouvrirLeModule('stock')) {
          await pilote.poser(duree: const Duration(seconds: 3));
        }
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
