import 'package:flutter_test/flutter_test.dart';

import 'pilote.dart';

/// Chapitre 2 — le promoteur, et un chapitre volontairement court.
///
/// Le propriétaire de l'école voit presque tout et n'écrit presque nulle part :
/// la matrice de droits ne lui accorde l'écriture que sur la messagerie. Ce
/// chapitre montre donc **le bandeau « lecture seule »** qui coiffe chaque
/// écran, d'un module à l'autre.
///
/// Il reste maigre, et c'est le propos. L'étirer demanderait d'inventer des
/// gestes que l'application ne lui donne pas — aucun peuplement n'y changerait
/// rien, c'est une décision de produit.
void main() {
  PiloteDeDemonstration.preparerLeBinding();

  testWidgets('chapitre du promoteur', (tester) async {
    await jouerLaPrise(
      tester: tester,
      role: 'promoter',
      identifiant: 'promoteur',
      motDePasse: 'Password@123',
      gestes: (pilote) async {
        pilote.journal.dire(
          'Le propriétaire voit tout et ne touche à rien.',
          duree: const Duration(seconds: 5),
        );

        for (final module in ['finance', 'grades', 'students', 'timetable']) {
          if (await pilote.ouvrirLeModule(module)) {
            await pilote.souligner(
              find.textContaining('Lecture seule'),
              texte: 'Le bandeau le suit d\'un écran à l\'autre.',
              duree: const Duration(seconds: 3),
            );
          }
        }

        pilote.journal.dire(
          'Son seul geste : écrire à l\'équipe.',
          duree: const Duration(seconds: 4),
        );
        await pilote.poser(duree: const Duration(seconds: 3));
      },
    );
  }, timeout: const Timeout(Duration(minutes: 8)));
}
